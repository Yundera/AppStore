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
- The `plex-proxy` sidecar is a plain reverse proxy, **not** an authentication layer. It
  terminates the Caddy route and forwards to Plex on 32400, and it is configured with only
  `BACKEND_HOST`/`BACKEND_PORT`/`LISTEN_PORT`/`ALLOWED_EXTENSIONS`/`ALLOWED_PATHS` — none of
  the variables that would enable `nginx-hash-lock`'s own auth, so with none of them set it
  runs in `AUTH_MODE=none` and authenticates nothing. An earlier revision of this file
  claimed it gated web access; that claim was false and is corrected here.
- **Authentication is Plex's own**, which CONTRIBUTING's Security checklist accepts in place
  of a platform gate ("the app's own built-in auth"). An unauthenticated caller gets 401
  from Plex itself on `/library/sections`, `/:/prefs`, `/accounts`, `/clients`, `/servers`
  and `/myplex/account`, unchanged under a spoofed `X-Forwarded-For: 127.0.0.1`.
- An SSO sidecar is deliberately **not** used here, and should not be added: Plex's mobile,
  smart-TV and streaming clients authenticate with `X-Plex-Token` rather than an interactive
  browser flow, so gating the public route behind Authelia would 302 every such client to a
  login it cannot complete — breaking the remote access this app exists to provide. The
  honest fix for the old false claim is this documentation, not a real gate.

## Alternatives considered and rejected
- `user: $PUID:$PGID` — the LSIO image requires root at startup for s6-overlay init; setting a non-root user causes the entrypoint to fail
- Separate containers for system tasks and media access — Plex is a monolithic application that cannot be split

## Data protection
- All persistent data stored under `/DATA/AppData/$AppID/`
- User media directories contain the user's own files; Plex reads them for indexing and transcoding
