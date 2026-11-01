# Homelab service definitions.
#
# Everything is reached through the Caddy ingress; no application publishes a
# host port. Each service is an independent compose project under apps/ or
# infra/, so bring up only what you want running.

SHELL := /bin/bash
.DEFAULT_GOAL := help

NETWORK := proxy
COMPOSE_FILES := $(shell find apps infra -name compose.yaml 2>/dev/null | sort)

# Empty when SERVICE names no compose project. $(dir ...) cannot be used here:
# it strips the last component, turning apps/memos into apps/.
SERVICE_DIR := $(or $(wildcard apps/$(SERVICE)),$(wildcard infra/$(SERVICE)))

# Kept in a variable so validate need not recurse through make: $(MAKE)
# expands to whatever launched make, which is not always a make binary, and
# then the recursion fails on make's own flags.
CADDY_VALIDATE := docker run --rm \
	-v "$(CURDIR)/infra/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
	caddy:2.10-alpine caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

# ─── Help ────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@echo ""
	@echo "  Usage: make <target> [SERVICE=name]"
	@echo ""
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Examples:"
	@echo "    make up                 start every service"
	@echo "    make up SERVICE=memos   start one service"
	@echo "    make logs SERVICE=memos follow one service"
	@echo "    make validate           config-check every compose file"
	@echo ""

# ─── Lifecycle ───────────────────────────────────────────────────────────────

.PHONY: network
network: ## Create the shared proxy network if it does not exist
	@docker network inspect $(NETWORK) >/dev/null 2>&1 \
		|| docker network create $(NETWORK)
	@echo "network $(NETWORK) ready"

.PHONY: require-service
require-service: # fails when SERVICE names nothing under apps/ or infra/
	@test -z "$(SERVICE)" || test -n "$(SERVICE_DIR)" \
		|| { echo "  no such service: '$(SERVICE)'" >&2; exit 1; }

.PHONY: up
up: network require-service ## Start all services (or SERVICE=name)
	@$(if $(SERVICE), \
		cd $(SERVICE_DIR) && docker compose up -d, \
		for f in $(COMPOSE_FILES); do echo "  starting $$f"; docker compose -f $$f up -d || echo "  FAILED: $$f"; done)

.PHONY: down
down: require-service ## Stop all services (or SERVICE=name)
	@$(if $(SERVICE), \
		cd $(SERVICE_DIR) && docker compose down, \
		for f in $(COMPOSE_FILES); do docker compose -f $$f down || true; done)

.PHONY: restart
restart: require-service ## Restart all services (or SERVICE=name)
	@$(if $(SERVICE), \
		cd $(SERVICE_DIR) && docker compose restart, \
		for f in $(COMPOSE_FILES); do docker compose -f $$f restart || true; done)

.PHONY: pull
pull: ## Pull newer images for all services
	@for f in $(COMPOSE_FILES); do docker compose -f $$f pull || true; done

# ─── Inspection ──────────────────────────────────────────────────────────────

.PHONY: ps
ps: ## Show status of every service
	@printf "  %-34s %-10s %-9s %s\n" SERVICE PROJECT STATUS PORTS
	@for f in $(COMPOSE_FILES); do \
		dir=$$(dirname $$f); \
		docker compose -f $$f ps --format '{{.Service}}|{{.Name}}|{{.State}}|{{.Ports}}' 2>/dev/null \
		| while IFS='|' read -r svc name state ports; do \
			printf "  %-34s %-10s %-9s %s\n" "$$dir/$$svc" "$$name" "$$state" "$$ports"; \
		done; \
	done

.PHONY: health
health: ## Show only containers that are unhealthy or restarting
	@docker ps -a --filter health=unhealthy --format '  UNHEALTHY {{.Names}} ({{.Status}})' || true
	@docker ps -a --filter health=starting --format '  STARTING  {{.Names}}' || true
	@echo ""
	@echo "  (no output above means everything is healthy)"

.PHONY: logs
logs: require-service ## Follow logs (or SERVICE=name)
	@$(if $(SERVICE), \
		cd $(SERVICE_DIR) && docker compose logs -f --tail=100, \
		for f in $(COMPOSE_FILES); do echo "=== $$f"; docker compose -f $$f logs --tail=20; done)

# ─── Ingress ─────────────────────────────────────────────────────────────────

# The script is authoritative; this asserts its result because the failure mode
# is a silent no-op rather than an error.
.PHONY: trust
trust: ## Trust the Caddy internal CA (required once per device, needs sudo)
	@./scripts/trust-ca.sh
	@if [ "$$(uname -s)" = "Darwin" ]; then exit 0; fi; \
	if ! docker ps --format '{{.Names}}' | grep -qx caddy; then \
		echo "  note: caddy is not running, skipping the bundle check"; exit 0; \
	fi; \
	bundle=""; \
	for b in /etc/ssl/certs/ca-certificates.crt /etc/ssl/cert.pem; do \
		if [ -f "$$b" ]; then bundle="$$b"; break; fi; \
	done; \
	docker exec caddy cat /data/caddy/pki/authorities/local/root.crt \
		> /tmp/caddy-root-ca.pem 2>/dev/null; \
	openssl verify -CAfile "$$bundle" /tmp/caddy-root-ca.pem >/dev/null 2>&1 \
		|| { echo "  FAIL: $$bundle does not trust Caddy's CA"; \
		     echo "        services will still warn in the browser"; exit 1; }; \
	echo "  ok: $$bundle trusts Caddy's CA"

.PHONY: reload-caddy
reload-caddy: ## Reload the Caddy config and report any errors
	@docker compose -f infra/caddy/compose.yaml exec -T caddy \
		caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile \
		&& echo "  caddy reloaded" || echo "  caddy reload FAILED - config is invalid"

.PHONY: validate-caddy
validate-caddy: ## Check the Caddyfile without applying it
	@$(CADDY_VALIDATE)

# ─── Quality ─────────────────────────────────────────────────────────────────

.PHONY: validate
validate: ## Config-check every compose file and the Caddyfile
	@fail=0; err=$$(mktemp); \
	for f in $(COMPOSE_FILES); do \
		if docker compose -f $$f config --quiet 2>$$err; then \
			printf "  \033[32mok\033[0m    %s\n" "$$f"; \
		else \
			printf "  \033[31mFAIL\033[0m  %s\n" "$$f"; sed 's/^/          /' $$err; fail=1; \
		fi; \
	done; \
	rm -f $$err; \
	if $(CADDY_VALIDATE) >/dev/null 2>&1; then \
		printf "  \033[32mok\033[0m    %s\n" "infra/caddy/Caddyfile"; \
	else \
		printf "  \033[31mFAIL\033[0m  %s\n" "infra/caddy/Caddyfile"; fail=1; \
	fi; \
	echo ""; \
	if [ $$fail -eq 0 ]; then echo "  all compose files valid"; else echo "  errors above"; fi; \
	exit $$fail

# ─── Housekeeping ────────────────────────────────────────────────────────────

.PHONY: prune
prune: ## Remove dangling images and build cache
	@docker image prune -f
	@docker builder prune -f

.PHONY: diskspace
diskspace: ## Report /opt usage per service
	@du -sh /opt/*/ 2>/dev/null | sort -rh | head -30