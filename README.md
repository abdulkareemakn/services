# homelab

Every self-hosted service I run, as compose files. One repository, one ingress,
no port juggling.

This is the single source of truth. It replaced three separate directories that
had drifted apart: a large catalogue of compose files, a CI-driven VPS
deployment repo, and a small scratch directory of things actually running.

## How it works

One service publishes ports to this host: **Caddy**, on 80 and 443. Everything
else declares `expose:` and is reachable only through it, at
`https://<service>.localhost`.

```
browser ──https──> caddy  ──proxy network──>  memos:5230
                            ───────────────>  kaneo-app:5173
                            ───────────────>  sure-app:3000
```

Because Caddy resolves backends by `container_name` and nothing else binds a
host port, port conflicts are structurally impossible. Adding a service cannot
break an unrelated one.

## Getting set up on a new device

```bash
git clone git@github.com:abdulkareemakn/services.git ~/services
cd ~/services

cp apps/memos/.env.example apps/memos/.env     # per service, as needed
$EDITOR apps/memos/.env

sudo make trust # install the Caddy internal CA (once per device)
make up         # start everything
make ps         # see what came up
```

`make trust` prints the exact commands — it needs `sudo`, so it cannot run
unattended.

## Layout

```
infra/caddy/       the ingress; its Caddyfile is the routing table
infra/beszel/      host metrics
infra/dozzle/      container log viewer
infra/diun/        image update notifications
infra/litestream/  continuous SQLite replication to R2

apps/<service>/    one directory per service: compose.yaml + .env.example
```

See [CONVENTIONS.md](CONVENTIONS.md) for the rules every service follows.

## Everyday commands

```bash
make help                        # all targets
make ps                          # status of everything
make health                      # only unhealthy/restarting containers
make up SERVICE=memos            # start one
make down SERVICE=memos          # stop one
make logs SERVICE=memos          # tail one
make validate                    # config-check every file, no side effects
make diskspace                   # what is using /opt
make prune                       # reclaim disk
```

Each service is an independent compose project, so `make up` starts them
independently — one failure does not stop the rest.

## Secrets

`.env` files are gitignored and never committed. Each service that needs
configuration ships a `.env.example` documenting every key.

Local-only secrets are generated per device:

```bash
openssl rand -hex 32
```

Third-party credentials (API keys, object storage) go in `.env` by hand.

## Adding a service

1. `mkdir apps/<service>`, write `compose.yaml`, add `.env.example` if needed.
2. Add a route to `infra/caddy/Caddyfile`.
3. `make validate`.
4. Commit, then `make up SERVICE=<service>`.

Full checklist in [CONVENTIONS.md](CONVENTIONS.md#adding-a-service).

## Maintenance

`diun` watches for image updates and `litestream` replicates every SQLite
database to Cloudflare R2. Neither is a substitute for an actual restore test —
check that a replica can be turned back into a working database at least
occasionally.

Image updates are deliberately not automatic. A floating tag plus an unattended
restart can mean a breaking change with no commit to point at. Upgrade
deliberately: `make pull`, then `make up SERVICE=<name>`, then check the logs.