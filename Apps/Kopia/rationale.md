# Kopia — Rationale

## What deviation / exception is being requested

Four, across `kopia-engine` and `kopia-app`:

1. Both run as `user: 0:0` (root) with `cap_drop: ALL` plus five file capabilities.
2. Both bind-mount the whole of `${DATA_ROOT:-/DATA}` (read-write, `rshared`).
3. `kopia-app` runs kopia's server **without a password of its own**.
4. The app declares `backup.skip: true`, so Maison never backs it up.

It is also the first store app that becomes a **Maison backup engine**, and the only
one meant for one kind of box: a self-hosted (FOSS mesh) server. A Yundera PCS ships
its own `kopia` stack under the same id, and Maison refuses to install this app over it.

## Why it is necessary

**Root and the whole of `/DATA`.** This is the engine Maison's backups run through.
It reads every app folder under `/DATA/AppData` and the user's Documents, Downloads
and Media, and restore writes them back. App data directories are routinely owned by
other uids with mode `0700` (a database writing as its own user), so a non-root engine
fails the backup of exactly the apps worth backing up — `permission denied` and an
aborted uninstall. Restore also has to `chown` files back to the uid they were taken
from, which only root can do. Docker has no ambient capabilities, so `user: 1000` plus
`cap_add` grants nothing; the choice is root or a backup that silently skips data.
This is the same profile the Yundera platform's own kopia stack runs with.

`kopia-app` is the same image over the same repository, browsing and restoring single
files, so it needs the same access.

**No password on the kopia server.** The app was written for a server that already
has one auth system. The AppShield gate is the only route to the UI; a second kopia
password would be a second credential store guarding the same thing.

**`backup.skip`.** The engine folder holds the repository configuration, its password
and its cache. A backup of those inside the repository they open is useless (reading
it needs the password already) and the cache is multi-gigabyte churn.

**An adapter for Maison.** The engine writes `engine/adapter.json`, which Maison
discovers. Maison does not use it until the admin clicks **Enable** in Settings ›
Backups, and refuses to enable it unless the descriptor names this app's own container
running this app's own image — so installing this app grants nothing the app did not
already have.

## Security mitigations in place

- **The gate is the only way in.** `kopia` (AppShield SSO) is the only service on
  `pcs` and the only one with Caddy labels. `kopia-app` and `kopia-engine` sit alone
  on `kopia-internal`, so no other app on the server can reach them.
- **`cap_drop: ALL`**, then back only `DAC_READ_SEARCH`, `DAC_OVERRIDE`, `CHOWN`,
  `FOWNER`, `FSETID`. No `SETUID`, no `SYS_ADMIN`, no network capabilities.
- **`no-new-privileges:true`** on both.
- **No Docker socket.** Maison execs into the engine; the engine never drives Docker.
- **Admin opt-in.** Maison ignores the engine until it is enabled in Settings, and
  binds that approval to the image the container actually runs.
- **The engine folder is `0700`.** It holds the repository password and the storage
  key. Example files ship as `*.example`; the real ones are written by the user.
- **Resource limits** on all three services (128M gate, 1G UI, 2G engine; `cpu_shares`
  40/50/30 — background tier for the engine).

## Alternatives considered and rejected

| Alternative | Why it was rejected |
|---|---|
| `user: $PUID:$PGID` | App folders owned by other uids at `0700` fail to back up, and restore cannot put ownership back. Verified: it aborts uninstall-with-backup. |
| `user: $PUID` + `cap_add: DAC_READ_SEARCH` | Does nothing. Docker has no ambient capabilities. |
| Mount only the user folders | Drops `/DATA/AppData`, i.e. every app — the main thing a backup is for. |
| Put `kopia-app` on `pcs` | Any other app could then reach a password-less kopia server over all of `/DATA`. |
| A Maison form for bucket and key | Would make Maison write storage credentials and name what it runs; the deployment rule is that the image is named by an installed app, never typed into a form. |
| Same app on a Yundera PCS | Its platform already deploys `kopia` with Yundera-issued storage; two stacks under one id would overwrite each other. |

## Data protection

- Backups are end-to-end encrypted with the repository password generated on the box.
  **The password is the only key**: Maison offers it on screen and by email, and the
  install tips say to save it off the server.
- The storage key lives in `engine/credentials.env`, inside the `0700` engine folder.
  It is read per invocation and blanked out of kopia's own config after connect.
- Uninstalling the app removes the engine's configuration with its folder; the backups
  stay in the bucket and are readable with the saved password. Maison warns before
  uninstalling an app that is a backup engine.
