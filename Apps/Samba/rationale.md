# Samba — Rationale

## What deviation / exception is being requested

Three related exceptions, all in the single `samba` service:

1. **Runs as `user: 0:0` (root).**
2. **Adds the `SYS_ADMIN` capability and passes through `/dev/fuse`**, with the
   `/storage` bind mounted `rslave` so mounts made on the host propagate into the
   container.
3. **Bind-mounts `${DATA_ROOT:-/DATA}` itself, read-write**, onto `/storage` —
   the whole data root rather than only `/DATA/AppData/samba/`. That includes
   `/DATA/Documents`, `/DATA/Downloads`, `/DATA/Media`, `/DATA/Gallery` **and**
   `/DATA/AppData`, which holds every other installed app's data.

## Why it is necessary

**The broad mount is the app.** Samba exists so the owner can mount their server's
storage as a network drive from Windows Explorer, macOS Finder, a Linux file
manager, a phone or a smart TV — the same job Dufs does over WebDAV and
FileBrowser does over HTTP. Narrowing the share to `/DATA/AppData/samba/` would
produce a network drive containing nothing but the app's own empty directory: a
user could not move a download into Media, could not reach files another app
wrote, and could not use the drive to inspect or repair an app's data directory.
The single share is named `DATA` and is disclosed before install.

**Root is required by the SMB server itself.** `smbd` binds TCP/445, a privileged
port, and it must be able to serve files owned by any uid in the mounted tree
while presenting a single `admin` SMB account. A container dropped to
`$PUID:$PGID` cannot bind 445 and cannot read the root-owned parts of
`/DATA/AppData` that the share is meant to expose. The image reads `UID`/`GID`
(set to `$PUID`/`$PGID`) and creates files it writes with the server user's
ownership, so user-visible files stay owned by `pcs:pcs` and remain editable
outside the app despite the container itself starting as root.

**`SYS_ADMIN` + `/dev/fuse` + `rslave` are for FUSE mounts.** Several PCS apps
present storage through FUSE (rclone remotes, the MetaMesh VFS, encrypted
overlays). Without `rslave` propagation the container sees the empty directory
that existed before the host mounted anything there, and a FUSE mount performed
inside the container needs `/dev/fuse` and `SYS_ADMIN`. Without them Samba
silently serves stale, empty directories for exactly the mount points a user is
most likely to want on a network drive.

## Security mitigations in place

- **Authentication is on by default and cannot be bypassed.** The share is created
  with `USER: admin` / `PASS: $APP_DEFAULT_PASSWORD` — the per-server generated
  password, never a hardcoded one. There is no guest or anonymous share; an
  unauthenticated SMB session is rejected by `smbd`.
- **The mount is disclosed before install**, in the app `description` and in
  `x-casaos.tips.before_install`, so the user sees the extent of the access on the
  install screen rather than after installing.
- **Only the SMB port is published.** `445/tcp` is the sole `ports:` entry and is
  not HTTP, so it cannot pass through Caddy; no web UI, admin panel or second
  door is published. The app carries the reserved `needs-public-ip` tag so a user
  on a CGNAT or mesh-routed PCS knows before installing that the port may not be
  reachable from outside.
- **The published port can be narrowed to one address.** The binding is written
  `0.0.0.0:445:445` precisely so the user can change the host side to a single
  interface — the before-install tip documents binding it to the Tailscale address
  so the share is reachable over the VPN only.
- **The container is not `privileged`.** It takes exactly one capability
  (`SYS_ADMIN`) and one device (`/dev/fuse`); no `--privileged`, no host PID or
  network namespace, no Docker socket.
- Resource limits (`cpu_shares: 50`, `memory: 256M`) bound the container.
- The image is pinned to a specific upstream release (`dockurr/samba:4.23.10`),
  never `:latest`.

## Alternatives considered and rejected

- **Run as `$PUID:$PGID`.** Rejected: `smbd` cannot bind privileged port 445 as an
  unprivileged uid, and the share would lose read access to the root-owned parts
  of `/DATA/AppData` that make the drive useful for inspection and recovery.
- **Share only `/DATA/Documents`, `/DATA/Downloads`, `/DATA/Media`,
  `/DATA/Gallery`.** Rejected: it splits one network drive into four, so a drag
  between them becomes a copy across mount points instead of a rename, and it
  removes the inspection/recovery use case entirely.
- **Mount `/DATA` read-only.** Rejected: writing to the share is the point of a
  network drive; a read-only Samba is a viewer, and the tips explicitly document
  copying files onto the share.
- **Exclude `/DATA/AppData` with a narrower set of binds.** Rejected: Docker has no
  exclude primitive, so this means enumerating every sibling directory, and the
  list goes stale the moment the user creates a new top-level folder.
- **Drop `SYS_ADMIN` / `/dev/fuse` / `rslave`.** Rejected: it is the difference
  between a network drive that shows the user's real storage and one that serves
  stale empty directories wherever a FUSE-backed app has mounted something. This
  is the exception most worth revisiting if the platform ever exposes FUSE mounts
  through a mechanism that does not need the capability.
- **Front it with AppShield / OIDC.** Not applicable: AppShield is an HTTP
  reverse proxy and SMB is not HTTP. The authentication requirement is met by
  Samba's own account gate instead, which CONTRIBUTING lists as an acceptable
  alternative.

## Data protection

The app stores no state of its own — there is no database and nothing under
`/DATA/AppData/samba/`; everything it serves is the user's own files, which
survive uninstall and reinstall because they were never the app's to begin with.
Nothing in the container's startup erases or rewrites the mounted tree: the image
only exports the existing directory as a share. Files written over SMB are created
as `UID:GID` = `$PUID:$PGID`, so they stay owned by the server user and remain
readable and editable by every other app and by the user over SSH. Revoking
access is a matter of changing `$APP_DEFAULT_PASSWORD` and restarting, or
uninstalling the app — neither costs any configuration.
