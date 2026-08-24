# Sonarr — Rationale

## What deviation / exception is being requested

Two, both listed in `CONTRIBUTING.md` as acceptable when documented here:

1. **Authentication is not enabled by the compose file.** There is no AppShield sidecar, no
   basic-auth gate and no auth environment variable. Sonarr relies on its own first-launch
   onboarding to establish the login instead.
2. **Volumes outside `/DATA/AppData/sonarr/`.** The container mounts
   `${DATA_ROOT:-/DATA}/Media/TV Shows` and `${DATA_ROOT:-/DATA}/Downloads` read-write.

## Why it is necessary

**Authentication.** Sonarr v4 has no default account to hand out — the credential is created by
the user, not by the image. On first load the UI renders a non-dismissible
`AuthenticationRequiredModal` and refuses to go any further until an authentication method
(Basic or Forms) and a username/password are set; the setting is then written to
`/config/config.xml` and persists. This is the same "handles authentication configuration on
first launch via an onboarding process" pattern `CONTRIBUTING.md` names as a valid exception
(Jellyfin, Immich). `tips.before_install` tells the user to complete it as the first step.

Fronting Sonarr with AppShield was rejected: it would place the PCS SSO login in front of
Sonarr's own login screen — a double login for the human — while the API path (`/api/v3`,
authenticated by the Sonarr API key) is what Prowlarr, Radarr and the download clients use to
talk to it. Those are machine callers on the `pcs` network with no browser and no OIDC flow, so
an SSO gate on the same hostname breaks the integrations that make the app useful.

**Media and download mounts.** Sonarr's whole job is to move finished downloads out of
`/DATA/Downloads` and into the TV library at `/DATA/Media/TV Shows`, renamed and sorted. Both
paths must be writable, and they must be the *shared* store folders — the point is that Jellyfin,
qBittorrent and Sonarr all see one library rather than three private copies.

## Security mitigations in place

- The container runs as `user: $PUID:$PGID`, never root, so it holds exactly the rights the
  PCS user already has over their own media — no privilege gain over a file manager.
- Directories are declared under `x-compose-app.folders` and created by Maison owned by
  `$PUID:$PGID` before first start; no hook creates or chowns anything.
- No host ports are published. The web UI is reachable only through Caddy over TLS on the
  three PCS routes; nothing listens on a host interface.
- `no_new_privileges` is implied by the non-root user; no privileged mode, no extra
  capabilities, no Docker socket.
- Memory capped at 512M and `cpu_shares: 50`, so a runaway import cannot starve the box.
- Image pinned to `lscr.io/linuxserver/sonarr:4.0.17` — no `:latest`.
- No credentials in the compose file; the admin password is the one the user picks during
  onboarding.

## Alternatives considered and rejected

- **AppShield / OIDC sidecar in front of Sonarr** — breaks the `/api/v3` integration path used
  by Prowlarr, Radarr and the download clients, and gives the human a second login in front of
  the one Sonarr already forces. Rejected.
- **Basic auth via a reverse-proxy gate** — same double-login problem, and it would shadow
  Sonarr's own account management (users, password reset) with a credential the app knows
  nothing about. Rejected.
- **Pre-seeding `config.xml` with Forms auth and `$APP_DEFAULT_PASSWORD`** — writing Sonarr's
  config file from outside means owning its schema across every upgrade, and a hook that
  rewrites an existing `config.xml` risks clobbering settings the user changed. The upstream
  onboarding modal already guarantees a credential is set. Rejected.
- **Mounting the media library read-only** — Sonarr would be unable to import, rename or
  organise anything, which is the entire function of the app. Rejected.

## Data protection

- Configuration, database and logs persist in `/DATA/AppData/sonarr/config/`, so uninstall
  with "keep data" followed by reinstall returns the same indexers, series list and login.
- The authentication setting lives in that same `config.xml` — the onboarding modal reappears
  only if the user deliberately deletes the config, never on a normal upgrade.
- `/DATA/Media/TV Shows` and `/DATA/Downloads` are the user's own directories, shared with the
  other media apps and untouched by installing or removing Sonarr.
- Nothing is written outside `${DATA_ROOT:-/DATA}`.
