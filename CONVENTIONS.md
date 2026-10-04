# Conventions

Every service in this repository follows the same rules. The point is that you
can read any `compose.yaml` and know what to expect without reading all of them.

## Layout

```
infra/     the homelab itself — ingress, metrics, logs, updates, backups
apps/      everything you actually use
```

Each service is a self-contained compose project with one file:

```
apps/<service>/compose.yaml
apps/<service>/.env.example
apps/<service>/.env          (gitignored, yours)
```

Adding a service means adding a directory. There is no top-level compose file
and no include mechanism — services stay independently startable.

## Images

Pin every tag. A floating `:latest` means an unattended restart can pick up a
breaking change with no commit to show for it.

```yaml
image: ghcr.io/usekaneo/kaneo:2.28.3    # good
image: neosmemo/memos:latest            # only when no upstream releases tags
```

Floating tags that remain are listed in `docs/floating-tags.md` with a reason.

## Container names

Always set `container_name`. Compose otherwise generates `<project>-<service>-1`,
which is unstable and tells you nothing.

Single-service stacks use the bare service name:

```yaml
services:
  memos:
    container_name: memos
```

Multi-service stacks prefix with the service name and suffix with the role, so
every container in the repo is identifiable at a glance in `docker ps`:

```yaml
services:
  kaneo-app:
    container_name: kaneo-app
  kaneo-db:
    container_name: kaneo-db
```

Known roles: `app`, `web`, `worker`, `db`, `redis`, `api`, `agent`, `proxy`.

### Network aliases

Renaming a container changes the DNS name your application uses to reach it.
Rather than editing application configuration, give the renamed container its
old name as a network alias:

```yaml
  kaneo-db:
    container_name: kaneo-db
    networks:
      proxy:
        aliases:
          - postgres
```

Kaneo resolves its database as `postgres` and exposes no variable to override
it, so the alias is what makes the rename safe. Prefer changing an explicit
config value where one exists; use an alias where the app hardcodes the name.

## Networking

There is exactly one published surface in this repo: Caddy on 80/443.

Every other service uses `expose:`, never `ports:`. Caddy routes on hostname
and resolves backends by `container_name` over the shared `proxy` network.

```yaml
services:
  memos:
    expose:
      - "5230"
    networks:
      - proxy

networks:
  proxy:
    external: true
    name: proxy
```

This means port conflicts are structurally impossible, and adding a service can
never break an unrelated one.

### The exception: non-HTTP protocols

Caddy only speaks HTTP. Anything else — git-over-SSH, a database client, a
raw TCP service — needs a real published port, bound to loopback:

```yaml
    ports:
      - "127.0.0.1:2222:2222"
```

Databases and queues are not an exception to publish: they are never published,
because the only client is a sibling container on `proxy`.

## Volumes

State lives under `/opt/<service>/`, never inside the repository.

| Path | Purpose |
|---|---|
| `/opt/<service>/app` | primary application state |
| `/opt/<service>/db` | postgres or sqlite data |
| `/opt/<service>/redis` | redis data, when the service uses one as a backend |
| `/opt/<service>/cache` | regenerable only, safe to delete |
| `/opt/<service>/config` | config files you edit by hand |
| `/opt/<service>/logs` | log files, when not sent to stdout |

Component-named directories are also acceptable where the component name is
clearer than the generic one — `/opt/karakeep/meili`, `/opt/many-notes/typesense`.

```yaml
    volumes:
      - /opt/memos/app:/var/opt/memos
```

Do not bind-mount a relative path. `./db/:/db` ties your data to the checkout
directory, which means a `git checkout` or a move can detach a live database.

## Restart policy

`restart: unless-stopped` on every long-running service. No exceptions in this
repo.

The difference from `always` matters: `always` restarts a container even if you
stopped it deliberately, so it comes back after a reboot and you have no idea
why. `unless-stopped` respects a manual stop.

For one-shot work — migrations, a backup job — use `on-failure` or `no`, never
`unless-stopped`. A job that has already succeeded should not be restarted.

### Healthchecks do not restart containers

Docker restarts on process exit, not on failed healthchecks. A container that
goes unhealthy while still running stays running indefinitely. Healthchecks here
serve two purposes:

1. **Startup gating** — `depends_on: {condition: service_healthy}` so an
   application does not start before its database is accepting connections.
2. **Visibility** — `docker ps` health status, and `make health`.

If you want a genuinely self-healing stack, that needs a watchdog container
(`autoheal` is the common one) polling health status and restarting. It is not
in this repo today.

Every database and queue container gets a healthcheck:

```yaml
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5
```

Applications get one too where the image ships an HTTP client (`wget --spider`).
Where it does not, omit it rather than shipping a command that fails.

## Secrets

- No secret values in `compose.yaml`.
- Every service that needs configuration has a `.env.example` documenting every
  key.
- `.env` is gitignored and never committed.
- Local-only secrets (`NEXTAUTH_SECRET`, `MEILI_MASTER_KEY`, `AUTH_SECRET`,
  `SECRET_KEY_BASE`, `BEZEL_*`) are generated fresh per device:
  `openssl rand -hex 32`.
- Anything that grants access to a third party (`OPENAI_API_KEY`, R2 keys)
  belongs in `.env` and must be rotated if it was ever committed.

Use `${VAR:?message}` for values a service cannot start without, so a missing
key fails loudly at `docker compose config` time rather than mysteriously later.

```yaml
    environment:
      SECRET: ${SECRET:?set SECRET in .env}
```

## Hostnames and TLS

Every service is reachable at `https://<service>.localhost`, using Caddy's
internal CA. One thing is needed once per device:

```bash
sudo make trust   # install the Caddy root CA
```

`.localhost` subdomains resolve to `127.0.0.1` natively per RFC 6761, so no
`/etc/hosts` entry is required on Linux, macOS or Windows with current Chrome,
Firefox or Edge.

If you need `*.localhost` to work in Safari or an older macOS, add the hostnames
to `/etc/hosts` yourself — there is no target for it here, deliberately. A
generated list would be wrong the moment a service is added or renamed, and the
entry is a one-off for the rare platform that needs it.

Apps that build absolute URLs — OAuth callbacks, CSRF origin checks, DAV
discovery — must be told their real hostname. Look for `*_URL`, `*_ENDPOINT`
and `CSRF_TRUSTED_ORIGINS` in the `.env.example` files.

## Adding a service

1. `mkdir apps/<service>` and write `compose.yaml` following this document.
2. Add `.env.example` if it needs any configuration.
3. Add a route to `infra/caddy/Caddyfile`.
4. `make validate` — both the compose file and the Caddyfile must pass.
5. Commit. Nothing deploys automatically; bring it up with `make up SERVICE=<service>`.