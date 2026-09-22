# Plausible — Rationale

## What deviation / exception is being requested
All three services run as `user: "0:0"` (root). Authentication uses Plausible's built-in registration system (invite-only by default; first user becomes admin).

## Why it is necessary
- **Plausible**: The official Community Edition image runs its Elixir/Phoenix application as root. It generates cryptographic secrets on first boot (`SECRET_KEY_BASE`, `TOTP_VAULT_KEY`) and writes them to `/secrets`. The entrypoint runs database migrations (`db createdb`, `db migrate`) that require write access to internal directories.
- **PostgreSQL**: Requires root for database initialization and file ownership in `/var/lib/postgresql/data`. Standard practice for PostgreSQL containers.
- **ClickHouse**: Requires root for data directory initialization and log management. The official alpine image expects root to set up `/var/lib/clickhouse` and `/var/log/clickhouse-server`.

## Security mitigations in place
- All volumes map exclusively to `/DATA/AppData/$AppID/` — no access to user directories
- No privileged mode, no elevated capabilities
- Memory limits on all services (512M PostgreSQL, 1G ClickHouse, 1G Plausible)
- Databases isolated on internal `plausible-network` — not exposed on `pcs`
- Database healthchecks prevent race conditions (`depends_on: condition: service_healthy`)
- Database credentials use `$APP_DEFAULT_PASSWORD` (no hardcoded secrets)
- Registration set to `invite_only` by default
- CPU shares configured on all services

## Alternatives considered and rejected
- `user: $PUID:$PGID` — Plausible's entrypoint and Elixir runtime expect root; ClickHouse requires root for data directory ownership; PostgreSQL init requires root

## Data protection
- PostgreSQL data persists in `/DATA/AppData/$AppID/db/`
- ClickHouse data persists in `/DATA/AppData/$AppID/event-data/`
- Cryptographic secrets persist in `/DATA/AppData/$AppID/secrets/`
- All data survives uninstall/reinstall
