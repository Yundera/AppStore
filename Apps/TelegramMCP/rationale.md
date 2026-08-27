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

## `ALLOWED_PATHS: "webhook"` alongside `OAUTH_RESOURCE`

CONTRIBUTING says machine/API clients must be gated with `OAUTH_RESOURCE`, and
that the `ALLOWED_PATHS` pattern must not be copied — an exempted path bypasses
the SSO gate with nothing put in its place, because `AUTH_HASH` is inert under
Maison. `/mcp` follows that rule: AppShield 2.0.9 runs its OAuth 2.1 broker over
`https://telegrammcp-${APP_DOMAIN}/mcp` and every MCP request must carry a
Bearer token. (The earlier listing exempted `/mcp` via `ALLOWED_PATHS` and
claimed a URL-hash mitigation; that hash never existed under Maison, so the
endpoint was reachable anonymously. It is gated now.)

`/webhook` is a deliberate, single-path exception.

**Why it is necessary.** In webhook mode the client is *Telegram itself*.
Telegram's servers POST update callbacks to `${PUBLIC_URL}/webhook` as a plain
HTTP client: no browser session, no redirect following, no token acquisition.
They cannot complete the Authelia OIDC login, and they are not an OAuth client —
there is no way to attach a Bearer token to a Telegram callback. Putting either
gate in front of `/webhook` would return a 302 or a 401 to every update and the
bot would receive nothing, disabling webhook mode entirely.

**The path still requires a credential.** The exemption is from the *platform*
SSO, not from authentication. When the bot switches to webhook mode it generates
a random `secret_token` (`crypto.randomUUID()`) per registration and passes it to
`setWebhook`; Telegram then sends it back on every callback in the
`X-Telegram-Bot-Api-Secret-Token` header, and grammY's `webhookCallback` rejects
any request whose header does not match. The token is regenerated on each
restart and is never published. In polling mode no webhook is registered at all
and `/webhook` answers `404 Webhook not active`.

**Ordering is safe.** AppShield renders the OAuth resource as `location ^~ /mcp`,
an nginx prefix match that suppresses regex evaluation, so it outranks the
`location ~ ^/(webhook)(/|$)` bypass. Listing `webhook` cannot widen the
exemption to `/mcp`.

**Alternatives rejected.**
- *Removing `ALLOWED_PATHS` entirely* — webhook mode stops working; every update
  gets the SSO redirect instead of reaching the bot.
- *`OAUTH_RESOURCE` on `/webhook`* — Telegram cannot obtain or send a Bearer
  token; the endpoint would 401 on every callback.
- *Dropping webhook mode and shipping polling-only* — polling is the default and
  needs no inbound path, but webhook mode is the low-latency option for users on
  a publicly reachable PCS, and it is upstream functionality this listing has no
  reason to remove when the callback already authenticates itself.

The Web UI at `/`, where the bot token is entered, and every `/api` route stay
fully behind the AppShield OIDC gate.

## `user: $PUID:$PGID`

The container only writes `config.json` under the bind-mounted
`/DATA/AppData/telegrammcp/` (`CONFIG_PATH=/app/data/config.json` is
baked into the image). It touches no user directories and needs no root,
so it runs as the unprivileged PCS user. All data stays under
`/DATA/AppData/telegrammcp/`.
