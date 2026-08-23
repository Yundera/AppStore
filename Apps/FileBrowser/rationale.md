# FileBrowser — Rationale

## What deviation / exception is being requested
The service bind-mounts `/DATA` itself, read-write, onto `/srv/` — a broad slice of
the data directory rather than only `/DATA/AppData/filebrowser/` and a single user
directory. It therefore reaches `/DATA/Documents`, `/DATA/Downloads`, `/DATA/Media`,
`/DATA/Gallery` **and** `/DATA/AppData`, which holds the databases, configuration and
secrets of every other app installed on the server.

## Why it is necessary
FileBrowser *is* the file manager for the PCS: its entire purpose is to give the
owner a browser-based view of their server's storage, the same way the CasaOS
built-in Files view does. Mounting only a subset would mean the user could not
reach files they created with another app, could not move a download into Media,
and could not use FileBrowser to fix or inspect an app's data directory — the
recovery use case it is most often installed for. Any narrower mount turns it into
a different, less useful app.

## Security mitigations in place
- The mount is disclosed **before install**, in `x-casaos.tips.before_install`
  (English, Korean, Chinese, French, Spanish), so the user sees the full extent of
  the access on the install screen.
- Authentication is on by default: the pre-install hook seeds the database with a
  single `admin` account whose password is the per-server `$APP_DEFAULT_PASSWORD`,
  never a hardcoded one. There is no anonymous access.
- The container runs as `$PUID:$PGID`, not root, so it can only touch what the
  server user can touch — it cannot escalate beyond the owner's own files.
- Only the app's own database directory (`/DATA/AppData/$AppID/db`) is declared in
  `x-compose-app.folders`; the app creates nothing else outside what the user asks
  for.
- Resource limits (`cpu_shares: 80`, `memory: 256M`) bound the container.
- The web UI is reachable only through the gateway-terminated Caddy routes on the
  `pcs` network; no host port is published.

## Alternatives considered and rejected
- **Mount only `/DATA/Documents`, `/DATA/Downloads` and `/DATA/Media`.** Rejected:
  it removes the recovery/inspection use case (AppData) and splits the tree into
  three roots, so moving a file between them is a copy across mount points.
- **Mount `/DATA` read-only.** Rejected: upload, rename, edit, delete and share are
  the app's core features; a read-only FileBrowser is a file *viewer*.
- **Exclude `/DATA/AppData` with a narrower set of binds.** Rejected: Docker has no
  exclude primitive, so this means enumerating every sibling directory, and the list
  would silently go stale as the user creates new top-level folders.

## Data protection
Access is gated by FileBrowser's own account system, seeded with one admin account
and a server-specific password that the before-install tip tells the user to change.
FileBrowser's per-user scope and permission settings let the owner restrict any
additional account to a subdirectory before sharing it. The app's own state lives in
`/DATA/AppData/$AppID/db/` and survives uninstall/reinstall, so revoking access is a
matter of changing credentials, not of losing configuration.
