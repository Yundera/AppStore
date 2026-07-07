# Odoo — Rationale

## What deviation / exception is being requested

Both services run as `user: "0:0"` (root):
- `postgres` (postgres:18.3)
- `odoo` (odoo:19.0)

Authentication relies on Odoo's built-in onboarding — the database manager page requires a master password (`$APP_DEFAULT_PASSWORD`) on first access, then users log in with their created admin account.

## Why it is necessary

CasaOS automatically applies `PUID:PGID` (1000:1000) when no `user` field is specified, which differs from standard Docker behavior.

- **PostgreSQL**: The official image expects to run as the `postgres` user (UID 999). CasaOS's automatic UID 1000 prevents PostgreSQL from initializing or accessing its data directory.
- **Odoo**: The official image expects to run as the `odoo` user. UID 1000 conflicts with Odoo's internal user management and access to `/var/lib/odoo`, `/etc/odoo`, and `/mnt/extra-addons`.

## Security mitigations in place

- **Volume isolation**: All volumes map exclusively to `/DATA/AppData/odoo/` — no access to user directories (`/DATA/Documents/`, `/DATA/Media/`, etc.).
- **Network isolation**: PostgreSQL is only reachable on the internal `odoo-internal` network. Only the Odoo web UI (port 80) is exposed via Caddy on the `pcs` network.
- **Official images**: `postgres:18.3` and `odoo:19.0` from Docker Hub, regularly updated and security-audited.
- **Resource limits**: PostgreSQL capped at 512M memory, Odoo at 1G.

## Alternatives considered and rejected

- **Specific UIDs** (e.g. 999 for postgres): Breaks when upstream images change their internal user IDs; less maintainable across updates.
- **Custom entrypoint scripts**: Adds complexity and maintenance burden; deviates from official image best practices.

## Data protection

- All persistent data is under `/DATA/AppData/odoo/` (postgres-data, odoo-data, config, addons).
- No shared volumes with other applications.
- PostgreSQL is not exposed outside the container network.
- `pre-install-cmd` guards config creation with an existence check (`if [ ! -f ... ]`) to preserve user modifications across reinstalls.
