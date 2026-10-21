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
- **Mitigation**: No host ports are published — port 80 is only `expose`d, and the web
  traffic reaches it through the app's own router (`seafile-router`, below); application
  data is confined to `/DATA/AppData/seafile/shared`

No service in this stack is privileged, and none of them mounts a host path outside
`/DATA/AppData/seafile`. The FUSE mount that used to publish the libraries at
`/DATA/Seafile` — the one thing here that needed `privileged`, `SYS_ADMIN` and
`/dev/fuse` — is now the separate **Seafile Virtual Folder** app (`Apps/SeafileDrive`),
so those privileges are granted only on a machine whose owner asked for that folder.

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
- **Router** (`seafile-router`): 50 — every web request passes through it, but it only proxies

`cpu_shares` caps nothing; it only orders contention. If a deployment needs a hard
ceiling, add `deploy.resources.limits.memory` per service.

## Routing: the app's own router

Seafile is one web address served by three programs: seahub (and its file server) in
`seafile`, the notification server, and SeaDoc. Which one answers depends on the path:

| Path | Goes to |
|---|---|
| `/notification/…` | `seafile-notification-server:8083`, prefix stripped |
| `/socket.io/…` | `seafile-seadoc:80`, path kept |
| `/sdoc-server/…` | `seafile-seadoc:80`, prefix stripped |
| everything else | `seafile:80` |

That dispatch is the app's business, so it lives in the app: `seafile-router`, an nginx
service whose config ships inline in this listing (`configs: seafile-router`). The
platform only routes `seafile-<domain>` to the router's port 80 — the plain three-label
shape every other app uses — and knows nothing of the paths behind it. (It used to be a
Caddy `handle_path` tree in the labels, which tied the listing to Caddy.)

The router is configured for what Seafile needs and nginx does not do by default: no
request-body cap and no buffering (whole files are uploaded and downloaded through it),
hour-long timeouts, websocket upgrade for the notification server and SeaDoc, and
`X-Forwarded-Proto` passed through from the TLS-terminating proxy in front. Its upstreams
are resolved through Docker's DNS at request time, so it starts before the other
services exist and follows them when they are recreated.

Checked on a test PCS on 2026-10-21 against the previous, label-routed listing, on all
three published hosts: login and API token, a 64 MiB upload and download through
`/seafhttp` with matching checksums, WebDAV, the notification websocket, SeaDoc's
socket.io (polling and websocket) and `/sdoc-server/` — identical results.

## Network Isolation

Two networks are declared: the app-private `seafile-net` bridge, which every service
joins, and the shared `pcs` network (`${APP_NET:-pcs}`, external), where the platform's
Caddy — shared infrastructure, not part of this app — runs.

**Two** services are attached to `pcs`:

- `seafile-router` — carries the `caddy_0/1/2` label groups; Caddy reaches it on port 80.
- `seafile` — because the **Seafile Virtual Folder** app (`Apps/SeafileDrive`), a separate
  compose project, reaches its WebDAV server at `http://seafile:8080/seafdav` over `pcs`.

`pcs` is one flat DNS namespace shared with every other app on the box, and Compose
gives each attached service an alias equal to its service name. So both use
app-prefixed service names and `container_name`s; neither claims a generic alias on the
shared network.

`seafile-notification-server`, `seafile-seadoc`, `db` and `redis` are on `seafile-net`
only — nothing outside this app can resolve or reach them; the router reaches the first
two there. No service publishes a host port: every port is `expose`d rather than mapped,
so the only inbound web path into the stack is Caddy → `seafile-router`.
