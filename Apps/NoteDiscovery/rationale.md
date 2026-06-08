# NoteDiscovery — Rationale

## What deviation / exception is being requested
Runs as `user: 0:0` (root).

## Why it is necessary
The NoteDiscovery container image requires root to bind to port 80 and manage file permissions in `/app/data`. The application writes markdown note files and search indexes that need consistent ownership.

## Security mitigations in place
- All volumes map exclusively to `/DATA/AppData/$AppID/` — no access to user directories
- No privileged mode
- Memory limited to 512M via `deploy.resources.limits`
- cpu_shares set to 50 (standard)
- Password protection enabled by default (`AUTHENTICATION_ENABLED: true`)
- Only port 80 exposed internally (not published to host)

## Alternatives considered and rejected
- `user: $PUID:$PGID` — causes permission errors when the application tries to write note files and indexes to `/app/data`

## Data protection
- All persistent data stored under `/DATA/AppData/$AppID/data/`
- Notes are stored as plain markdown files, easily portable
