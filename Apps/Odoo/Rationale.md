# Odoo — Rationale

## What deviation / exception is being requested

Both services run as `user: "0:0"` (root):
- `postgres` (postgres:18.3)
- `odoo` (odoo:19.0)

Authentication relies on Odoo's built-in onboarding — the database manager page requires a master password on first access, then users log in with their created admin account. That master password is **not** left on Odoo's upstream default (the literal `admin`): `seed/config/odoo.conf.tmpl` writes `admin_passwd = ${ODOO_MASTER_PASSWORD}` (a per-app secret, shown with `x-compose-app.credentials`) into `/etc/odoo/odoo.conf`, which is the only config the container reads because the `config/` bind mount masks the image's own `/etc/odoo`.

## Why it is necessary

CasaOS automatically applies `PUID:PGID` (1000:1000) when no `user` field is specified, which differs from standard Docker behavior.

- **PostgreSQL**: The official image expects to run as the `postgres` user (UID 999). CasaOS's automatic UID 1000 prevents PostgreSQL from initializing or accessing its data directory.
- **Odoo**: The official image expects to run as the `odoo` user. UID 1000 conflicts with Odoo's internal user management and access to `/var/lib/odoo`, `/etc/odoo`, and `/mnt/extra-addons`.

## Security mitigations in place

- **Volume isolation**: All volumes map exclusively to `/DATA/AppData/odoo/` — no access to user directories (`/DATA/Documents/`, `/DATA/Media/`, etc.).
- **Network isolation**: PostgreSQL is only reachable on the internal `odoo-internal` network. Only the Odoo web UI (port 80) is exposed via Caddy on the `pcs` network.
- **Official images**: `postgres:18.3` and `odoo:19.0` from Docker Hub, regularly updated and security-audited.
- **Resource limits**: PostgreSQL capped at 512M memory, Odoo at 1G.
- **Master password set from a generated secret**: `/web/database/manager` (backup, duplicate, restore, drop) needs no session, so it is gated on `admin_passwd`, which is set to the per-app secret `ODOO_MASTER_PASSWORD` (seeded from the old box-wide password on installs that already had it, generated otherwise) rather than left on the upstream default.

## Alternatives considered and rejected

- **Specific UIDs** (e.g. 999 for postgres): Breaks when upstream images change their internal user IDs; less maintainable across updates.
- **Custom entrypoint scripts**: Adds complexity and maintenance burden; deviates from official image best practices.

## Data protection

- All persistent data is under `/DATA/AppData/odoo/` (postgres-data, odoo-data, config, addons).
- No shared volumes with other applications.
- PostgreSQL is not exposed outside the container network.
- `seed/config/odoo.conf.tmpl` is create-if-absent, so a reinstall never overwrites a config the user has edited. The `repair-admin-passwd` step only repairs installs made before `admin_passwd` was set: it appends the key (from `ODOO_MASTER_PASSWORD`) to an odoo.conf that already exists and never creates one.

## Data migrations (`data_version: 3`)

Until 2026-03-28 the store shipped `odoo:18.0` on `postgres:15.15`; it now ships `odoo:19.0` on `postgres:18.3`. Neither conversion happens by itself: PostgreSQL 18 refuses to start on a 15 cluster, and Odoo 19 started on an Odoo 18 database answers 500 on every page while its container reports healthy. Every install predates `.data-version`, so an old one and a current one both arrive at data version 1 and each step reads the data rather than trusting the counter.

- **2 `require-odoo-19-database`** (script, read-only): starts a throwaway PostgreSQL of the cluster's own major, with no network, and reads each database's `base` module version. Any database below 19 fails the update, so Maison restores the pre-update backup and Odoo 18 keeps running. Odoo 18 → 19 needs OpenUpgrade, which depends on the modules installed and is not safe to run unattended. It is a script and not a `blocked` step because `blocked` cannot look at the data: it would also refuse every install that is already on 19.
- **3 `postgres-15-to-18`** (container): `pgautoupgrade` runs `pg_upgrade` once and exits; on a cluster already at 18 it changes nothing. In practice it only runs for a 15 cluster whose databases are already on Odoo 19, for example one upgraded by hand with OpenUpgrade, since step 2 stops every other 15 install first.
