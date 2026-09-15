# Files — Rationale

## What deviation / exception is being requested

Three, all in the `files-backend` service:

1. It runs as `user: 0:0` (root) rather than `$PUID:$PGID`.
2. It bind-mounts the whole of `${DATA_ROOT:-/DATA}` read-write, not a subtree
   of `/DATA/AppData/files`.
3. It ships with **no authentication of its own** — no login page, no accounts.

## Why it is necessary

**Root.** This is a file manager whose job is the whole data tree, and that tree
includes `/DATA/AppData`. App data directories are routinely owned by other uids
with mode `0700` — a database container writing as its own user. Running as
`$PUID` those directories are unreadable, so a large part of what the app exists
to manage would show as empty folders with no explanation. Everything the app
*creates* is chowned back to `PUID:PGID` with `DIR_MODE`/`FILE_MODE`, so files a
user makes here still belong to them and stay usable by their other apps.

Capabilities are not a middle ground here. Docker has no ambient capabilities, so
`user: 1000` plus `cap_add: DAC_READ_SEARCH` grants a non-root process nothing —
the capability sits in the bounding set and is never raised. The choice is root
or a half-visible tree; the blast radius is pulled back in from the other side
instead (see below).

**The whole of `/DATA`.** Narrowing the mount to the user directories would drop
`/DATA/AppData` from the browser. That is the folder people most often need a file
manager for — pulling a config file out of an app, dropping a certificate in,
checking what is eating the disk — and it is what the app this replaces
(`Apps/FileBrowser`) has always mounted. The scope is stated in the app
`description` and again in `tips.before_install`, so it is visible before install.

**No built-in auth.** The app was written for a PCS that already has one auth
system, and deliberately does not add a second. This is the reason it exists
rather than FileBrowser: FileBrowser's anonymous share links force three path
prefixes (`share/`, `api/public/`, `static/`) to be carved out of the SSO gate,
and every exemption is a hole that has to stay correct forever. Files has no
sharing, so the only exempt path is `api/health`.

## Security mitigations in place

- **The gate is the only way in.** The publicly reachable service is the AppShield
  SSO sidecar. `files-backend` carries no Caddy labels and is **not** on the `pcs`
  network — it sits alone on `files-internal`, so no other app on the server can
  reach it, and there is no route to it that skips authentication.
- **`cap_drop: ALL`**, then back only the five the ownership model needs: `CHOWN`,
  `FOWNER`, `FSETID`, `DAC_OVERRIDE`, `DAC_READ_SEARCH`. No `SETUID`, no
  `SYS_ADMIN`, no `MKNOD`, no network capabilities.
- **`no-new-privileges:true`** — no setuid binary in the image can escalate.
- **`read_only: true`** with `/tmp` on tmpfs: the container's own filesystem is
  immutable, and the only writable path is the bind mount it is meant to manage.
- **The image shells out to nothing.** It is a single Go binary on Alpine with
  `ca-certificates` and `tzdata` — no shell-invoking code path, no docker socket,
  no `docker-cli`, no hook runner.
- **Resource limits** on both services (128M gate, 512M backend; `cpu_shares` 80
  and 50).
- **No anonymous surface.** `ALLOWED_PATHS` is `api/health` and nothing else, so
  there is no unauthenticated route that reads or writes a file.

## Alternatives considered and rejected

| Alternative | Why it was rejected |
|---|---|
| `user: $PUID:$PGID` | `/DATA/AppData` subdirectories owned by other uids at `0700` become unreadable — the tree renders as empty folders. |
| `user: $PUID` + `cap_add: DAC_READ_SEARCH` | Does nothing. Docker has no ambient capabilities, so a non-root process never gains the capability. |
| Mount only `/DATA/Documents`, `/DATA/Downloads`, `/DATA/Media` | Drops `/DATA/AppData`, the case a file manager is most often opened for, and is a regression against `Apps/FileBrowser`. |
| Keep `Apps/FileBrowser` instead | Upstream archived 2026-09-01. Its OIDC request (`filebrowser/filebrowser#1328`) was closed unimplemented, so it needs `auth.method=noauth` seeded into a bolt database plus three gate exemptions for share links. |
| Put `files-backend` on `pcs` | Any other app on the server could then reach an unauthenticated root process over all of `/DATA`. This is the one line in the compose that must not change. |
| Give the app its own login | A second credential store on a machine that already has SSO, and the exemptions that come with it. Not adding one is the point of the app. |

## Data protection

- The app writes only inside the bind mount; there is no other writable path.
- **Delete is not destroy.** Deleting moves the item to a trash folder under
  `/DATA/AppData/files`, with restore-to-original-location, delete-permanently and
  empty-trash in a dedicated Trash view. Auto-purge is `TRASH_RETENTION_DAYS`
  (30 by default; `0` disables it).
- Everything the app creates is chowned to `PUID:PGID` with `0775`/`0664`, so
  uploaded files stay readable and writable by the user's other apps rather than
  becoming root-owned islands.
- The app's own state directory is hidden from the browse tree, so a user cannot
  wander into the trash store and corrupt it from the file view.
- Uninstall keeps `/DATA/AppData/files` like any other app, so trash and the
  thumbnail cache survive a reinstall. Nothing outside that directory is the app's
  own state — the app stores no database.
