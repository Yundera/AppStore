# UptimeKumaMCP — Rationale

## Stock third-party image, `architectures: [amd64]` only

`davidfuchs/mcp-uptime-kuma` (MIT, <https://github.com/DavidFuchs/mcp-uptime-kuma>) runs
unmodified. Tags 0.11.4 to 0.13.0 were published for **linux/amd64** only; from 0.14.0
on the image is also published for linux/arm64 (Docker Hub tag listing, checked
2026-11-14). The listing still declares amd64 alone, the platform it has been tested
on; widening `architectures` to arm64 is a separate change once it has been installed
on an arm64 box. It's pinned to an exact
version: the project is pre-1.0 and tool names may still change between releases.

## The Uptime Kuma login is a Maison `input`, not a generated secret

Uptime Kuma 2 has no API key the MCP server can use: it logs in over Socket.IO with
a username and password. That account is created by the user in Uptime Kuma's own
first-run screen, so Maison cannot generate it. It is declared under `inputs`
(`UPTIME_KUMA_USERNAME`, `UPTIME_KUMA_PASSWORD` as `secret: true`), which asks for it
at install, shows **Setup needed** while it's empty, and recreates the app when it's
changed from **Set up…**. It isn't an `accounts` entry, because the account belongs to
another app on the same box, not to a third party.

`UPTIME_KUMA_URL` is an optional input. The compose reads it as
`${UPTIME_KUMA_URL:-http://uptimekuma:80}`, so the empty line Maison writes falls back
to the store's Uptime Kuma app on the `pcs` network.

A wrong or not-yet-valid login does not wedge the server: every tool call retries the
login (verified 2026-11-04 by bringing Uptime Kuma up after the MCP server and by
restarting it underneath a logged-in session).

`UPTIME_KUMA_2FA_TOKEN` is not offered: it takes a TOTP code, which is stale by the next
restart.

## A service with a route: `webui: false`, and `view: service` declared

The app has no web UI. The upstream serves only `POST /mcp` and `GET /health`, and `/`
is a 404. It still needs a route, for the public OAuth `/mcp` endpoint. The route is
marked `webui: false`: Maison routes it like any other but never makes it the tile's
click URL, so the app lands in **Services** and a click opens its settings and tips, as
Samba's does. Without it the tile opened the route's `/`, which is a 404.

`view: service` is still declared, for Maison builds that predate `webui`: they ignore
the key, count the route as a web UI and would sort the tile into the app grid. On those
builds the click still opens the 404; only the grid is right.

AppShield's backend is `uptimekumamcp-beacon:9099` rather than the MCP server. Beaconify
proxies `/mcp` to the backend unchanged, and its `/api/status` (tool count, last refresh,
last error) is linked from the tips as the way to check the app is answering. AppShield
gates that page with SSO and `/mcp` with its OAuth 2.1 broker.

## beaconify 1.0.3, not the 1.0.2 the other MCP apps use

Beacon's discovery manifest travels in one UDP datagram, which holds at most 65,507 bytes.
This server's 35 tools with full input and output schemas came to about 74 KB (36 tools,
about 77 KB, on 0.15.0). beaconify
1.0.2 sends that whole, the send fails, and Beacon logs `No manifest … after 3 attempts`
every sweep (seen on holyhorse 2026-11-04). 1.0.3 falls back to `{name, description}`
when the manifest is too big, and Beacon (≥ 1.0.20) then fetches the full tool
definitions over HTTP. Verified on holyhorse with a local build: Beacon 1.0.21
registered `uptime-kuma-mcp` with 35 tools, and `call` reached Uptime Kuma.

## `TRUST_PROXY: "true"` on the backend

The upstream rate-limits each client IP: 100 requests per 15 minutes in 0.12.1, and
`RATE_LIMIT_MAX` (default 1000) in 0.15.0. Every
caller arrives from beaconify's address, so without trusting `X-Forwarded-For`, Beacon
and every public OAuth client would share one bucket. AppShield sets the header and
beaconify forwards it, so each public client gets its own bucket (verified on 0.12.1:
two different forwarded addresses each started at 99 remaining; on 0.15.0 a public
OAuth client had its own bucket of 1000). A client can spoof the
header to move to another bucket, but that only gets around a throttle: access is
decided by AppShield before the request ever reaches the backend.

## Unauthenticated in-network endpoint

`MCP_AUTH_TOKEN` is left unset, so `http://uptimekumamcp-backend:3000/mcp` answers
anyone on the `pcs` network. That is the same trust model as Beacon and every other MCP
app in this store (their "Option 2"), and it is what lets Beacon and beaconify call
the backend without a credential. Nothing publishes the port. The upstream logs a
warning about this at startup, which is expected.

## Backend runs as `$PUID:$PGID` with no volume

The server keeps all state in memory: its Socket.IO session and a monitor cache. It
writes nothing to disk. The only persistent data is AppShield's OAuth store in
`/DATA/AppData/uptimekumamcp/oauth/`.
