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
- **Mitigation**: All services are contained within the seafile-net network with controlled exposure

### RClone FUSE Mount Service
- **Reason**: FUSE mounting requires root privileges and system capabilities:
  - `privileged: true` for FUSE operations
  - `SYS_ADMIN` capability for mount operations
  - `/dev/fuse` device access
- **Mitigation**: File ownership is properly managed via `--uid $PUID --gid $PGID` flags, ensuring mounted files at `/DATA/Seafile` have correct user permissions

## CPU Share Allocation

The compose sets no hard memory or CPU limits — Seafile's own footprint varies too
much with library size and indexing for a fixed cap to be safe. What it does set is
`cpu_shares`, a relative scheduling weight that decides who wins when the host is
contended:

- **Seafile App** (`seafile`): 80 — user-facing web UI
- **Database** (`db`): 70 — serves the interactive app
- **Seadoc** (`seadoc`): 70 — interactive document editing
- **Redis** (`redis`): 30 — cache, not on the critical path
- **Notification Server** (`notification-server`): 30 — lightweight background service
- **RClone** (`rclone`): 30 — background FUSE mount

`cpu_shares` caps nothing; it only orders contention. If a deployment needs a hard
ceiling, add `deploy.resources.limits.memory` per service.

## Network Isolation

All services communicate through the app-private `seafile-net` bridge network. Only the `seafile` service is additionally attached to the shared `pcs` network, where Caddy — shared platform infrastructure, not part of this app — picks up its `caddy_*` labels and publishes the web UI. The database, Redis, Seadoc, the notification server and RClone are unreachable from outside the app.
