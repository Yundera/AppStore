# CasaOS — Rationale

## What deviation / exception is being requested

Four deviations, all on the single `casaos` service, and they only make sense
together:

1. **Runs as root.** The service declares no `user:` and the image's config
   carries `User: null`, so the container runs as `0:0`.
2. **Mounts the whole of `/DATA` read-write**, not just
   `${DATA_ROOT:-/DATA}/AppData/casaos/`. That includes every user directory —
   `/DATA/Documents`, `/DATA/Downloads`, `/DATA/Media`, `/DATA/Gallery` — and
   every other app's data under `/DATA/AppData`.
3. **Uses `bind.propagation: rshared` on that mount**, so mounts made on either
   side become visible on the other.
4. **Mounts two paths outside `/DATA`**: `/var/run/docker.sock` (full control of
   the host Docker daemon) and `/dev` (the host device tree).

The net effect is deliberate and total: **this container can do anything on the
PCS that its owner could do as root.**

## Why it is necessary

CasaOS is not an application that happens to need a large mount — it *is* the
server's dashboard and app installer. Every one of the four items above is what
one of its three jobs requires:

- **Installing, starting, stopping and removing apps** is done by talking to the
  host Docker daemon. That is `/var/run/docker.sock`, and it is the app's entire
  reason to exist. A CasaOS with no socket can list nothing and install nothing.
- **Writing every other app's compose file and data directory.** App definitions
  live in `/DATA/AppData/casaos/`, but the directories CasaOS creates and chowns
  on an app's behalf are spread across the whole of `/DATA/AppData/`, and the
  media/document folders it offers apps as shared mounts are `/DATA/Media`,
  `/DATA/Documents`, `/DATA/Downloads` and `/DATA/Gallery`. It must be able to
  create them and set ownership to `$PUID:$PGID` before the app that needs them
  starts. Confined to its own AppData directory it can install an app but not
  give it anywhere to store data.
- **The file manager and storage manager.** The dashboard browses and edits the
  user's files directly, and lists, formats and mounts attached disks — hence
  `/dev`.
- **Root** follows from the above: `/var/run/docker.sock` is root-owned, the
  directories being chowned belong to other UIDs, and block-device operations
  are root-only. Running as `$PUID:$PGID` would leave the socket unreadable and
  every chown refused. It would also be security theatre — a container holding
  the Docker socket is root-equivalent on the host whatever UID it runs as.
- **`rshared` propagation** exists so FUSE filesystems mounted by an app (RClone
  remotes, MetaMesh's `meta-fuse`) become visible on the host and to the other
  containers that mount `/DATA`, instead of being trapped in this container's
  mount namespace. Without it a mounted remote appears as an empty directory
  everywhere except inside CasaOS.

## Security mitigations in place

- **Disclosed before install.** `x-casaos.tips.before_install` states that
  CasaOS manages Docker on the server and can therefore see and control every
  installed app, and that its data directory holds the definitions of every app
  on the machine.
- **No `privileged: true` and no `cap_add`.** The escalation is exactly the
  mounts listed above; the container gains no kernel capabilities beyond the
  Docker default set.
- **No published host ports.** `expose: 8080` only, on the shared
  `${APP_NET:-pcs}` network, so the dashboard is reachable solely through the
  gateway-terminated Caddy routes, over TLS.
- **Authentication is on by default and never hardcoded.** CasaOS serves its own
  login gate. On a machine that has run CasaOS before, the existing account in
  `/DATA/AppData/casaos` is reused; on a fresh one it presents first-run account
  setup before anything else is reachable. No credentials are baked into the
  compose file — the store injects `$APP_DEFAULT_PASSWORD`, generated per
  server, and the passwordless email sign-in option only appears when
  `USER_EMAIL`, `SMTP_HOST` and `SMTP_PORT` are all set.
- **Pinned image**, `ghcr.io/yundera/casa-img:0.4.15-47` — no `:latest`.
- **Resource limits**: `cpu_shares: 90`, `memory: 1G`, so a runaway install job
  cannot starve the rest of the PCS.
- **The SSO bridge is not part of this app.** `casaos-oidc-bridge` — which holds
  `BRIDGE_SECRET` from the PCS unified `.env` — stays in the platform
  infrastructure stack. Installing or removing CasaOS from the store cannot
  reach that secret or take every other app's login down with it.

### The Docker socket is the residual risk, and it is real

`/var/run/docker.sock` mounted read-write is equivalent to host root for
anything that achieves code execution in this container: it can start a
privileged container that mounts the host filesystem. Nothing in the compose
bounds that, and nothing can — it is the app's primary function. What bounds it
is the authenticated, gateway-only route in front of it and the owner's decision
to install a dashboard in the first place. Treat the CasaOS password as the root
password for the whole server, because that is what it is.

## Alternatives considered and rejected

- **Run as `$PUID:$PGID`.** Rejected: the Docker socket is root-owned, and the
  chowns CasaOS performs when provisioning another app's data directories are
  root-only operations. See also the security-theatre point above.
- **Mount only `${DATA_ROOT:-/DATA}/AppData/casaos/`.** Rejected: CasaOS could
  then write app definitions but not create or chown the data directories those
  apps mount, so every installed app would start with unwritable storage. It
  would also remove the file manager, which is a headline feature.
- **Mount `/DATA` read-only.** Rejected: provisioning an app's directory,
  chowning it, and editing a file from the file manager are all writes.
- **Replace the raw socket with a read-only Docker API proxy**
  (`tecnativa/docker-socket-proxy`). Rejected: unlike a monitoring app, CasaOS's
  whole job is *mutating* Docker — create, start, stop, remove. A read-only
  proxy disables the app.
- **Drop `/dev`.** Considered. It costs the storage manager (attached-disk
  listing, format, mount) and nothing else. Retained and disclosed rather than
  removed, because disk management is one of the three things users open the
  dashboard for.
- **Drop `rshared` and use the default `rprivate` propagation.** Rejected:
  FUSE mounts made inside the container would be invisible to the host and to
  every other container, which silently breaks the RClone and MetaMesh apps.
- **Front the dashboard with the AppShield OIDC sidecar.** Rejected: CasaOS
  serves its own `/login`, which is a path AppShield reserves, so the two cannot
  be stacked without disabling CasaOS's own account system — and that system is
  what owns the PCS user identity in the first place.

## Data protection

CasaOS's own state — the account, the app catalogue and every installed app's
compose definition — lives in `/DATA/AppData/casaos/` and survives
uninstall/reinstall. Uninstalling CasaOS leaves that directory in place and
removes nothing else; the apps it installed keep running.

Beyond that there is no technical boundary between this app and the rest of the
PCS, and there deliberately is not one: the protection is the login gate in
front of it, the absence of any published port, and the fact that the person
installing it is the machine's owner.

## Source repository

The image is built from <https://github.com/yundera/casa-img>, Yundera's fork of
IceWhale's CasaOS, and published as `ghcr.io/yundera/casa-img`.
