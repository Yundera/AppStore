# Jellyfin — Rationale

## What deviation / exception is being requested
The nginx-hash-lock sidecar runs as `user: 0:0` (root) with `AUTH_DISABLED: "true"` — it acts as a plain reverse proxy without hash-lock or OIDC authentication. The Jellyfin backend runs as `user: $PUID:$PGID` and accesses user media directories (`/DATA/Media/Movies`, `/DATA/Media/TV Shows`, `/DATA/Media/Music`, `/DATA/Downloads`).

## Why it is necessary
- **jellyfin-proxy (nginx-hash-lock)**: Runs as root to bind to port 80. Auth is disabled because Jellyfin has its own first-launch onboarding wizard that requires the user to create an admin account — this is an explicitly-listed valid exception in CONTRIBUTING.md's Security checklist.
- **jellyfin**: Runs as `$PUID:$PGID` to access user-owned media files in `/DATA/Media/` and `/DATA/Downloads/`. This is the Mixed Usage pattern.

## Security mitigations in place
- Jellyfin's built-in onboarding wizard forces admin account creation on first launch (cannot be bypassed)
- App data volumes map to `/DATA/AppData/$AppID/` only
- User media directories are the user's own files; Jellyfin reads them for indexing and streaming
- No privileged mode on any service
- Memory limits on both services (128M proxy, 1024M Jellyfin)
- Caddy labels only on the proxy sidecar; backend has no public routes

## Alternatives considered and rejected
- OIDC/hash-lock authentication — Jellyfin's native authentication is more appropriate; adding an external auth layer in front of Jellyfin's own login creates a confusing double-login experience
- Running proxy as non-root — nginx requires root to bind to port 80

## Data protection
- Jellyfin config persists in `/DATA/AppData/$AppID/config/`
- Cache persists in `/DATA/AppData/$AppID/cache/`
- User media directories contain the user's own files (read-only access for indexing/streaming)
- All data survives uninstall/reinstall
