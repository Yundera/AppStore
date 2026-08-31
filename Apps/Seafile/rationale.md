# Seafile App - Security and Architecture Rationale

## Root User Usage

This Seafile deployment uses root containers for several services due to technical requirements:

### Database Service (MariaDB)
- **Reason**: MariaDB requires root privileges for proper initialization and database management
- **Mitigation**: Data is isolated to `/DATA/AppData/seafile/mysql` with no user directory access

### Redis Service
- **Reason**: Redis runs as root for consistency with other services in the stack
- **Mitigation**: Limited to the app-private `seafile-net` network, no external exposure, password-protected (`--requirepass`)

### Seafile Application Services
- **Reason**: Seafile-mc container requires root for internal service management and initialization
- **Mitigation**: No host ports are published — port 80 is only `expose`d, so the sole
  inbound path is the platform Caddy that picks up the `caddy_*` labels; application data
  is confined to `/DATA/AppData/seafile/shared`

### RClone FUSE Mount Service
- **Reason**: FUSE mounting requires root privileges and system capabilities:
  - `privileged: true` for FUSE operations
  - `SYS_ADMIN` capability for mount operations
  - `/dev/fuse` device access
  - `apparmor:unconfined` in `security_opt`, because the default profile blocks the mount
- **Mitigation**: File ownership is properly managed via `--uid $PUID --gid $PGID` flags, ensuring mounted files at `/DATA/Seafile` have correct user permissions

## CPU Share Allocation

The compose sets no hard memory or CPU limits — Seafile's own footprint varies too
much with library size and indexing for a fixed cap to be safe. What it does set is
`cpu_shares`, a relative scheduling weight that decides who wins when the host is
contended:

- **Seafile App** (`seafile`): 80 — user-facing web UI
- **Database** (`db`): 70 — serves the interactive app
- **Seadoc** (`seafile-seadoc`): 70 — interactive document editing
- **Redis** (`redis`): 30 — cache, not on the critical path
- **Notification Server** (`seafile-notification-server`): 30 — lightweight background service
- **RClone** (`rclone`): 30 — background FUSE mount

`cpu_shares` caps nothing; it only orders contention. If a deployment needs a hard
ceiling, add `deploy.resources.limits.memory` per service.

## Network Isolation

Two networks are declared: the app-private `seafile-net` bridge, which every service
joins, and the shared `pcs` network (`${APP_NET:-pcs}`, external), where the platform's
Caddy — shared infrastructure, not part of this app — runs.

**Three** services are attached to `pcs`, not one. Each is there because Caddy has to
reach it by container DNS on that network:

- `seafile` — carries the `caddy_0/1/2` label groups and serves the web UI on port 80.
- `seafile-notification-server` — the label groups proxy `/notification/*` to
  `seafile-notification-server:8083`.
- `seafile-seadoc` — the label groups proxy `/sdoc-server/*` and `/socket.io/*` to
  `seafile-seadoc:80`.

`pcs` is one flat DNS namespace shared with every other app on the box, and Compose
gives each attached service an alias equal to its service name. So all three use
app-prefixed service names and `container_name`s, and `seafile-seadoc` pins a matching
`hostname`; none of them claims a generic alias on the shared network.

`db`, `redis` and `rclone` are on `seafile-net` only — nothing outside this app can
resolve or reach them. No service publishes a host port: every port is `expose`d
rather than mapped, so the only inbound path into the stack is through Caddy.
