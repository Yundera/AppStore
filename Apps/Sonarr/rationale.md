# Sonarr — Rationale

## What deviation / exception is being requested

Two, both listed in `CONTRIBUTING.md` as acceptable when documented here:

1. **Authentication is the app's own, not the recommended AppShield OIDC sidecar.** Sonarr is
   protected by its built-in **Forms** authentication, seeded on so that it is enabled before
   the app is ever reachable. CONTRIBUTING's Security checklist names "the app's own built-in
   auth … enabled by default" as an acceptable alternative; this file records why that path was
   taken and how "enabled by default" is actually achieved.
2. **Volumes outside `/DATA/AppData/sonarr/`.** The container mounts
   `${DATA_ROOT:-/DATA}/Media/TV Shows` and `${DATA_ROOT:-/DATA}/Downloads` read-write.

## Why it is necessary

**Authentication.** Sonarr is API-first, and the browser UI and the machine API share one
origin. Prowlarr pushes indexer definitions to Sonarr, the download client reports back, and
every one of those calls authenticates with an `X-Api-Key` header against `/api/v3/…` on the
same host the browser uses.

Putting an OIDC sidecar in front of that origin forces a choice, and neither branch is good:

- **No exemption** — the sidecar 302s the machine calls to an SSO login page. Prowlarr can no
  longer sync, the download client can no longer report back, and the media stack silently
  stops working. The human also gets a second login in front of Sonarr's own.
- **Exempt `/api/*`** — the exemption covers the entire administrative surface. Every
  destructive operation Sonarr can perform is an `/api/v3/…` call, so a gate that lets them all
  through unauthenticated is not a gate.

Sonarr's own Forms auth does not have this problem: it distinguishes a browser session (cookie)
from an API client (`X-Api-Key`) on the same origin, and gates both.

**Media and download mounts.** Sonarr's whole job is to move finished downloads out of
`/DATA/Downloads` and into the TV library at `/DATA/Media/TV Shows`, renamed and sorted. Both
paths must be writable, and they must be the *shared* store folders — the point is that
Jellyfin, qBittorrent and Sonarr all see one library rather than three private copies.

## Security mitigations in place

- **Auth is enabled before first reach, not after.** `seed/config/config.xml.tmpl` ships
  `AuthenticationMethod=Forms` with `AuthenticationRequired=Enabled`, and Maison writes it into
  `/DATA/AppData/sonarr/config/config.xml` at install — before the container ever starts. There
  is no window in which the app serves anonymously.
- **A unique password per app, per install.** `x-compose-app.secrets` generates
  `SONARR_ADMIN_PASSWORD` as `alnum:24` (~143 bits) once into the app's `.env`. It is not shared
  with any other app and is not the platform password.
- **The credential is disclosed before install** in `tips.before_install`, so the user can sign
  in without reading a log or a config file.
- **`/initialize.json` is gated.** With `AuthenticationMethod=None` that endpoint serves the
  admin API key to anonymous callers; under Forms it redirects to `/login`.
- The container runs as `user: $PUID:$PGID`, never root, so it holds exactly the rights the PCS
  user already has over their own media — no privilege gain over a file manager.
- Directories are declared under `x-compose-app.folders` and created by Maison owned by
  `$PUID:$PGID` before first start; no hook creates or chowns anything.
- No host ports are published. The web UI is reachable only through Caddy over TLS on the three
  PCS routes; nothing listens on a host interface.
- `no_new_privileges` is implied by the non-root user; no privileged mode, no extra
  capabilities, no Docker socket.
- Memory capped at 512M and `cpu_shares: 50`, so a runaway import cannot starve the box.
- Image pinned to `lscr.io/linuxserver/sonarr:4.0.17` — no `:latest`.
- No credential is hardcoded in the compose file; the password is generated per install.

## Alternatives considered and rejected

- **AppShield / OIDC sidecar in front of Sonarr** — breaks the `/api/v3` integration path used
  by Prowlarr, Radarr and the download clients, or requires an `/api/*` exemption that neuters
  the gate. Rejected.
- **Basic auth via a reverse-proxy gate** — same double-login problem, and it would shadow
  Sonarr's own account management (users, password reset) with a credential the app knows
  nothing about. Rejected.
- **Relying on Sonarr's first-run "Authentication Required" modal** — this was the previous
  design, and it was rejected after measurement: the modal does not gate anything. From a
  cookieless context that had never signed in, `GET /` returned the full SPA, a deep link to
  `/system/status` rendered completely behind the modal (disk space, mapped paths, health
  warnings), `/initialize.json` returned the admin API key, and the API accepted an
  authenticated write using that anonymously-obtained key. The modal is a client-side overlay,
  not the non-dismissible gate it appears to be. Rejected.
- **`AuthenticationMethod=Forms` with no seeded credential** — rejected because it is a hard
  lockout. With no user row in `sonarr.db` the login page offers no registration path and every
  credential fails, so the owner cannot get in either.
- **`AuthenticationMethod=External`** (delegate to the reverse proxy) — the sidecar option in a
  different costume; inherits the same API problem. Rejected.
- **Mounting the media library read-only** — Sonarr would be unable to import, rename or
  organise anything, which is the entire function of the app. Rejected.

## Data protection

- `seed/` is **create-if-absent**, so `config.xml` is written once and never rewritten. Sonarr
  consumes `<Username>`/`<Password>` on first boot, creates the user in `sonarr.db` and strips
  both elements from the file — so a password the user changes later is never reset by a
  restart, an update or a store upgrade. (This is what made an earlier revision of this file
  reject config seeding: a hook that *rewrites* an existing `config.xml` would indeed clobber
  user settings. `seed/` does not rewrite.)
- Configuration, database and logs persist in `/DATA/AppData/sonarr/config/`, so uninstall with
  "keep data" followed by reinstall returns the same indexers, series list and login.
- The generated secret lives in the app's `.env` and is never regenerated, so restores and
  reinstalls keep working against existing data.
- `/DATA/Media/TV Shows` and `/DATA/Downloads` are the user's own directories, shared with the
  other media apps and untouched by installing or removing Sonarr.
- Nothing is written outside `${DATA_ROOT:-/DATA}`.
