# Claude Code — Rationale

## What deviation / exception is being requested

Two things are recorded here:

1. **`MCP_ENABLED=false`** — the app ships with the image's MCP endpoint turned
   off, even though this is the sandboxed variant and `ClaudeCodeRoot`'s own
   rationale describes this app as the one that carries MCP.
2. **`user: 0:0`** — the container's supervisor starts ttyd and the auth/MCP
   process and must be root to do so; it is the image's only supported mode.

No exception is requested on authentication: it is on by default (see below).

## Why it is necessary

**MCP off.** In `ghcr.io/worph/claude-code-container` (every tag through
`1.0.28`), `MCP_ENABLED=true` does two things, not one. It serves `/mcp` on port
9090 behind a Bearer check, **and** it starts a Beacon discovery responder —
`mcp-announce.js`, bound to `0.0.0.0:9099` with membership of multicast
`239.255.99.1`. That responder replies to any datagram whose body is
`{"type":"discovery"}`, from any sender, with no authentication of any kind, and
when `AUTH_PASSWORD` is set the manifest it returns includes
`auth: {type: "bearer", token: "<AUTH_PASSWORD>"}`.

`AUTH_PASSWORD` here is `$APP_DEFAULT_PASSWORD`. It is simultaneously:

- the `/mcp` Bearer token, and `/mcp` exposes `query_claude`, i.e. arbitrary
  command execution inside this container;
- the web-terminal login password; and
- the PCS-wide generated default that other store apps use for their own admin
  and database credentials.

The service sits on the shared `${APP_NET:-pcs}` network, and Docker network
peers can reach any container port regardless of what `expose:` lists. So with
MCP on, any co-tenant container — including a third-party app the user installs
later — could obtain that password with a single unauthenticated UDP packet.
The image exposes no switch that keeps `/mcp` while suppressing the
announcement, and no `AUTH_PASSWORD` value is safe to publish when the token is
what grants code execution. Disabling MCP is the only setting that removes the
channel.

**`user: 0:0`.** The image's s6 supervisor spawns ttyd and the Node auth process
and drops privileges itself; a non-root UID cannot start it. Nothing outside the
container is mounted, so root here is root of an empty sandbox.

## Security mitigations in place

- **Authentication is on by default and never hardcoded.** Every route is behind
  the auth layer on port 9090, which keeps running with MCP disabled: `/login`
  and `/logout` are served by it directly, everything else goes through Caddy
  `forward_auth` to `/auth` and is redirected to `/login` on 401. The password
  is `$APP_DEFAULT_PASSWORD`, generated per server at install time.
- **No credential is broadcast.** With `MCP_ENABLED=false` the discovery
  responder is never created (`server.js` returns before constructing it), so
  nothing announces the app or its token on the shared network. Verified against
  the image source; the same setting is what `ClaudeCodeRoot` ships.
- **`/mcp` is dead.** The 9090 server answers the path with a JSON-RPC
  `METHOD_NOT_FOUND`, so the remote-drive surface does not exist even for a peer
  that reaches port 9090 directly.
- **Fully sandboxed.** No `/var/run/docker.sock`, no host SSH mount, no `/DATA`
  mount, no `privileged: true`, no `cap_add`. The only bind mounts are this
  app's own `workspace/` and `config/` under `/DATA/AppData/claude/`.
- **No published host ports.** `expose:` only, on the `pcs` network, so 8080 and
  9090 are reachable from outside solely through the gateway-terminated Caddy
  routes.
- **Pinned image** `ghcr.io/worph/claude-code-container:1.0.26`; resource limits
  `cpu_shares: 70`, `memory: 2048M`.
- **Disclosed before install.** `x-casaos.description` and
  `tips.before_install` state that this is the sandboxed variant, name
  `ClaudeCodeRoot` as the privileged alternative, and say that MCP is off and
  why.

## Alternatives considered and rejected

- **Keep `MCP_ENABLED=true` and document the disclosure.** Rejected: a note in
  `tips.before_install` does not stop a co-tenant container reading the
  password, and the store requires authentication that actually holds.
- **Give the app its own generated secret instead of `$APP_DEFAULT_PASSWORD`.**
  Rejected: it narrows the blast radius to this container but the announced
  token still grants `query_claude`, i.e. code execution. The disclosure channel
  is unchanged.
- **Unset `AUTH_PASSWORD` so the manifest carries no `auth` block.** Rejected:
  with an empty password the image treats every request as authorised
  (`isAuthorized()` returns true, `/auth` returns 200) — that removes the
  disclosure by removing the authentication.
- **Front the app with the AppShield OIDC sidecar and let it hold the
  perimeter.** Rejected as currently unbuildable: AppShield proxies a single
  `BACKEND_HOST:BACKEND_PORT`, and this app needs two — ttyd on 8080 for the UI
  and the MCP/auth server on 9090 for `/mcp`. One sidecar cannot serve both, and
  a second sidecar would need its own `container_name`/`hostname`, which is what
  `auth-registrar` attests the OIDC client identity against. It also would not
  address the leak, which is a UDP responder on the shared network that no HTTP
  proxy sits in front of.
- **Move the container off the `pcs` network so the responder has no audience.**
  Rejected: Caddy resolves upstreams on `pcs`, so leaving it makes the app
  unreachable.

## Data protection

The app's own state lives under `/DATA/AppData/claude/` — `workspace/` and
`config/`, both declared in `x-compose-app.folders` and owned by `$PUID:$PGID` —
and survives uninstall/reinstall. Nothing outside that directory is mounted, so
the container cannot read another app's data or the host filesystem.

## Restoring MCP

The feature is worth having back; the fix belongs in the image, not the listing.
`mcp-server/server.js` should either stop attaching `discoverOpts.auth`, or gate
the announcement behind an explicit opt-in (e.g. `DISCOVERY_ANNOUNCE_AUTH`)
defaulting to off. Once a tag ships with that, this app can set
`MCP_ENABLED=true` again. Source:
<https://github.com/yundera/claude-code-container>.
