# Filestash — Rationale

## What deviation / exception is being requested

1. The whole of `${DATA_ROOT:-/DATA}` is bind-mounted read-write at `/DATA`.
2. The image is pinned by **digest** under a `latest` tag, not by a version tag.
3. The container's `command` is overridden by a one-line `sh -c` wrapper.
4. Authentication is the app's own login page, not the PCS single sign-on.

## Why it is necessary

**The `/DATA` mount.** The app exists to move files between this server and remote
storage (Backblaze B2, S3, SFTP, WebDAV). The "My Server" connection is Filestash's
`local` backend, and what it can send is exactly what is mounted. A subset would mean
the owner cannot send their Media library, or cannot pull a backup back into
Documents. Read-write because pulling files back is half the use case. Same reasoning
and same mount as `Apps/FileBrowser` and `Apps/FileBrowserQuantum`.

**Digest pin.** Upstream (`machines/filestash`) publishes no version tags: the only
current, multi-arch tag is a rolling `latest` (the hash-named tags stopped in 2023 and
are amd64-only). `latest@sha256:…` freezes the multi-arch manifest list as of
2026-10-16. A bump means changing the digest.

**The `command` wrapper.** Filestash takes its admin password as a bcrypt hash in
`ADMIN_PASSWORD`. Maison writes `.env` values verbatim and unquoted, and compose
interpolates `$` inside them, so `$2a$10$…` reached the container mangled (checked:
`docker compose config` renders it as `$$2a$$10`). The hash is therefore rendered by
Maison into `state/admin.bcrypt` (`x-compose-app.files`, `ensure: always`, mode 0600,
owned by `$PUID`), and the wrapper reads it into the environment and `exec`s the
binary, so Filestash is still PID 1.

Because compose never sees the hash, a password changed from Maison would not
recreate the container (Maison applies it with a plain `compose up`). The old
process kept the old password: seen on wisera, where the change returned ok and the
new password was refused. The `filestash.admin-password-rev` label carries the
plaintext password so the container definition changes with it. Nothing reads it.
It is visible only to `docker inspect` (root on the box), which is less than the
plain env var other store apps use for their admin password.

**Own login rather than SSO.** Filestash's login page is the backend picker, and
each remote backend authenticates with that service's own credentials typed there.
An AppShield in front would add a second login before that page, and would also need
path exemptions for share links. "My Server" is protected by the admin password,
24 random characters generated per install. Wiring Filestash's own identity-provider
plugins to the PCS's Dex is left for a follow-up.

## Security mitigations in place

- The admin password is a per-app secret (`FILESTASH_ADMIN_PASSWORD: password:24`),
  shown via `credentials`, and changeable from Maison (`change: apply: env`). Its
  bcrypt sibling is regenerated on change and re-rendered into `admin.bcrypt` on
  every up.
- `ADMIN_PASSWORD` takes precedence over a hash saved from the admin console (tested:
  with env hash A and config hash B, only A logs in). Maison's credential stays
  authoritative and never shows a stale password. The tip says so.
- The `local` connection's path is pinned to `/DATA/` in the seeded `config.json`.
  Filestash enforces a pin as a prefix of the submitted `path`, and the submitted path
  becomes the session's root. The current login frontend does not prefill or hide
  pinned fields, though: it shows an empty Path box and sends `"path": null`, which is
  refused with "Not Allowed" before the password is checked. Hence the
  `My Server (/DATA)` label, and the tip and credential note telling the user to type
  `/DATA`. Dropping the pin instead would let an empty Path open the container's
  whole filesystem.
  Tested: a session requested with `path: /etc/` is refused ("Not Allowed"), and a
  `../` traversal is refused ("Can't use filesystem").
- The container runs as `$PUID:$PGID` (the image's own user is uid 1000). Files under
  `/DATA/AppData` owned by other uids with restrictive modes stay unreadable.
- `general.secret_key` (sessions, share links) is a per-install `alnum:16` secret
  (Filestash requires exactly 16 alphanumerics), seeded once into `config.json`.
- Filestash's scanner protection is on by default. Its web console
  (`features.server.console_enable`) and telemetry are off by default and are left
  off.
- No host port is published: the UI is reachable only through the Caddy routes on
  the `pcs` network.
- The full extent of the `/DATA` mount, and the fact that this app is not behind the
  server's SSO, are disclosed before install in `tips.before_install` (en, fr, zh).

## Alternatives considered and rejected

- **`auth.admin` in a rendered `config.json` with `ensure: always`.** This would
  clobber every setting the owner saves from the admin console (connections,
  branding) on each start.
- **`env_file` with `format: raw`.** Depends on a recent compose and on Maison
  tolerating a second env file. The `sh` wrapper needs nothing from either.
- **Mounting only Documents/Media.** Breaks the "back up anything on my server" use
  case, and is inconsistent with the store's other file managers.

## Data protection

App state (`config.json`, share/metadata sqlite, logs) lives in
`/DATA/AppData/filestash/state/` and survives uninstall/reinstall. `config.json` is
seeded create-if-absent, so the owner's edits are never overwritten. A new option
added in a later store release will not reach an existing install. Filestash itself
never deletes anything outside an explicit user action.

Transfers between two backends go through the browser: download from one, upload to
the other. That is fine for ad-hoc copies and wrong for bulk or scheduled backup. The
before-install tip points to RClone / Duplicati for that.
