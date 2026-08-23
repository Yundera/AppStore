# Dufs — Rationale

## What deviation / exception is being requested
The service bind-mounts `${DATA_ROOT:-/DATA}` itself, read-write, onto `/srv` — a
broad slice of the data directory rather than only `/DATA/AppData/dufs/` and a
single user directory. It therefore reaches `/DATA/Documents`, `/DATA/Downloads`,
`/DATA/Media`, `/DATA/Gallery` **and** `/DATA/AppData`, which holds the databases,
configuration and secrets of every other app installed on the server. It serves
that tree with `--allow-upload --allow-delete --allow-symlink --allow-archive`,
so the mount is not only broad but fully writable and downloadable as archives.

## Why it is necessary
Dufs is the WebDAV front end for the PCS: its purpose is to let the owner mount
their server's storage as a network drive from Windows, macOS, Linux or a phone,
and to browse the same tree from a web UI. That is the same job FileBrowser does
over HTTP, and it fails for the same reason if the mount is narrowed — a user
could not move a download into Media, could not reach files another app created,
and could not use the mounted drive to inspect or repair an app's data directory.
A WebDAV drive that exposes one subdirectory is a different, much less useful app,
and the user already has `/DATA/AppDataShared` if that is all they want.

## Security mitigations in place
- The mount is disclosed **before install**, in `x-casaos.tips.before_install`
  (English and Chinese), and again in the app `description`, so the user sees the
  full extent of the access on the install screen rather than after installing.
- The `/srv` mount also carries a per-volume description under the service's own
  `x-casaos.volumes`, which is what the dashboard shows for the running app.
- Authentication is on by default and enforced by dufs itself: `--auth
  admin:$APP_DEFAULT_PASSWORD@/:rw` seeds a single `admin` account with the
  per-server password, never a hardcoded one. There is no anonymous access — an
  unauthenticated request to any path answers `401` with a Digest/Basic challenge.
- The container runs as `$PUID:$PGID`, not root, so it can only touch what the
  server user can touch — it cannot escalate beyond the owner's own files.
- Only user-facing directories are declared in `x-compose-app.folders` (see below);
  the app creates nothing else and takes ownership of nothing else.
- Resource limits (`cpu_shares: 50`, `memory: 128M`, `cpus: 0.5`) bound the container.
- The web UI and WebDAV endpoint are reachable only through the gateway-terminated
  Caddy routes on the `pcs` network; no host port is published.

## Alternatives considered and rejected
- **Mount only `/DATA/Documents`, `/DATA/Downloads` and `/DATA/Media`.** Rejected:
  it removes the inspection/recovery use case and splits the tree into three WebDAV
  roots, so a drag between them is a copy across mount points rather than a rename.
- **Mount `/DATA` read-only.** Rejected: upload, rename, delete and WebDAV write are
  the advertised core features; a read-only Dufs is a file *viewer*, and a read-only
  network drive is not what "mount as a network drive" means to a user.
- **Exclude `/DATA/AppData` with a narrower set of binds.** Rejected: Docker has no
  exclude primitive, so this means enumerating every sibling directory, and the list
  goes stale the moment the user creates a new top-level folder.
- **Drop `--allow-symlink`.** Kept for now, but recorded here as the one flag worth
  revisiting. It does *not* mean "follow the user's own symlinks" — those resolve
  inside `/srv` and are followed without it. It means specifically "allow symlink to
  files/folders **outside** root directory", so it is what lets a link escape the
  mounted `/DATA`. What bounds it is the image: `sigoden/dufs` is a two-layer
  scratch-style image holding little more than the static binary, so there is
  essentially nothing outside `/srv` in that mount namespace to reach. Removing the
  flag would still be a strict reduction in exposure and costs the user nothing that
  the PCS layout makes reachable.

## Why `/DATA` and `/DATA/AppData` are not declared under `folders`
A Touchstone functional audit (2026-08-23, demostaging1) found `PUT /` and
`PUT /AppData/` answering `500 Permission denied (os error 13)` while
`PUT /AppDataShared/` answered `201` — the app could not write at the very path it
opens on. The audit left the root cause unresolved because it could not inspect
host ownership. It is host-side: on a normally provisioned PCS both directories are
already owned by the server user —

    holyhorse  drwxr-xr-x pcs pcs /DATA    drwxr-xr-x pcs pcs /DATA/AppData
    wisera     drwxr-xr-x pcs pcs /DATA    drwxr-xr-x pcs pcs /DATA/AppData

— under which a container at `1000:1000` writes fine. The demo box's data root was
not.

Declaring them here would still be wrong, and deliberately is not done:

- **`/DATA`** is the platform's own root, not this app's. `folders` applies a `mode`
  as well as an owner, so declaring it would let one app re-permission the directory
  every other app's data sits under, on every `up`. Its ownership is the platform's
  guarantee to make, and Maison already makes it.
- **`/DATA/AppData`** is worse: chowning the parent of every other app's data
  directory is precisely the thing a broad-mount app should not do.

What is declared instead is the set of directories Dufs *exists* to write into —
`Documents`, `Downloads`, `Gallery`, `Media`. On a box where those are missing or
root-owned they are created and chowned to `$PUID:$PGID` before the container
starts, so upload, new-folder and WebDAV `PUT` work where a user actually works.
Writing a file directly at the root of the tree remains a host-permission question,
and is not something the PCS layout asks a user to do.

## Data protection
Access is gated by dufs's own HTTP authentication with a single `admin` account and
a server-specific password that the before-install tip tells the user to change; the
rule is `@/:rw`, so there is no anonymous read path and no second account to audit.
Dufs keeps no state of its own — there is no database, no config file and nothing
under `/DATA/AppData/dufs/`; everything it shows is the user's own files, which
survive uninstall and reinstall because they were never the app's to begin with.
Revoking access is therefore a matter of changing `$APP_DEFAULT_PASSWORD` and
restarting, or uninstalling the app, and costs no configuration either way.
