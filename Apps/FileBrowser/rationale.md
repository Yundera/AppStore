# FileBrowser — Rationale

## What deviation / exception is being requested
Two things:

1. The backend bind-mounts `/DATA` itself, read-write, onto `/srv/` — a broad slice of
   the data directory rather than only `/DATA/AppData/filebrowser/` and a single user
   directory. It therefore reaches `/DATA/Documents`, `/DATA/Downloads`, `/DATA/Media`,
   `/DATA/Gallery` **and** `/DATA/AppData`, which holds the databases, configuration and
   secrets of every other app installed on the server.
2. The backend's own authentication is **disabled** (`--auth.method=noauth`), and
   `ALLOWED_PATHS` exempts three prefixes from the AppShield gate.

## Why it is necessary

### The `/DATA` mount
FileBrowser *is* the file manager for the PCS: its entire purpose is to give the
owner a browser-based view of their server's storage, the same way the CasaOS
built-in Files view does. Mounting only a subset would mean the user could not
reach files they created with another app, could not move a download into Media,
and could not use FileBrowser to fix or inspect an app's data directory — the
recovery use case it is most often installed for. Any narrower mount turns it into
a different, less useful app.

### `noauth` behind AppShield
Upstream `filebrowser/filebrowser` has no OIDC and never will: the request
(filebrowser/filebrowser#1328, opened 2021) was closed unimplemented and the
repository was archived on **2026-09-01**, with `v2.63.23` as the last release and
no further bug or security fixes. Its only auth methods are `json`, `proxy`, `hook`
and `noauth`. So the app cannot speak to the PCS's Dex directly, and SSO has to come
from a gate in front of it.

With the gate in front, the app's own password login is not a second factor — it is a
second prompt for the same person, and it collides with the shield: AppShield reserves
the `/login` location, so a backend that 302s to its own `/login` gets the shield's
"Login Required" page instead of its form and becomes unusable. `noauth` resolves
every request to user ID 1 (`auth/none.go`), which is the `admin` account the
`add-admin` init step seeds, so the owner lands in the UI with full administrator
rights and no second password. This is the same trade `Apps/ConvertX`
(`ALLOW_UNAUTHENTICATED=true`) already makes.

`proxy` auth was considered instead and rejected — see below.

### The `ALLOWED_PATHS` exemption
Share links are anonymous by design: the hash in the URL is the credential, and the
owner can add a password to the share on top of it. Behind an unqualified gate every
share link would redirect an outside recipient to a Yundera login they do not have,
and a documented headline feature of the app would be silently dead. The exemption
covers exactly the three prefixes a share needs — `share/` (the landing page),
`api/public/` (the endpoints it calls) and `static/` (its JS/CSS). The authenticated
API — `/api/resources`, `/api/users`, `/api/settings` — stays behind the gate.

## Security mitigations in place
- The mount is disclosed **before install**, in `x-casaos.tips.before_install`
  (English, Korean, Chinese, French, Spanish), so the user sees the full extent of
  the access on the install screen — including that a share link hands its recipient
  access to the file behind it.
- **Authentication is on, and it is the PCS's own SSO.** The AppShield sidecar
  self-registers with `auth-registrar` and gates every request through Dex, which is
  owner-only. There is no anonymous access to the file manager and no app-specific
  password to leak or leave at its default.
- **The unauthenticated backend is not reachable.** Because the backend has no auth of
  its own, `filebrowser-backend` carries no Caddy labels and is **not on the `pcs`
  network** — only on the app-private `filebrowser-internal` network, which the gate
  is the sole other member of. On `pcs` any other app on the server could have reached
  it directly; this is the mitigation that makes `noauth` acceptable and it is
  load-bearing.
- The backend runs as `$PUID:$PGID`, not root, so it can only touch what the server
  user can touch — it cannot escalate beyond the owner's own files.
- Only the app's own database directory (`/DATA/AppData/$AppID/db`) is declared in
  `x-compose-app.folders`; the app creates nothing else outside what the user asks for.
- Resource limits bound both containers (gate `cpu_shares: 80` / `128M`, backend
  `cpu_shares: 50` / `256M`).
- No host port is published by either service.

## Alternatives considered and rejected
- **Mount only `/DATA/Documents`, `/DATA/Downloads` and `/DATA/Media`.** Rejected:
  it removes the recovery/inspection use case (AppData) and splits the tree into
  three roots, so moving a file between them is a copy across mount points.
- **Mount `/DATA` read-only.** Rejected: upload, rename, edit, delete and share are
  the app's core features; a read-only FileBrowser is a file *viewer*.
- **Exclude `/DATA/AppData` with a narrower set of binds.** Rejected: Docker has no
  exclude primitive, so this means enumerating every sibling directory, and the list
  would silently go stale as the user creates new top-level folders.
- **Keep FileBrowser's own `json` password login behind the gate.** Rejected: the
  `/login` collision above makes it unreachable, and it adds a second password for the
  same single owner.
- **`--auth.method=proxy` with AppShield's `Remote-User` header.** Rejected despite
  being the "correct-looking" option. Proxy users that FileBrowser auto-provisions are
  created with `Admin: false` hard-coded (`auth/proxy.go`), not from the configured
  defaults, and the username is the IdP's email claim — not a value this compose can
  know at install time, so the admin account cannot be pre-seeded under the right name.
  With password login disabled the settings and user-management screens would then be
  permanently unreachable. `auth/proxy.go` also performs no trusted-proxy or source-IP
  check, so the header is believed from any caller. It buys per-user identity, which is
  worth nothing here: the orchestrator's OIDC owner policy is owner-only with no
  sharing, so there is exactly one human.
- **Migrating to FileBrowser Quantum** (`gtstef/filebrowser`), which has native OIDC.
  Not rejected — it is shipped separately as `Apps/FileBrowserQuantum` so it can be
  evaluated without disturbing this app's users. Its database format is incompatible
  with v2's, so it cannot be an in-place image swap.

## Data protection
Access is gated by the PCS's own SSO (AppShield → Dex), which is owner-only, so
revoking access is a matter of the Yundera account, not of an app-local credential.
The app's own state lives in `/DATA/AppData/$AppID/db/` and survives
uninstall/reinstall; share links the owner created are listed and revocable from the
app's Shares screen.

## Upstream status
`filebrowser/filebrowser` is archived as of 2026-09-01. This app is pinned to
`v2.63.23`, the final release. It will receive no further upstream fixes, including
security fixes — the reason `Apps/FileBrowserQuantum` exists as a maintained
successor to evaluate. `changelog.txt` in this directory is the upstream changelog as
it was last vendored (it stops at 2.20.1) and does not describe the shipped version.
