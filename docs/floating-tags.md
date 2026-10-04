# Floating image tags

Every other service pins an exact version. These eight do not, with reasons.

The risk of a floating tag: an unattended restart can pull a breaking change
with no commit to point at. Where a pin is possible, use one — upgrade
deliberately with `make pull` followed by `make up SERVICE=<name>`.

| Service | Tag | Why it floats |
|---|---|---|
| `apps/sure` | `ghcr.io/we-promise/sure:stable` | Upstream ships `stable` as the supported channel and tags releases separately. Pinning has caused upgrade-path friction upstream. |
| `apps/navidrome` | `deluan/navidrome:stable` | Navidrome publishes `stable` as a floating tested channel; version tags are not consistently published to GHCR. |
| `apps/it-tools` | `ghcr.io/corentinth/it-tools:stable` | Static frontend, no persistent state, no migrations. A bad build is cosmetic and self-corrects on the next pull. |
| `apps/tasktrove` | `ghcr.io/dohsimpson/tasktrove:latest` | No release tags published. Has migrations, so check `make logs` after an update. |
| `apps/yamtrack` | `ghcr.io/fuzzygrim/yamtrack:latest` | No release tags published. SQLite-backed; restore from litestream if a build breaks the schema. |
| `apps/tracktor` | `ghcr.io/javedh-dev/tracktor:latest` | No release tags published. Stateless. |
| `apps/jelu` | `wabayang/jelu:latest` | No release tags published. SQLite-backed via `/opt/jelu/db`. |
| `apps/vince` | `ghcr.io/vinceanalytics/vince:latest` | No release tags published. Stateless apart from its data volume. |

## Services with migrations

`tasktrove`, `yamtrack` and `jelu` all persist state and run schema migrations on
start. If one starts failing after an automatic pull, check the logs first and
restore from litestream if the schema moved.

## Pinning one of these

```bash
docker run --rm <image>:latest <entrypoint> version   # or check the release page
```

Then edit the compose file and record the version in a comment, the way
`apps/memos` documents why it cannot be downgraded.