# Seafile Virtual Folder — Rationale

## What deviation / exception is being requested

1. The single container runs as `user: 0:0` with `privileged: true`, `SYS_ADMIN`,
   `/dev/fuse` and `apparmor:unconfined`.
2. It writes outside `/DATA/AppData/seafiledrive/` — it owns the mountpoint
   `/DATA/Seafile`, and everything that appears under it.
3. It ships no login gate of its own.

## Why it is necessary

**1 — FUSE.** A userspace filesystem whose mount must be visible to the host and to
other containers needs all four: the `mount` syscall (`SYS_ADMIN`), the FUSE device,
an AppArmor profile that does not block the mount, and `privileged` for the mount
propagation to travel back out through the `shared` bind. Dropping any one of them
leaves the mount confined to the container, where it is useless — the entire purpose
of the app is that other apps see the files.

**2 — the mountpoint is the product.** `/DATA/Seafile` is where a user-facing folder
belongs: browsable in the file manager, bindable by other apps, reachable over the
SMB share. Putting it under `AppData` would hide the one thing the app exists to
publish. What appears there is not app state — it is the user's own Seafile
libraries, and it lives in Seafile, not on this disk.

**3 — no listener to gate.** The container opens no port, joins no Caddy route group
and answers nothing from the network. Its only network activity is outbound, to
Seafile's WebDAV endpoint, where it authenticates with the credentials in
`config/rclone.conf`. There is no inbound surface for a login gate to sit in front
of; the gate that matters is Seafile's own, and it is enforced on every request this
app makes.

## Security mitigations in place

- **Files are not root-owned.** `--uid $PUID --gid $PGID` makes everything under
  `/DATA/Seafile` belong to the user, so nothing the mount publishes is writable only
  by root, and the privileged container is not a way to drop root-owned files into a
  user directory.
- **The mount is scoped to one Seafile account.** Seafile's WebDAV exposes exactly
  the libraries that account owns or has been given, so the folder can never show
  more than that user could see in the web UI. It is an authenticated view, not a
  bypass.
- **Credentials are never plaintext in the compose.** The WebDAV password is passed
  through `rclone obscure` by a one-shot `init` container and only the obscured form
  is written to `config/rclone.conf`, which is created `0644` under `$PUID:$PGID`
  inside AppData.
- **Memory is capped** at 512M (`cpu_shares: 30`), which a metadata-only mount stays
  well inside; a runaway transfer is bounded rather than able to squeeze the rest of
  the machine.
- **No published ports, no Caddy labels, no host paths besides the mountpoint and its
  own config directory.** `/DATA/Seafile` and the app's own
  `config` and `cache` directories are the complete list of what the container can
  touch on the host.

## Alternatives considered and rejected

- **Leave the mount inside the Seafile app** (where it lived until now). It made
  every Seafile install a privileged install, whether or not the user wanted a host
  folder, and tied the lifetime of the mount to an app people install for its web UI.
  Splitting it out makes the Seafile stack fully unprivileged and the FUSE privileges
  something a user opts into.
- **Use the generic Rclone app.** It can mount WebDAV, but its mounts are created
  through the web GUI at runtime rather than declared, so they do not survive a
  restart unattended, and it cannot know the Seafile URL or credentials — the
  zero-configuration first start is the entire value here.
- **Run rclone unprivileged with `--allow-other` alone.** Without `SYS_ADMIN` the
  mount syscall fails outright; with it but without shared propagation the mount is
  invisible outside the container.
- **Serve the libraries over WebDAV to each app instead of mounting.** Most apps
  cannot consume a WebDAV URL; a path is the only interface they all speak.

## Data protection

Nothing under `/DATA/Seafile` is stored by this app — it is a view. Seafile remains
the system of record: its versioning, snapshots, trash and sharing rules all still
apply to changes written through the folder, and uninstalling this app removes only
the view, never a byte of library data. The app's own state is one file,
`config/rclone.conf`, which is seeded once and then never rewritten, so an edited
remote survives restarts, updates and reinstalls.

With `--vfs-cache-mode off` (the default) nothing is cached on local disk at all;
raising the cache mode stores copies under `/DATA/AppData/seafiledrive/cache`, which
is the app's own directory and is removed with the app.
