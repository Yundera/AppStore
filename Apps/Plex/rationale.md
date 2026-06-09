# Plex — Rationale

## What deviation / exception is being requested
Runs as `user: 0:0` (root) while accessing user media directories (`/DATA/Media/Movies`, `/DATA/Media/TV Shows`, `/DATA/Media/Music`, `/DATA/Downloads`). Also mounts `/dev/dri` for GPU hardware transcoding.

## Why it is necessary
The LinuxServer Plex image starts as root to perform internal setup (setting permissions, configuring hardware transcoding), then drops privileges to PUID:PGID internally via the LSIO s6-overlay init system. The `devices: /dev/dri` mount requires the container to start as root to access GPU device nodes for hardware-accelerated video transcoding.

## Security mitigations in place
- PUID/PGID environment variables ensure file operations run as the non-root user internally
- Memory limited to 1GB via `deploy.resources.limits`
- cpu_shares set to 50 (standard)
- `privileged: true` removed — only `/dev/dri` device pass-through is used
- Web access gated by nginx-hash-lock sidecar

## Alternatives considered and rejected
- `user: $PUID:$PGID` — the LSIO image requires root at startup for s6-overlay init; setting a non-root user causes the entrypoint to fail
- Separate containers for system tasks and media access — Plex is a monolithic application that cannot be split

## Data protection
- All persistent data stored under `/DATA/AppData/$AppID/`
- User media directories contain the user's own files; Plex reads them for indexing and transcoding
