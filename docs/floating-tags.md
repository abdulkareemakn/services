# Floating image tags

38 of 78 image references in this repo float (`:latest`, `:stable` or
`:main`). They are listed here so the risk is explicit rather than accidental.

## Why it matters

An unattended restart can pull a breaking change with no commit to point at.
`apps/memos` is the worked example: it was pinned to `0.25.2` while its
database had been created by `0.30.0`. Memos migrations only run forward, so the
older binary refused to start with `no such table: migration_history` and
treated a populated database as empty. Wrong pins are worse than no pin.

## Services that migrate a database on start

These are the ones where a floating tag can do real damage. If one starts
failing after an automatic pull, read the logs and restore from litestream
before retrying.

| Service | Tag | Store |
|---|---|---|
| `apps/memos` | pinned `0.30.0` | sqlite at `/opt/memos/app` |
| `apps/vikunja` | `vikunja/vikunja:latest` | sqlite at `/opt/vikunja/db` |
| `apps/linkwarden` | `ghcr.io/linkwarden/linkwarden:latest` | postgres + meilisearch |
| `apps/blinko` | `blinkospace/blinko:latest` | postgres |
| `apps/planka` | postgres + app, both floating | postgres at `/opt/planka/db` |
| `apps/glasskeep` | `nikunjsingh/glass-keep:latest` | sqlite at `/opt/glasskeep/app` |
| `apps/jelu` | `wabayang/jelu:latest` | sqlite at `/opt/jelu/db` |
| `apps/yamtrack` | `ghcr.io/fuzzygrim/yamtrack:latest` | sqlite at `/opt/yamtrack/db`, replicated by litestream |
| `apps/tasktrove` | `ghcr.io/dohsimpson/tasktrove:latest` | `/opt/tasktrove/app` |

## Pinned but intentionally floating

| Service | Tag | Reason |
|---|---|---|
| `apps/sure` | `ghcr.io/we-promise/sure:stable` | upstream ships `stable` as the supported channel |
| `apps/navidrome` | `deluan/navidrome:stable` | upstream's tested channel; version tags not reliably on GHCR |
| `apps/it-tools` | `ghcr.io/corentinth/it-tools:stable` | static frontend, no state, no migrations |
| `apps/HomeAssistant` | `ghcr.io/home-assistant/home-assistant:stable` | HA publishes `stable` deliberately; minor versions are the support unit |

## Stateless — low risk

`arcane`, `bytestash`, `budgetzen`, `dockpeek`, `dumbbudget`, `dumbpad`,
`expenseowl`, `flatnotes`, `freshrss`, `hammond`, `many-notes`, `MediaManager`,
`MediaTracker`, `movary`, `openwebui`, `picsur`, `portainer`, `portracker`,
`silverbullet`, `slash`, `slink`, `sonarr`, `termix`, `timetracker`,
`tracktor`, `vince`, `wallos`.

These hold no database and no durable state, so a bad pull costs a restart.

## Pinning one

Find the current version rather than guessing:

```bash
docker run --rm <image>:latest <entrypoint> version
# or check the upstream releases page
```

Then edit the compose file and **record why in a comment**, the way
`apps/memos` does. A future reader needs to know the pin is load-bearing.

Do not pin `postgres`, `redis` or `caddy` to `latest` — those are already
pinned, and an unpinned database image can silently change major version under
an existing data directory.