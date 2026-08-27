# Ntfy — Rationale

## Unauthenticated MCP endpoint on the shared `pcs` network

### What deviation is being requested

The bundled MCP sidecar listens on `:9099` (`/mcp`) with **no authentication**, and
`tips.before_install` advertises `http://ntfy:9099/mcp` as the intended "no auth
required" integration path for AI assistants running on the same PCS. Any other
container attached to the shared `pcs` network can therefore reach it and, through
it, publish notifications and read cached messages from any topic — using the
admin-scoped token the entrypoint mints on first boot (`ntfy token add admin`).

### Why it is necessary

MCP clients on the same host (Beacon, Claude Code, n8n) speak plain HTTP with no
browser session and no way to complete an interactive login. The in-cluster port is
what makes the zero-configuration local integration work, and it is the same pattern
every other MCP app in this store ships (`Apps/Beacon`, `Apps/BrowserMCP`,
`Apps/N8NMCP`, `Apps/NextcloudMCP` all leave the backend MCP port reachable on `pcs`).

Fronting ntfy itself with the AppShield sidecar is not an option here: AppShield
reserves `/login`, and ntfy's bundled nginx serves its **own** `/login` page for the
web UI — the two collide. The web UI is instead gated by ntfy's native auth
(`auth-default-access: deny-all`, seeded `admin` user), which is what satisfies the
store's `auth-default` requirement.

### Security mitigations in place

- `9099` is `expose:`d only. It is never published to the host, carries **no** Caddy
  label, and is not part of any public vhost — there is no public `/mcp` route.
- Reaching it requires already having a container on the `pcs` network, i.e. an app
  the PCS owner installed themselves.
- The blast radius is ntfy's own data: sending notifications and reading cached
  messages. The sidecar exposes no filesystem, shell or config tooling.
- The Beacon announce payload carries no credentials — it is `name`, `port`, `path`,
  `version`, `type` only; the admin token is never broadcast.
- The public surface (`:80`) keeps ntfy's own auth: `auth-default-access: deny-all`
  means anonymous publish/subscribe is refused there.

### Alternatives considered and rejected

- **AppShield in front of the whole app** — collides with ntfy's own `/login` route
  and would break the ntfy mobile/desktop apps, which authenticate with an
  `Authorization` header against `/v1/*` and cannot perform the OIDC redirect dance.
- **Dropping `9099` from `expose:`** — removes the local MCP integration, which is the
  reason this listing exists.
- **A shared secret on the sidecar** — the sidecar image has no token option today;
  adding one is an upstream change in `ghcr.io/worph/ntfy`, tracked there.

### Data protection

All state lives in `/DATA/AppData/ntfy/cache/` (`user.db`, `cache.db`, the sidecar
token), so it survives uninstall/reinstall. The token file is written inside that
directory and is never surfaced over the network.

## `user: "0:0"`

The image's entrypoint writes `/etc/ntfy/server.yml` at start-up, seeds the admin
user and sidecar token into the bind-mounted `/var/cache/ntfy`, and then starts an
nginx master that binds `:80` and drops its workers to the `nginx` user. None of that
works as an unprivileged uid, and running as root also removes the need for the user
to pre-fix ownership of `/DATA/AppData/ntfy/cache/` before first launch. The only
host path the container can see is `/DATA/AppData/ntfy/cache/`.
