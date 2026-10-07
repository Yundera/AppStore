# DiscordMCP — Rationale

## `architectures: [amd64]` only

The upstream image (`ghcr.io/bookjjun-ij/discordmcp:1.0.0`) is published as a
single-arch **linux/amd64** image — the only other manifest entry is the
`unknown/unknown` attestation (verified with `docker manifest inspect`). The
AppStoreLab copy of this app lists both `amd64` and `arm64`, but an arm64 PCS
cannot pull it. This listing declares only `amd64` so it is hidden on arm
hardware instead of failing at install. Adding arm64 needs a multi-arch build
upstream (or a rebuild under `ghcr.io/yundera/`).

## No `beaconify` sidecar

The image ships a built-in UDP discovery responder (`mcp-announce.cjs`,
`DISCOVERY_PORT=9099`), so the backend answers Beacon's discovery broadcast
directly and simply exposes `9099` — same approach as TelegramMCP and N8NMCP.

## `user: $PUID:$PGID`

The container only writes `config.json` under the bind-mounted
`/DATA/AppData/discordmcp/` (`CONFIG_PATH=/app/data/config.json` is baked into
the image). It touches no user directories and needs no root, so it runs as the
unprivileged PCS user. All data stays under `/DATA/AppData/discordmcp/`.

## AppShield runs as `0:0`

Same as every AppShield-fronted app: the scratch image has no passwd entry, and
its OAuth data dir (`/data/oauth`) is declared under `x-compose-app.folders` and
chowned to `$PUID:$PGID` by Maison.
