# Prowlarr — Rationale

## What deviation / exception is being requested

Two, and they are linked:

1. **Prowlarr's own authentication is set to `External`** — it performs no login of its own and
   trusts the reverse proxy in front of it. That proxy is the **AppShield OIDC sidecar**
   (`prowlarr-gate`), which is enabled by default, so every human request has passed the PCS
   single sign-on before Prowlarr sees it.
2. **The backend service sits on the shared `pcs` network without being published.** It carries
   no Caddy labels, so it is not reachable from the internet; it is on `pcs` only so sibling apps
   can reach it by container name.

## Why it is necessary

**Why the sidecar rather than Prowlarr's own login.** Sonarr, Radarr and Lidarr are seeded with a
generated password through `seed/config/config.xml.tmpl`: they consume `<Username>`/`<Password>`
on first boot, create the user row in their database, and strip the elements from the file.
**Prowlarr does not do this.** It strips both elements *without* creating the user row, leaving the
`Users` table empty while Forms authentication is enforced against it — which locks out the owner
as well as everyone else, with no in-browser recovery path. Verified on `2.4.0` and on `latest`,
by inspecting the database after boot in both cases. So the seeded-credential pattern used by the
other three Servarr apps is not available here, and `External` plus a real gate is.

This is also the better outcome for the user: there is no password to copy out of a tips table.
Opening the tile goes through the SSO they already have.

**Why the backend is on `pcs`.** Prowlarr is an indexer *proxy*: Sonarr, Radarr and Lidarr query
it at `prowlarr-backend:9696` with an `X-Api-Key`, which is the wiring their own `tips` describe. That is
container-to-container traffic on the shared network and never leaves the host. Putting the
backend behind the gate instead would send those machine calls to an SSO login page and break the
media stack; exempting `/api/*` on the gate would un-gate Prowlarr's entire administrative
surface, which is worse than not having a gate at all.

## Security mitigations in place

- **Only the gate is published.** The gate service holds every Caddy label; the backend has none.
  The internet has no route to `prowlarr-backend:9696`.
- **The machine API is still authenticated.** With `External`, Prowlarr continues to enforce its
  API key on `/api/*`: verified that `/api/v1/health` returns `401` without `X-Api-Key` and `200`
  with it. `External` disables the *browser* login, not the API key.
- **The API key no longer leaks.** Under the previous `AuthenticationMethod=None`,
  `/initialize.json` served the admin API key to anonymous callers. That endpoint is now behind
  the gate.
- **Least privilege.** The backend runs as `$PUID:$PGID`, never root; the gate runs as the
  AppShield image's own unprivileged user. Both carry memory limits and `cpu_shares`, and both
  images are pinned.

## Bundled FlareSolverr

**What.** A third service, `prowlarr-flaresolverr`, solves Cloudflare challenges for the indexers
that sit behind one. A `post_up` init step registers it in Prowlarr as an indexer proxy tied to a
`flaresolverr` tag.

**Why bundled, not a separate store app.** FlareSolverr has no authentication: it is a headless
Chrome that fetches any URL it is sent. A standalone app would have to sit on the shared `pcs`
network, where every container of the PCS could use it as a browser proxy, including against
internal addresses. As a sidecar it sits only on the app-private `prowlarr-internal` network, which
nothing but the backend and the init step joins. Bundling is also what makes it work without
manual steps (below), and it keeps the solver's version moving with the app that depends on it.
The Suwayomi app follows the same pattern.

**Why the init step talks to Prowlarr's API.** Running the solver is not enough: Prowlarr only uses
one it has an indexer-proxy entry for, and only for indexers sharing that entry's tag. That entry
lives in `prowlarr.db`, which the store does not write directly (see the alternatives below), so
the step uses the documented `/api/v1/tag` and `/api/v1/indexerProxy` endpoints, with the API key
Prowlarr wrote into `config.xml` (mounted read-only). It only ever **adds**: the tag if there is
none, the proxy if no FlareSolverr proxy exists. A proxy the user configured or pointed elsewhere
is left alone. It does not tag indexers, because only Cloudflare-protected ones need it, and
Prowlarr's own test error tells the user which ones.

**Resources.** Each challenge is solved in its own Chromium (~250-300 MB while solving), Prowlarr
queries every tagged indexer in parallel, and FlareSolverr has no concurrency cap. At a 1G limit a
busy PCS recorded thousands of cgroup OOM kills, and every tagged indexer failed with `tab crashed`.
The 2G limit fits ~6-7 concurrent solves; idle, it sits near 350 MB. `cpu_shares` is kept low so a
burst of solves yields to everything else. The service runs as the image's own unprivileged
`flaresolverr` user (uid 1000) and mounts nothing.

## Alternatives considered and rejected

- **`AuthenticationMethod=Forms` with a seeded credential** (what Sonarr/Radarr/Lidarr use) —
  rejected because Prowlarr does not create the user row from `config.xml`. It produces a hard
  lockout, which is exactly what Touchstone recorded against this app.
- **Seeding the `Users` row directly into `prowlarr.db`** — technically proven to work (PBKDF2-
  HMAC-SHA512, 10000 iterations, 16-byte salt, 32-byte output, base64), but rejected: the database
  does not exist until migrations have run, writing to it means stopping a running app, and it
  couples the store to an undocumented Servarr schema and KDF that can change on any upgrade.
- **Leaving Prowlarr on its own first-run onboarding** — rejected: that is the state that shipped
  the app with `authenticationMethod: none`, a publicly reachable admin UI and an anonymously
  readable API key.
- **Gating `/api/*` as well** — rejected: it breaks indexer sync to Sonarr/Radarr/Lidarr.

## Known limitation

Because Prowlarr trusts its proxy, anything that can reach `prowlarr-backend:9696` directly is not
challenged for a browser session — it is still challenged for the API key on `/api/*`, but the UI
would render. That path is limited to containers on the `pcs` network of the same PCS; it is not
reachable from the internet. This is the same trust boundary the sibling API wiring already
depends on.

## Data protection

- All state lives under `/DATA/AppData/prowlarr/config`, covered by the bind mount and therefore
  by Maison's archive-on-uninstall.
- `seed/` is create-if-absent, so `config.xml` is written once and a user who later changes a
  setting keeps it.
- No user directories are mounted; nothing is written outside `${DATA_ROOT:-/DATA}`.
