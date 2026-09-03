# Docmost — Rationale

## What deviation / exception is being requested

Two:

1. **Authentication is Docmost's own first-launch onboarding.** No AppShield / OIDC
   sidecar, and no pre-seeded credential — the workspace owner is created by the first
   person to reach the app.
2. **All three services run `user: "0:0"`** (`docmost-db`, `docmost-redis`, `docmost`).

Per CONTRIBUTING's *Rationale* section either one alone requires this file: "The app
ships with authentication disabled, or relies on the app's own first-launch onboarding
instead of an enabled default", and "The app runs as `user: 0:0`".

## Authentication

Docmost is itself the login gate. Nothing sits in front of it, and nothing behind it is
anonymous.

- **No pre-seeded credential exists.** The compose sets no admin user, password or API
  token. `$APP_DEFAULT_PASSWORD` appears only as the Postgres role password
  (`POSTGRES_PASSWORD`, and inside `DATABASE_URL`) — never as an application credential —
  so there is no shipped account for a visitor to try.
- **The first user to register becomes the workspace admin**, through Docmost's own
  `/setup/register` page. That is stated to the user *before* they install, in
  `tips.before_install` in all five supported locales.
- **Onboarding closes after that first use.** `POST /api/auth/setup` sits behind the
  server's `SetupGuard`, which counts workspaces and throws
  `ForbiddenException('Workspace setup already completed.')` as soon as one exists — the
  403 the store audit observed on a second attempt. A self-hosted instance exposes no
  public signup endpoint; every later account comes from the admin's
  `workspace/invites/*` flow.
- **Protected APIs answer 401 when unauthenticated** (`JwtAuthGuard` →
  `UnauthorizedException`, verified live in the store audit). The unauthenticated surface
  is the SPA shell plus login / forgot-password, which carry no workspace data.

This is CONTRIBUTING's Security-checklist alternative "the app's own built-in auth (e.g.
Jellyfin, Immich onboarding)", and the same shape as `Apps/Jellyfin` and `Apps/Immich`.
The residual exposure is the one those two also carry: between the container starting and
the owner completing `/setup/register`, whoever reaches the URL first claims the
workspace. The routes only exist while the app is running, and `tips.before_install` makes
creating the admin account step 2 of getting started.

Supporting the gate:

- `APP_SECRET` comes from `x-compose-app.secrets` (`DOCMOST_APP_SECRET: hex:32`), so the
  session-signing key is generated once per install into the app's `.env` — never baked
  into the store, and never regenerated (a rotated key logs every user out).
- `APP_URL` is pinned to `https://docmost-${APP_DOMAIN}`, so invitation and
  password-reset links are issued against the gateway hostname rather than an
  attacker-supplied `Host` header.
- Nothing is published to the host: the app uses `expose: "80"` only and is reached
  through the shared `pcs` network behind Caddy TLS.

## Why the root containers are necessary

- **`docmost-db` / `docmost-redis`**: the official `postgres` and `redis` images expect to
  start as root, take ownership of their data directory, then drop to their own service
  account (`postgres`, `redis`). Started as an arbitrary UID against a bind mount they
  cannot chown, `initdb` fails and the stack never comes up.
- **`docmost`**: keeps write access to the bind-mounted attachment store
  (`/app/data/storage`) whatever the ownership of the host directory.

All three mount **only** paths under `${DATA_ROOT:-/DATA}/AppData/docmost/` — `pgdata/`,
`redis/` and `storage/`. No user directory (`/DATA/Documents`, `/DATA/Downloads`,
`/DATA/Media`, `/DATA/Gallery`) and no host socket is mounted, so this is CONTRIBUTING's
"root containers are acceptable when volumes map exclusively to AppData" case, not the
mixed-access one.

## Security mitigations in place

- Only `docmost` joins the shared `pcs` network. Postgres and Redis live on the
  app-private `docmost-network` bridge, unreachable from other apps on the box.
- No `ports:`, no `privileged`, no `cap_add`, no device or socket mounts.
- Every image is version-pinned: `postgres:16.13-alpine`, `redis:7.2.13-alpine`,
  `docmost/docmost:0.70.3`.
- Memory and CPU limits on all three services (512M / 0.5, 256M / 0.25, 1G / 1.0).
- Mail goes through the PCS-bundled SMTP relay on the internal `smtp` host; invitations
  and password resets do not traverse a third-party provider.

## Alternatives considered and rejected

1. **AppShield / OIDC in front of Docmost** — rejected. AppShield reserves `/login`, and
   `/login` is Docmost's own login route, so the shield would shadow it. It would also
   break clients that authenticate straight against the Docmost API with a JWT instead of
   an interactive browser flow (`Apps/DocmostMCP` is one such client in this store), and
   it would stack a second login in front of Docmost's own workspace/member model.
2. **Pre-seeding an owner account with `$APP_DEFAULT_PASSWORD`** — rejected. Docmost
   0.70.3 creates the workspace and its first user in one transaction through
   `POST /api/auth/setup`; there is no environment variable or CLI for it, so seeding
   would mean inserting rows into Postgres by hand and keeping that insert in step with
   upstream's schema migrations.
3. **`user: $PUID:$PGID` on the datastores** — rejected for the reason above. For the
   `docmost` service itself the upstream image does ship as uid 1000 (`node`), so dropping
   privileges there is plausible; it has not been validated against an existing install
   whose `storage/` tree was written as root, so the app keeps `0:0` until that migration
   is tested.

## Data protection

- All state is under `${DATA_ROOT:-/DATA}/AppData/docmost/` — `pgdata/` (pages, users,
  permissions), `redis/`, and `storage/` (attachments and images) — declared in
  `x-compose-app.folders` and preserved across uninstall / reinstall and upgrades.
- Nothing outside that directory is mounted, so root inside these containers reaches no
  user file.
- `DOCMOST_APP_SECRET` lives in the app's `.env` and is never regenerated, so sessions and
  the data they unlock survive restarts and updates.
- The `docmost` service writes as uid 0, so attachments under `storage/` are root-owned in
  a file manager; the app's directories are chowned to `$PUID:$PGID` by
  `x-compose-app.folders`, so the user can still manage and remove the app folder.
