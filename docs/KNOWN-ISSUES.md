# Known issues

Services imported from the old directories that will not work as-is, or that
need a decision before they can run. Everything here is a **configuration**
problem — every compose file passes `make validate`. Passing validation means
the YAML is well-formed, not that the service will start.

Nothing in this list has been started yet, so there is no data at risk. The
only services with real data are `memos` and `kaneo`, and both are verified
working.

## Blockers — will not start correctly

### `padloc` — builds from a git URL
Both services use `build:` with `context: github.com/padloc/padloc.git#main`
instead of a published image. That requires network access to clone and build on
every fresh machine, and pins nothing. Published images exist at
`padloc/server` and `padloc/pwa`; switch to those and drop the `build:` blocks.

### `sonarr` — mounts media directories that do not exist
```
/home/abdulkareem/media/TVShows/:/sonarr/data/TVShows/
/home/abdulkareem/media/Movies/:/sonarr/data/Movies
```
There is no `/home/abdulkareem/media` on this machine. Docker will create the
directories empty, so Sonarr starts but has nothing to index. Point these at
real media or remove them.

### `navidrome` — no music library
The library mount was removed because `/mnt/volume_sgp1_01/music` was a VPS-era
path. Navidrome will start with an empty library. See the note in its compose
file.

### `vince` — placeholder domain
`VINCE_DOMAINS=CHANGE-ME` in `apps/vince/.env`. Vince refuses to track anything
until this names a real site, and the site needs a DNS or Caddy entry plus the
tracking snippet.

### `actual` — authentication is misconfigured
`ACTUAL_LOGIN_METHOD: openid` with `ACTUAL_ALLOWED_LOGIN_METHODS: openid`. That
assumes an authenticating proxy sits in front of it, which the local Caddy does
not do. Actual will present an OpenID login that cannot complete. Switch both
values to `password`.

## Needs credentials you have to supply

These have a valid `.env` skeleton but cannot work until filled in with real
third-party values:

| Service | Missing |
|---|---|
| `beszel` | `BEZEL_TOKEN`, `BEZEL_KEY` — created in the hub UI, copied into `infra/beszel/.env` |
| `litestream` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `LITESTREAM_BUCKET`, `LITESTREAM_ENDPOINT` — Cloudflare R2 |
| `linkding` | `LD_SUPERUSER_NAME` / `LD_SUPERUSER_PASSWORD`, or accept no auth |
| `opengist` | working `OPENGIST_ADMIN_PASSWORD` (currently generated) |
| `booklogr` | `BL_GOOGLE_ID` if Google login is wanted |

## Architectural exceptions to the conventions

### `HomeAssistant` — host networking and privileged
Runs `privileged: true` with `network_mode: host`, so it cannot join the proxy
network. Caddy reaches it through `host.docker.internal:8123`, which is why
`infra/caddy/compose.yaml` carries an `extra_hosts` entry for the bridge
gateway. This is the only service in the repo that binds a port on the host
without a `ports:` entry, and the only `privileged` container.

Host networking is kept deliberately: Home Assistant discovery protocols
(mDNS/SSDP) do not work through a bridge. If you do not need local device
discovery, switching it to bridge networking would let it join `proxy` normally.

### `dockpeek`, `portracker` — raw TCP socket proxies
Both run a Docker socket proxy on 2375. That is TCP, not HTTP, so Caddy cannot
front it and the app talks to it over `proxy` by container name instead. No
host port needed.

### `opengist` — git over SSH
HTTP is proxied. Git-over-SSH on 2222 is not, so it needs a real published port
if you push over SSH. The `ports:` block is present but commented out.

## Floating image tags

39 of 78 image references across the repo use `:latest`, `:stable` or `:main`.
See [floating-tags.md](floating-tags.md) for the full list and which services
run schema migrations (those matter most).

Pinning all of them means checking each upstream's published release tags. That
is mechanical but has to be done per image, and a wrong pin is worse than a
floating tag — see the `memos` entry in that document for what a bad pin costs.

## Never verified

Every service except `memos` and `kaneo` was imported from files that had never
been started on this machine. Expect to hit runtime issues that config
validation cannot catch: migrations against a stale schema, applications that
need a URL they were never told, images whose current release dropped support
for a setting still in the compose file.

Bring them up one at a time and read the logs:

```bash
make up SERVICE=<name>
make logs SERVICE=<name>
```