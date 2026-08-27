# Plex — Rationale

## What deviation / exception is being requested
Runs as `user: 0:0` (root) while accessing user media directories (`/DATA/Media/Movies`, `/DATA/Media/TV Shows`, `/DATA/Media/Music`, `/DATA/Downloads`).

## Why it is necessary
The LinuxServer Plex image starts as root to perform internal setup (setting permissions, laying out `/config`), then drops privileges to PUID:PGID internally via the LSIO s6-overlay init system.

## Security mitigations in place
- PUID/PGID environment variables ensure file operations run as the non-root user internally
- Memory limited to 1GB via `deploy.resources.limits`
- cpu_shares set to 50 (standard)
- No `privileged: true` and no device pass-through: the container gets no host devices. `/dev/dri` is deliberately not mapped, because a PCS without an Intel/AMD render node cannot create the container at all; Plex transcodes in software, and hardware transcoding is a Plex Pass extra a user can add locally if their host has a GPU.
- Web access gated by nginx-hash-lock sidecar

## Alternatives considered and rejected
- `user: $PUID:$PGID` — the LSIO image requires root at startup for s6-overlay init; setting a non-root user causes the entrypoint to fail
- Separate containers for system tasks and media access — Plex is a monolithic application that cannot be split

## Data protection
- All persistent data stored under `/DATA/AppData/$AppID/`
- User media directories contain the user's own files; Plex reads them for indexing and transcoding
