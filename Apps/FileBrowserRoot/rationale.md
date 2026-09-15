# FileBrowser (root) — Rationale

## What deviation / exception is being requested
Four, all in the same direction:

1. The backend bind-mounts the **Docker host's entire filesystem** (`/`) read-write onto
   `/srv/`, the app's browsing root. That is `/DATA` *and* `/etc`, `/var`, `/home`,
   `/root`, `/boot`, `/opt`, `/usr` and every mount nested under them.
2. The backend runs as **`user: 0:0`**, not `$PUID:$PGID`, so file permissions do not
   constrain what it reads or writes, and everything it creates is owned by root.
3. The backend's own authentication is **disabled** (`--auth.method=noauth`), with the
   AppShield SSO gate in front of it as the only authentication.
4. `ALLOWED_PATHS` exempts three prefixes (`share/`, `api/public/`, `static/`) from that
   gate so share links keep working.

(3) and (4) are inherited verbatim from `Apps/FileBrowser` and are justified there for the
same reasons; this document concentrates on (1) and (2), which are what make this a
separate app.

## Why it is necessary

### It is the entire app
`Apps/FileBrowser` already exists and already covers the user-data case: it mounts
`/DATA` and runs as `$PUID:$PGID`. This app is deliberately the other one — the
administrator's file manager, the same relationship `Apps/ClaudeCodeRoot` has to
`Apps/ClaudeCode`. Remove the host mount or the root user and nothing is left that the
standard app does not already do, so there is no narrower version of this app to ship:
the deviation *is* the product.

The jobs it exists for all live outside `/DATA` or outside the server user's permissions:

- editing a configuration file an app will not start without (`/DATA/AppData/<app>/…`
  written by a root container, `/etc/…` for anything host-side);
- recovering a file from another app's data directory when that directory is root-owned;
- reading a log under `/var/log` after a failure;
- placing a file where only root can write;
- inspecting the CasaOS stack itself under `/DATA/AppData/casaos/apps/yundera/`.

Each is a task the owner would otherwise do over SSH. The point of the app is to make it
possible from a browser, on a machine where the owner may not have a shell to hand.

### Why root and not `$PUID:$PGID`
The mount alone is not enough. Most of what makes this app useful — app data written by
root containers, `/etc`, `/var/log`, `/root` — is unreadable or unwritable as UID 1000.
Running as `$PUID:$PGID` would produce a file manager that lists the whole filesystem and
then refuses on the half of it that matters, which is worse than not shipping it.

## Security mitigations in place
- **Authentication is the PCS's own SSO and it is not optional.** The AppShield sidecar
  self-registers with `auth-registrar` and gates every request through Dex, which is
  owner-only. There is no anonymous access and no app-specific password to leak or leave
  at its default.
- **The unauthenticated backend is not reachable.** `filebrowserroot-backend` carries no
  Caddy labels and is **not** on the `pcs` network — only on the app-private
  `filebrowserroot-internal` network, whose only other member is the gate. This matters
  more here than in the standard app: on `pcs`, any other container on the server could
  otherwise have reached an unauthenticated, root-privileged file manager over the whole
  host filesystem. It is the load-bearing mitigation.
- **Disclosed before install**, in `x-casaos.tips.before_install` (English, Korean,
  Chinese, French, Spanish) and again in the store description in the same five
  languages, including that it can leave the machine unbootable and that files it creates
  are root-owned. The `root` chip on the icon carries the same warning into the app grid
  and the tile.
- **Separate app, separate install decision.** Nobody gets host-wide root access by
  updating the file manager they already had; they get it by choosing to install a second
  app that says what it is in its name, icon and listing.
- **No host port is published** by either service, and no Docker socket is mounted — this
  app can write host files, but it cannot start containers.
- Resource limits bound both containers (gate `cpu_shares: 80` / `128M`, backend
  `cpu_shares: 50` / `256M`).
- Only the app's own database directory (`/DATA/AppData/$AppID/db`) is declared in
  `x-compose-app.folders`, and the init containers that seed it still run as
  `$PUID:$PGID`, so the app folder stays owner-editable.

## Residual risk that is accepted, not mitigated
- **The owner can destroy the server with it.** `rm` on `/etc`, `/boot` or `/var/lib`
  from this app is exactly as effective as it would be from a root shell. There is no
  undo and no protected-path list. This is inherent to the app and is stated on the
  install screen.
- **Files it creates are owned by root**, including files created in `/DATA/Documents`
  and friends. Another app running as `$PUID:$PGID` may then be unable to modify them.
  The standard FileBrowser app is the right tool for user data precisely because it does
  not have this problem.
- **A share link can point at any file on the machine**, `/etc/shadow` included. The gate
  exemption that keeps share links working cannot distinguish a shared holiday photo from
  a shared private key; only the owner choosing what to share can.
- **`/proc`, `/sys` and `/dev` are visible**, because Docker bind mounts are recursive.
  Browsing them is harmless; a search started from `/` walks them and is slow.

## Alternatives considered and rejected
- **Extend `Apps/FileBrowser` instead of adding an app.** Rejected: it would silently
  turn an existing, deliberately scoped app on every server that has it into a
  host-wide root tool, with no install-time decision from the owner.
- **Mount `/` read-only.** Rejected: repairing a config file and dropping a file where
  only root can write are the two things it is installed for; read-only leaves an
  inspector, and `Apps/FileBrowser` plus a shell already covers inspection.
- **Enumerate host directories (`/etc`, `/var`, `/home`, …) instead of `/`.** Rejected:
  Docker has no exclude primitive, the list goes stale the moment the host grows a new
  top-level directory or mount, and each entry becomes its own root in the UI, so moving
  a file between two of them is a cross-device copy.
- **Run as root but drop capabilities (`cap_drop`, `no-new-privileges`).** Rejected as
  security theatre here: no capability governs "write any file" once every file is
  mounted and the process is UID 0 — `DAC_OVERRIDE` is what does, and dropping it would
  disable the app.
- **Mount the Docker socket too, for full host control.** Rejected: out of scope for a
  file manager, and `Apps/ClaudeCodeRoot` already covers host administration for anyone
  who needs it.
- **Keep FileBrowser's own password login as a second factor.** Rejected for the same
  reason as in `Apps/FileBrowser`: AppShield reserves `/login`, so a backend that 302s to
  its own `/login` is unusable behind the gate.

## Data protection
Access is gated by the PCS's own SSO (AppShield → Dex), which is owner-only, so revoking
access is a matter of the server account, not of an app-local credential. The app's own
state — its database of settings and shares — lives in `/DATA/AppData/$AppID/db/` and
survives uninstall/reinstall; share links the owner created are listed and revocable from
the app's Shares screen. Nothing this app reads leaves the server: there is no telemetry,
no outbound sync and no third-party dependency at runtime.

## Upstream status
`filebrowser/filebrowser` is archived as of 2026-09-01. This app is pinned to `v2.63.23`,
the final release, and will receive no further upstream fixes, including security fixes —
the same position `Apps/FileBrowser` is in, and the reason `Apps/FileBrowserQuantum`
exists as a maintained successor to evaluate. That matters more for a root-privileged app
than for a scoped one: a remotely exploitable bug in the backend would be exploitable
against the whole host. The compensating control is that the backend is unreachable
except through the SSO gate, so the only party who can reach it is the owner.
