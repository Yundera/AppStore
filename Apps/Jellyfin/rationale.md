# Jellyfin — Rationale

## What deviation / exception is being requested
The nginx-hash-lock sidecar runs as `user: 0:0` (root) with `AUTH_DISABLED: "true"` — it acts as a plain reverse proxy without hash-lock or OIDC authentication. The Jellyfin backend runs as `user: $PUID:$PGID` and bind-mounts four user directories (`/DATA/Media/Movies`, `/DATA/Media/TV Shows`, `/DATA/Media/Music`, `/DATA/Downloads`) **read-write**; `x-compose-app.folders` also creates them and chowns them to `$PUID:$PGID` before every `up`.

## Why it is necessary
- **jellyfin-proxy (nginx-hash-lock)**: Runs as root to bind to port 80. Auth is disabled because Jellyfin has its own first-launch onboarding wizard that requires the user to create an admin account — this is an explicitly-listed valid exception in CONTRIBUTING.md's Security checklist.
- **jellyfin**: Runs as `$PUID:$PGID` to access user-owned media files in `/DATA/Media/` and `/DATA/Downloads/`. This is the Mixed Usage pattern. The media mounts are read-write rather than `:ro` because Jellyfin writes alongside the media it indexes — sidecar NFO/metadata files, downloaded artwork and subtitles, and trickplay/chapter images are stored next to the media by default. A `:ro` mount makes those features fail at runtime, so the app has delete-capable access to the whole of `/DATA/Media/Movies`, `/DATA/Media/TV Shows`, `/DATA/Media/Music` and `/DATA/Downloads`.

## Security mitigations in place
- Jellyfin's built-in onboarding wizard forces admin account creation on first launch (cannot be bypassed)
- App data volumes map to `/DATA/AppData/$AppID/` only
- User media directories hold the user's own files; Jellyfin reads them for indexing and streaming and writes only its own metadata sidecars there — but the mount grants full write access, so this is a convention, not an enforced limit
- No privileged mode on any service
- Memory limits on both services (128M proxy, 1024M Jellyfin)
- Caddy labels only on the proxy sidecar; backend has no public routes

## Alternatives considered and rejected
- OIDC/hash-lock authentication — Jellyfin's native authentication is more appropriate; adding an external auth layer in front of Jellyfin's own login creates a confusing double-login experience
- Running proxy as non-root — nginx requires root to bind to port 80
- Mounting the media directories `:ro` — Jellyfin then cannot write NFO/metadata sidecars, downloaded artwork/subtitles or trickplay images next to the media, and library scans log write errors on every item

## Data protection
- Jellyfin config persists in `/DATA/AppData/$AppID/config/`
- Cache persists in `/DATA/AppData/$AppID/cache/`
- User media directories (`/DATA/Media/Movies`, `/DATA/Media/TV Shows`, `/DATA/Media/Music`, `/DATA/Downloads`) are mounted read-write and are chowned to `$PUID:$PGID` on every start — Jellyfin can create, modify and delete anything under them. This is disclosed in `tips.before_install`, which lists the media locations the app reaches
- Nothing outside those four user directories and `/DATA/AppData/$AppID/` is mounted
- All data survives uninstall/reinstall
