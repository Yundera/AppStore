# FileBrowser Quantum — Rationale

## Why this app exists alongside `Apps/FileBrowser`

`filebrowser/filebrowser` — the project behind `Apps/FileBrowser` — was **archived
by its authors on 2026-09-01**. `v2.63.23` is the last release; there will be no
further bug fixes and no further security fixes. For an app that mounts the whole of
`/DATA` read-write, an unmaintained upstream is not a position the store can sit in
indefinitely.

`gtsteffaniak/filebrowser` ("FileBrowser Quantum") is the actively maintained fork
and the practical successor: same shape of app, released weekly, and with the
features the original never got — native OIDC, LDAP, indexed search, multiple named
sources, per-folder access rules.

It is shipped as a **separate app** rather than as a version bump of `Apps/FileBrowser`
because the two are not interchangeable: Quantum's database schema is incompatible
with v2's `database.db`, and its configuration moved from CLI flags plus a settings
row in the database to a `config.yaml`. Swapping the image on an existing install
would strand the user's accounts, shares and settings. Two apps lets a user evaluate
Quantum, move at their own pace, and run both side by side during the move.

## What this first version deliberately does not do

**No SSO.** `Apps/FileBrowser` is fronted by the AppShield gate and signs in with the
PCS's Yundera login. This app is not: it uses Quantum's own password login, which is
what the app does out of the box. That is the point of this first release — to see
the app behave as its authors intend, without a gate in the request path
confusing the picture.

Quantum *does* have native OIDC (`auth.methods.oidc` with `issuerUrl` / `clientId` /
`clientSecret`, auto-creating users on login and mapping an `adminGroup`), and it can
point straight at the PCS's Dex — no AppShield needed. The wiring is not trivial and
is left for a follow-up: `auth-registrar` issues client credentials only to a caller
it can attest by PTR on the `pcs` network, so it must be called *from inside this
container* at startup (an init container has a different container name and would be
rejected), which needs a small wrapper image. Registering with
`callback_path: /api/auth/oidc/callback` is the contract.

Until then, this app's login page is the only thing between the internet and all of
`/DATA`, and the before-install tip says so in those words.

## Deviations being requested

### The `/DATA` mount
The source is `${DATA_ROOT:-/DATA}` mounted on `/srv`, read-write — the same broad
mount `Apps/FileBrowser` already ships, and for the same reason. This *is* the file
manager for the PCS: mounting a subset would mean the owner cannot move a download
into Media, cannot reach files another app created, and cannot use it to inspect or
repair an app's data directory, which is the recovery use case it is most often
installed for. See `Apps/FileBrowser/rationale.md` for the alternatives considered
and rejected; they apply unchanged here.

`/DATA/AppData` is kept **browsable but out of the search index** (`rules` →
`folderPath: /AppData`, `viewable: true` in `seed/data/config.yaml`). This is not a
security control — the files are still reachable, exactly as in `Apps/FileBrowser` —
it is there because those trees are mostly sqlite and WAL files that change
constantly, and indexing them is index churn and memory spent on results nobody
searches for.

### `memory: 1G`
Four times `Apps/FileBrowser`'s limit. Quantum's search is backed by an index it
builds over the source tree, and the source tree is all of `/DATA`. The limit is
sized for a media library rather than for an empty server; an operator who narrows
the source in `config.yaml` can lower it.

## Security posture
- **Authentication is on and cannot be turned off from the store side.** Password
  auth is enabled in the seeded `config.yaml`, and `signup: false` — no self-service
  account creation on the login page.
- The admin password is the per-server `$APP_DEFAULT_PASSWORD`, never a hardcoded
  one. It is passed via `FILEBROWSER_ADMIN_PASSWORD`, which Quantum re-applies on
  every start; the tip and the env description both say so, and both give the two
  ways around it (clear the variable, or create a second account).
- Session tokens last 30 days (`tokenExpirationHours: 720`), matching the PCS-wide
  session policy rather than Quantum's own 2-hour default.
- The container runs as `$PUID:$PGID`, not root — the image's own default user is
  already uid 1000.
- `disableUpdateCheck: true`: no outbound release check. Version bumps come from the
  app store.
- Only `/DATA/AppData/$AppID/data` is declared in `x-compose-app.folders`; the app
  creates nothing else outside what the user asks for.
- No host port is published; the UI is reachable only through the gateway-terminated
  Caddy routes on the `pcs` network.
- The full extent of the `/DATA` mount, and the fact that this app is *not* behind
  the Yundera login, are both disclosed **before install** in
  `x-casaos.tips.before_install` (English, French, Chinese).

## Configuration
`config.yaml` is delivered through Maison's seed tree (`seed/data/config.yaml` →
`/DATA/AppData/filebrowserquantum/data/config.yaml`), which is create-if-absent — so
an operator's edits are never clobbered by an app update, at the cost that a new
option added in a later store release will not appear in an existing install. The
file is commented with what to compare against after a version bump.

No init containers are needed: Quantum creates its own database on first start, and
the admin account comes from the environment rather than a seeding CLI call.

## Version
Pinned to `gtstef/filebrowser:1.5.5-stable` (published 2026-08-30), the current
stable line. The `2.0.x-beta` line exists and changes the config format again —
notably `http.trustProxyHeaders` replacing v1.5.x's `http.trustedHeaders` — so it is
deliberately not used here.
