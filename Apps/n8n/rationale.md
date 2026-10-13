# n8n — Rationale

## What deviation / exception is being requested

Two:

1. **No auth gate enabled before the first visitor.** n8n ships behind no AppShield
   sidecar and no OIDC layer — the Caddy labels point straight at the `n8n` service on
   port 80. Access is controlled by n8n's own first-launch owner setup: the first person
   to reach the app creates the owner account, and every request is unauthenticated until
   they do.
2. **`n8n-postgres` runs as `user: "0:0"`.** The application container itself runs as
   `$PUID:$PGID`.

## Why it is necessary

- **Onboarding auth.** n8n owns its own user model — owner account, additional users,
  sessions, API keys, and the credential vault that holds every third-party secret a
  workflow uses. The setup screen is the app's first screen and cannot be skipped or
  disabled. Once completed, the gate is enforced on every route: an anonymous client gets
  401 on the data endpoints and is redirected to the sign-in page in the browser. This is
  the same pattern as `Apps/Jellyfin` and `Apps/Immich`, and CONTRIBUTING's Security
  checklist lists app-own onboarding as an acceptable alternative to a pre-enabled gate.
- **Postgres as root.** The official `postgres` image starts as root so its entrypoint can
  `initdb` and `chown` the data directory, then drops to the `postgres` user for the server
  process itself. Forcing `user: $PUID:$PGID` makes `initdb` fail on a fresh volume.

## Security mitigations in place

- The owner-setup screen is the app's first screen — there is no path into the editor,
  the workflow list or the credential vault that bypasses it.
- `tips.before_install` tells the user, before they install, that first launch asks them to
  create an owner account, so the claim step is expected rather than discovered.
- The database is on `n8n-internal`, a compose-private bridge, and is **not** attached to
  the shared `pcs` network. Nothing outside this compose project can reach it, and it has
  no Caddy labels and publishes no host port.
- The database password is `N8N_DB_PASSWORD`, an app-specific secret (seeded from the old
  box-wide password on installs that already had it, generated otherwise), not a
  literal baked into the compose file.
- `n8n` runs as `$PUID:$PGID`, not root.
- No host ports are published by either service; the web UI is reachable only through Caddy
  over the shared network.
- Memory and CPU limits on both services (1G/1.0 CPU for n8n, 512M/0.5 for Postgres).
- No privileged mode, no Docker socket, no host mounts.

## Alternatives considered and rejected

- **AppShield/OIDC in front of n8n** — n8n's own owner account cannot be turned off, so
  fronting the whole app produces two sign-ins for one app: the platform SSO, then n8n's
  own login. Rejected for the same reason as Jellyfin's.
- **Seeding the owner account at install time** — n8n creates the owner through its own
  setup endpoint rather than through configuration; there is no supported environment
  variable that pre-creates it. Seeding would mean scripting against an internal endpoint
  that carries no compatibility promise, and it would hand the user an account whose
  password they did not choose for a vault holding their third-party credentials.
- **`user: $PUID:$PGID` on `n8n-postgres`** — `initdb` cannot create and chown
  `/var/lib/postgresql/data` as a non-root user; the container exits on first start.

## Data protection

- Workflows, credentials and n8n settings persist in `/DATA/AppData/$AppID/data/`.
- The Postgres cluster persists in `/DATA/AppData/$AppID/pgdata/`.
- Nothing outside `/DATA/AppData/$AppID/` is mounted — no user directories, no broad slice
  of `/DATA`.
- Both directories are declared in `x-compose-app.folders` and chowned to `$PUID:$PGID`
  before every `up`.
- All data survives uninstall/reinstall.
