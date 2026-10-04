# Homelab service definitions.
#
# Everything is reached through the Caddy ingress; no application publishes a
# host port. Each service is an independent compose project under apps/ or
# infra/, so bring up only what you want running.

SHELL := /bin/bash
.DEFAULT_GOAL := help

NETWORK := proxy
COMPOSE_FILES := $(shell find apps infra -name compose.yaml 2>/dev/null | sort)

# Services that must be running before anything else is useful.
PREREQS := caddy

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

.PHONY: up
up: network ## Start all services (or SERVICE=name)
	@$(if $(SERVICE), \
		cd $(dir $(firstword $(wildcard apps/$(SERVICE) infra/$(SERVICE)))) && docker compose up -d, \
		for f in $(COMPOSE_FILES); do echo "  starting $$f"; docker compose -f $$f up -d || echo "  FAILED: $$f"; done)

.PHONY: down
down: ## Stop all services (or SERVICE=name)
	@$(if $(SERVICE), \
		cd $(dir $(firstword $(wildcard apps/$(SERVICE) infra/$(SERVICE)))) && docker compose down, \
		for f in $(COMPOSE_FILES); do docker compose -f $$f down || true; done)

.PHONY: restart
restart: ## Restart all services (or SERVICE=name)
	@$(if $(SERVICE), \
		cd $(dir $(firstword $(wildcard apps/$(SERVICE) infra/$(SERVICE)))) && docker compose restart, \
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
logs: ## Follow logs (or SERVICE=name)
	@$(if $(SERVICE), \
		cd $(dir $(firstword $(wildcard apps/$(SERVICE) infra/$(SERVICE)))) && docker compose logs -f --tail=100, \
		for f in $(COMPOSE_FILES); do echo "=== $$f"; docker compose -f $$f logs --tail=20; done)

# ─── Ingress ─────────────────────────────────────────────────────────────────

.PHONY: trust
trust: ## Trust the Caddy internal CA (required once per device, needs sudo)
	@./scripts/trust-ca.sh

.PHONY: reload-caddy
reload-caddy: ## Reload the Caddy config and report any errors
	@docker compose -f infra/caddy/compose.yaml exec -T caddy \
		caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile \
		&& echo "  caddy reloaded" || echo "  caddy reload FAILED - config is invalid"

.PHONY: validate-caddy
validate-caddy: ## Check the Caddyfile without applying it
	@docker run --rm -v "$(CURDIR)/infra/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
		caddy:2.10-alpine caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

# ─── Quality ─────────────────────────────────────────────────────────────────

.PHONY: validate
validate: ## Config-check every compose file and the Caddyfile
	@fail=0; \
	for f in $(COMPOSE_FILES); do \
		if docker compose -f $$f config --quiet 2>/tmp/err; then \
			printf "  \033[32mok\033[0m    %s\n" "$$f"; \
		else \
			printf "  \033[31mFAIL\033[0m  %s\n" "$$f"; sed 's/^/          /' /tmp/err; fail=1; \
		fi; \
	done; \
	$(MAKE) --no-print-directory validate-caddy; \
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