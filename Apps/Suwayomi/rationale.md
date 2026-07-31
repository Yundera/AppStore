# Suwayomi — Rationale

## What deviation / exception is being requested
The FlareSolverr bypass service (`ghcr.io/thephaseless/byparr`) runs as `user: 0:0` (root). The main Suwayomi service runs as `$PUID:$PGID`. Authentication uses Suwayomi's built-in simple login (`AUTH_MODE: simple_login`).

## Why it is necessary
- **Byparr (FlareSolverr)**: Runs a headless Chromium browser to bypass Cloudflare protection on manga sources. The official image requires root to launch the browser process, manage browser profiles, and handle system-level dependencies (fonts, certificates, shared libraries).
- **Suwayomi**: Runs correctly as `$PUID:$PGID` — no root required.

## Security mitigations in place
- Only the Byparr sidecar runs as root — the main Suwayomi service runs as `$PUID:$PGID`
- Byparr has no volumes mounted — no access to host filesystem
- Byparr has no Caddy labels — not publicly accessible, only reachable within the `pcs` network
- Memory limits on both services (1G Suwayomi, 512M Byparr)
- CPU shares configured on both services (50 Suwayomi, 20 Byparr)
- No privileged mode, no elevated capabilities
- Authentication enabled with `AUTH_MODE: simple_login` using `$APP_DEFAULT_PASSWORD`

## Alternatives considered and rejected
- `user: $PUID:$PGID` for Byparr — headless Chromium requires root for sandbox and system library access; the upstream image does not support non-root execution

## Data protection
- Suwayomi data persists in `/DATA/AppData/$AppID/data/`
- Downloaded manga persists in `/DATA/Media/Mangas/`
- Byparr stores no persistent data — it is stateless
