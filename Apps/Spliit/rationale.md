# Spliit — Rationale

## What deviation / exception is being requested
All three services run as `user: 0:0` (root). The nginx-hash-lock sidecar gates web access with a hash-based authentication layer.

## Why it is necessary
- **spliit**: The Node.js application runs Prisma database migrations on startup, which requires write access to the working directory. Running as non-root causes migration failures.
- **db (PostgreSQL)**: Requires root for database initialization and file ownership in `/var/lib/postgresql/data`. Standard practice for PostgreSQL containers.
- **nginxhashlock**: The nginx-hash-lock sidecar needs root to bind to port 80 and configure nginx.

## Security mitigations in place
- All volumes map exclusively to `/DATA/AppData/$AppID/` — no access to user directories
- No privileged mode on any service
- Memory limits on all services (128M nginx, 512M db, 1G app)
- Web access gated by nginx-hash-lock sidecar (hash-based authentication)
- Database credentials use `$APP_DEFAULT_PASSWORD` (not hardcoded)

## Alternatives considered and rejected
- `user: $PUID:$PGID` — Prisma migrations fail without root; PostgreSQL init requires root for data directory ownership

## Data protection
- PostgreSQL data persists in `/DATA/AppData/$AppID/pgdata/`
- Data survives uninstall/reinstall
