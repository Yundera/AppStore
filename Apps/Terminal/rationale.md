# Terminal — Rationale

## What deviation / exception is being requested

Four deviations, and they only make sense together:

1. **`terminal-ttyd` runs as `user: root`** — the shell it hands the user is a
   root shell.
2. **`terminal-ttyd` bind-mounts the host root `/` at `/host`, read-write** —
   not a subdirectory of `/DATA/AppData/terminal/`, and not under `/DATA` at
   all. The `${DATA_ROOT:-/DATA}` prefix does not apply because the target is
   the host filesystem itself.
3. **The mount subsumes the whole of `/DATA`** — `/DATA/Documents`,
   `/DATA/Downloads`, `/DATA/Media`, `/DATA/Gallery` and every other app's data
   under `/DATA/AppData` are reachable read-write through `/host/DATA`.
4. **`terminal-ttyd` runs `privileged: true` with `cap_add: [SYS_ADMIN,
   NET_ADMIN]`** — needed so that administration inside the chroot behaves like
   administration on the host.

The command is literally `ttyd --writable ... chroot /host bash`. The net effect
is deliberate and total: **this app can do anything on the PCS that its owner
could do over SSH as root.**

## Why it is necessary

The app exists to be the owner's shell on their own PCS. The tasks it is
installed for — inspect why a container will not start, edit a compose file or
a system config, fix permissions on a user directory, recover a broken app's
data, run a package update — are precisely the tasks that require a root
filesystem view and host-level privilege. A terminal confined to its own
AppData directory can administer nothing; it is a shell in an empty box.

- **`user: root` and the host-root bind** are what make it a *host* shell rather
  than a shell inside a scratch container. Without them the session survives
  nothing: the container's own filesystem is discarded on every restart.
- **`privileged` + `SYS_ADMIN`** are what make `mount`, loop devices, `dmesg`,
  filesystem repair and `nsenter`-style work behave inside the chroot.
  `NET_ADMIN` is there for `ip`, `iptables` and interface debugging, which is a
  routine reason to open a terminal on a home server.

## Security mitigations in place

- **Authentication is on by default and is the PCS's own.** The published
  service is the AppShield sidecar (`ghcr.io/yundera/appshield:2.0.6`), which
  self-registers with the PCS OIDC provider (`auth-registrar`) and refuses every
  request that does not carry a valid Yundera session. There is no app-local
  password to leak or forget to change, and no unauthenticated path to the
  shell.
- **The shell is never published directly.** `terminal-ttyd` has no `ports:`, no
  `expose:` and is not on the `pcs` network — it sits on the app-private
  `terminal-internal` bridge and is reachable only from the sidecar. Only the
  sidecar carries the `caddy_0/1/2` labels, so port 7681 is unroutable from
  outside the app.
- **The privilege is confined to the one service that needs it.** The
  internet-facing sidecar is an ordinary unprivileged reverse proxy: it has no
  `privileged`, no `cap_add` and no volumes. An attacker has to get through
  OIDC before privilege is on the table at all.
- **Disclosed before install.** `x-casaos.description` and
  `x-casaos.tips.before_install` both state that this is a root shell, that the
  host root is mounted read-write, that all of `/DATA` and every other app's
  data is reachable, and that access should be treated as equivalent to root
  SSH.
- **Pinned images**, `ghcr.io/yundera/appshield:2.0.6` and `tsl0922/ttyd:1.7.7`
  — no `:latest`.
- **Resource limits**: `cpu_shares: 80` on the sidecar, `cpu_shares: 70` on the
  shell.
- **Terminal-side features that widen the attack surface are off**: `enableSixel`
  and `enableTrzsz` are disabled; only Zmodem transfer is left on.
- **No host provisioning.** The app ships no `pre-install-cmd`: it creates no
  host account, adds no sudo rule and installs no key material. Uninstalling it
  leaves nothing behind on the host.

## Alternatives considered and rejected

- **Mount only `/DATA/AppData/terminal/`.** Rejected: it removes every reason to
  install the app. The recovery and inspection use cases *are* the product.
- **Mount `/` read-only.** Rejected: editing a config file, fixing an ownership
  mistake or clearing a full disk are all writes.
- **Mount `/DATA` instead of `/`.** Rejected: it still exposes all user data
  (so the disclosure obligation is unchanged) while removing the ability to
  touch `/etc`, `/var/log` and the compose stack under
  `/DATA/AppData/casaos/apps/` — i.e. it keeps the risk and drops the benefit.
- **Drop `privileged` and keep only `SYS_ADMIN`/`NET_ADMIN`.** Rejected for the
  shell service: device nodes and mount operations inside the chroot need the
  full privileged set, and a terminal that fails halfway through a repair is
  worse than no terminal. It *was* dropped from the sidecar, which never needed
  it.
- **Front it with an app-local password instead of the PCS SSO.** Rejected:
  ttyd's own basic-auth is a single shared credential with no session
  management, and AppShield gives the same identity the rest of the PCS uses.
- **Ship no terminal app at all and tell users to SSH.** Rejected: SSH into a
  Yundera PCS requires key material and a reachable port, which is exactly what
  a user locked out of their own server does not have. A browser shell behind
  the PCS login is the recovery path.

## Data protection

The app stores nothing of its own — there is no AppData directory to preserve,
so uninstall/reinstall is lossless by construction.

Beyond that, there is no technical boundary between this app and the rest of the
PCS: the protection is the SSO gate in front of it and the owner's decision to
install it. Practically:

- Treat access to this app as equivalent to root SSH access to the server.
  Anyone who can log into your Yundera account can read and change every file
  on it.
- Install it only on a PCS you administer yourself, and uninstall it when you
  are done with the task you installed it for.
- If what you need is to browse, upload or edit files, install **FileBrowser**
  instead — same job, confined to the directories you point it at.
