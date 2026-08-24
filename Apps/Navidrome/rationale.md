# Navidrome — Rationale

## What deviation / exception is being requested
The `navidrome` service runs as `user: "0:0"` (root) while bind-mounting a user
directory, `${DATA_ROOT:-/DATA}/Media/Music/`, in addition to its own AppData
directory `${DATA_ROOT:-/DATA}/AppData/navidrome/data/`. This is the Mixed Usage
pattern, which CONTRIBUTING.md asks to be documented here.

Authentication is also not pre-configured in the compose file: Navidrome creates
its admin account through a mandatory first-launch onboarding screen, which is an
explicitly listed valid exception in the Security checklist.

## Why it is necessary
- **Root user**: the upstream `deluan/navidrome` image starts as root and drops to
  its own runtime user internally; it also needs to bind port 80, which is the port
  Caddy proxies to (`ND_PORT: 80`). Existing installations already have a
  root-created SQLite database and cache tree under
  `/DATA/AppData/navidrome/data/`; switching the container user would leave that
  tree unwritable and break the upgrade path for users on a previous version,
  since `x-compose-app.folders` chowns the declared directory itself and not its
  contents.
- **`/DATA/Media/Music` mount**: Navidrome is a music server. Its whole purpose is
  to index and stream the music library the user manages through the PCS file
  tools, so the shared media directory is the library it must read.

## Security mitigations in place
- The music library is mounted **read-only** (`:ro`). Navidrome can index and
  stream the user's files but cannot modify, move or delete them.
- The mount is scoped to `/DATA/Media/Music`, not `/DATA/Media` or `/DATA`.
- Writable state is confined to `/DATA/AppData/navidrome/data/`.
- No privileged mode, no host networking, no published host ports — the web UI is
  reachable only through Caddy over the shared network via `expose: 80`.
- Memory limit of 512M and `cpu_shares: 50`.
- Navidrome's own login gate is enabled by default; the admin account must be
  created before any content is reachable.

## Alternatives considered and rejected
- **`user: $PUID:$PGID`** — would match the user-directory rule, but the library
  mount is read-only so no user file can be written with the wrong ownership, and
  the change would strand the root-owned database of every existing installation
  (data loss / stopped app on upgrade), which the Data Persistence requirement
  forbids.
- **Copying music into AppData** — duplicates the user's entire library on disk and
  breaks the point of a shared `/DATA/Media/Music`.
- **AppShield/OIDC sidecar in front** — Navidrome's Subsonic API is consumed by
  third-party mobile clients that authenticate against Navidrome's own user
  database; an SSO gate in front would break every Subsonic client and add a
  double login for the web UI.

## Data protection
- Database, configuration, playlists and user accounts persist in
  `/DATA/AppData/navidrome/data/` and survive uninstall/reinstall.
- The user's music files are never written to: the mount is `:ro`.
- `x-compose-app.folders` creates both directories with `$PUID:$PGID` ownership
  before every `up`, so the user can always inspect or remove them.
