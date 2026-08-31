# Prowlarr — Rationale

## What deviation / exception is being requested

Prowlarr is protected by **its own built-in Forms authentication**, seeded on so that it
is enabled before the app is ever reachable, rather than by the recommended
**AppShield OIDC sidecar** (`ghcr.io/yundera/appshield`).

Per CONTRIBUTING's Security checklist this is an "acceptable alternative — the app's own
built-in auth … enabled by default", and this file records why that path was taken and
how "enabled by default" is actually achieved.

## Why it is necessary

Prowlarr is an API-first application, and the browser UI and the machine API share one
origin. Prowlarr pushes indexer definitions to Sonarr/Radarr/Lidarr, the *arr apps call
their download client, and every one of those calls authenticates with an `X-Api-Key`
header against `/api/v1/…` on the same host the browser uses.

Putting an OIDC sidecar in front of that origin forces a choice, and neither branch is
good:

- **No exemption** — the sidecar 302s the machine calls to an SSO login page. Prowlarr
  can no longer sync, the download client can no longer report back, and the media stack
  silently stops working.
- **Exempt `/api/*`** — the exemption covers the entire administrative surface. Every
  destructive operation Prowlarr can perform is an `/api/v1/…` call, so a gate that lets
  them all through unauthenticated is not a gate.

The app's own Forms auth does not have this problem: it distinguishes a browser session
(cookie) from an API client (`X-Api-Key`) on the same origin, and gates both.

## Security mitigations in place

- **Auth is enabled before first reach, not after.** `seed/config/config.xml.tmpl` ships
  `AuthenticationMethod=Forms` with `AuthenticationRequired=Enabled`, and Maison writes it
  into `/DATA/AppData/prowlarr/config/config.xml` at install — before the container ever
  starts. There is no window in which the app serves anonymously.
- **A unique password per app, per install.** `x-compose-app.secrets` generates
  `PROWLARR_ADMIN_PASSWORD` as `alnum:24` (~143 bits) once into the app's `.env`. It is not
  shared with any other app and is not the platform password.
- **The credential is disclosed before install** in `tips.before_install`, so the user can
  sign in without reading a log or a config file.
- **`/initialize.json` is gated.** With `AuthenticationMethod=None` that endpoint serves the
  admin API key to anonymous callers; under Forms it redirects to `/login`.
- **Least privilege.** The container runs as `$PUID:$PGID` (never root), uses `expose:` with
  no host port publishing, is reached only over TLS through the shared `pcs` Caddy network,
  and carries explicit memory and `cpu_shares` limits.

## Alternatives considered and rejected

- **AppShield OIDC sidecar** — rejected for the reason above: it either breaks inter-app
  API authentication or requires an `/api/*` exemption that neuters the gate.
- **Relying on the app's first-run "Authentication Required" modal** — rejected because it
  does not gate anything. Measured on a real install from a cookieless context that had
  never signed in: `GET /` returned the full SPA, a deep link to `/system/status` rendered
  completely behind the modal (disk space, mapped paths, health warnings),
  `/initialize.json` returned the admin API key, and the API accepted an authenticated
  write using that anonymously-obtained key. The modal is a client-side overlay.
- **`AuthenticationMethod=Forms` with no seeded credential** — rejected because it is a hard
  lockout. With no user row in `prowlarr.db` the login page offers no registration path and
  every credential fails, so the owner cannot get in either.
- **`AuthenticationMethod=External`** (delegate to the reverse proxy) — rejected: it is the
  sidecar option in a different costume and inherits the same API problem.

## Data protection

- `seed/` is **create-if-absent**, so `config.xml` is written once and never rewritten.
  Prowlarr consumes `<Username>`/`<Password>` on first boot, creates the user in `prowlarr.db`
  and strips both elements from the file — so a password the user changes later is never
  reset by a restart, an update or a store upgrade.
- All app state lives under `/DATA/AppData/prowlarr/config`, which is covered by the app's
  bind mount and therefore by Maison's archive-on-uninstall.
- The generated secret lives in the app's `.env` and is never regenerated, so restores and
  reinstalls keep working against existing data.
