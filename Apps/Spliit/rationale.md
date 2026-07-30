# Spliit — Rationale

## What deviation / exception is being requested
1. Both services run as `user: 0:0` (root).
2. Authentication is disabled — the app is publicly accessible without login.

## Why it is necessary
- **spliit**: The Node.js application runs Prisma database migrations on startup, which requires write access to the working directory. Running as non-root causes migration failures.
- **db (PostgreSQL)**: Requires root for database initialization and file ownership in `/var/lib/postgresql/data`. Standard practice for PostgreSQL containers.
- **No authentication**: Spliit is a collaborative expense-sharing app. Users create groups and share links with friends/family who need direct access without any account. Adding an authentication gate would break the core functionality — external participants would be unable to view or add expenses.

## Security mitigations in place
- All volumes map exclusively to `/DATA/AppData/$AppID/` — no access to user directories
- No privileged mode on any service
- Memory limits on all services (512M db, 1G app)
- Database credentials use `$APP_DEFAULT_PASSWORD` (not hardcoded)
- No sensitive data exposed — the app only handles expense group data
- Each group has a unique random URL that acts as a capability-based access control

## Alternatives considered and rejected
- `user: $PUID:$PGID` — Prisma migrations fail without root; PostgreSQL init requires root for data directory ownership
- AppShield / nginx-hash-lock authentication — blocks external participants from accessing shared expense groups, breaking the app's core use case

## Data protection
- PostgreSQL data persists in `/DATA/AppData/$AppID/pgdata/`
- Data survives uninstall/reinstall
