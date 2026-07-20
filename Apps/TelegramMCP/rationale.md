# TelegramMCP — Rationale

## `architectures: [amd64]` only

The upstream image (`ghcr.io/worph/telegram-mcp`) is published as a
single-arch **linux/amd64** image — no `arm64` manifest exists for any
tag (verified with `docker buildx imagetools inspect`; the second
platform reported is the `unknown/unknown` SBOM/provenance attestation,
not a runnable arch). The AppStoreLab copy of this app lists both
`amd64` and `arm64`, but that is inaccurate — an arm64 PCS cannot pull
it. This listing declares only `amd64` so CasaOS hides it on arm
hardware instead of failing at install. To add arm64 support, Worph
needs to publish a multi-arch build (or it must be rebuilt under
`ghcr.io/yundera/`).

## No `beaconify` sidecar

Unlike DocmostMCP (whose upstream image has no discovery support and
therefore needs a `worph/beaconify` proxy), this image ships a built-in
UDP discovery responder (`mcp-announce.cjs`, `DISCOVERY_PORT=9099`).
The main container answers Beacon's discovery broadcast directly, so the
service simply exposes `9099` — same approach as N8NMCP. No sidecar.

## `ALLOWED_PATHS: "mcp,webhook"` on the hash-lock

`nginx-hash-lock` lists ALLOWED_PATHS as the paths that bypass the
login/cookie flow entirely. Two paths must be reachable without it:

- `/mcp` — MCP HTTP clients can't perform the hash-lock session dance; a
  302-to-login would break the transport. The endpoint is gated instead
  by the URL hash documented in `tips.before_install`.
- `/webhook` — Telegram's servers POST update callbacks here with no
  credentials and no way to add the hash, so the path must be open.

The web UI at `/` stays behind both the hash and the `ADMIN` password
(AUTH_MODE `both`), because that is where the bot token is entered.

## `user: $PUID:$PGID`

The container only writes `config.json` under the bind-mounted
`/DATA/AppData/telegrammcp/` (`CONFIG_PATH=/app/data/config.json` is
baked into the image). It touches no user directories and needs no root,
so it runs as the unprivileged PCS user. All data stays under
`/DATA/AppData/telegrammcp/`.
