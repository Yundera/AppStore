# Tailscale — Rationale

## What deviation / exception is being requested

Four linked deviations, all on the single `tailscale` service:

1. **`user: 0:0`** — the container runs as root instead of `$PUID:$PGID`.
2. **`network_mode: host`** — the container shares the host network namespace
   instead of joining a bridge network with `expose:`.
3. **`cap_add: [NET_ADMIN, SYS_MODULE]`** — two extra Linux capabilities on top of
   the default set.
4. **A device bind of `/dev/net/tun`** — a host path outside `/DATA`.

Taken together these give the container effective control of the host's network
stack, and `SYS_MODULE` in particular lets it load kernel modules into the host
kernel. This is a genuine privilege escalation and is stated here plainly rather
than framed as "privileged networking".

## Why it is necessary

- **`user: 0:0` + `NET_ADMIN`** — `tailscaled` creates the `tailscale0` TUN
  interface, installs routes and policy-routing rules, and programs `iptables`/`nftables`
  chains for the tailnet. All of that requires `CAP_NET_ADMIN`, and the upstream
  `ghcr.io/tailscale/tailscale` entrypoint (`containerboot`) assumes uid 0 for its
  state and socket paths. A non-root uid cannot create a TUN device or touch the
  routing table, and the daemon exits at startup.
- **`network_mode: host`** — the point of this app is to put *the PCS itself* on the
  tailnet: reaching the host's own services over their host ports, advertising the
  LAN as a subnet route, and optionally acting as an exit node. All three require the
  daemon to live in the host network namespace and to see the host's real interfaces.
  In a bridge namespace the tunnel would only serve the container.
- **`/dev/net/tun`** — the kernel TUN device node. Kernel-mode networking (the
  default here, `TS_USERSPACE=false`) needs it to open the tunnel interface.
- **`SYS_MODULE`** — `tailscaled` loads the `tun` kernel module when it is not
  already present. This mirrors Tailscale's own published `docker-compose` example.
  On a host where `tun` is already loaded the capability is not exercised; it is kept
  so the app works on PCS images that do not preload it. It is the single most
  powerful item in this list — see *Alternatives* below.

## Security mitigations in place

- **No listening port is published and there is no local web UI.** The compose
  declares no `ports:` and no Caddy labels; the app is administered from Tailscale's
  own console (`login.tailscale.com`), which is authenticated by Tailscale, and by
  the `TS_AUTHKEY` the user pastes into the app's settings.
- **Traffic is end-to-end encrypted** by WireGuard between tailnet nodes; the daemon
  holds only this node's private key, which never leaves the machine.
- **The node cannot join a tailnet on its own.** `TS_AUTHKEY` ships empty, so a
  freshly installed container has no credentials and no connectivity until the user
  supplies a key from their own tailnet (or their own Headscale server).
- **Only one host path outside AppData is mounted**, `/dev/net/tun`, and it is the
  device the daemon needs. No user directory (`/DATA/Documents`, `/DATA/Downloads`,
  `/DATA/Media`, `/DATA/Gallery`) and no part of the host filesystem is bound in.
- **The image tag is pinned** (`ghcr.io/tailscale/tailscale:v1.94.2`) to the upstream
  official image, so the privileged surface is a reviewed, reproducible artifact.
- **No install hook.** The app makes no host changes at install time; its one state
  directory is declared under `x-compose-app.folders` and created by Maison.
- **`cpu_shares: 70`** keeps the daemon from starving other apps under contention.

## Alternatives considered and rejected

1. **`user: $PUID:$PGID`** — rejected: an unprivileged uid cannot create a TUN
   interface or modify the routing table; `containerboot` fails at startup.
2. **Userspace networking (`TS_USERSPACE=true`, no TUN device, no `SYS_MODULE`)** —
   rejected as the default: userspace mode gives outbound connectivity through a
   SOCKS5/HTTP proxy only. It cannot expose the host's existing services on the
   tailnet, cannot advertise subnet routes, cannot act as an exit node, and costs a
   large fraction of throughput. Those capabilities are the reason to install this
   app. Users who only need outbound access can set `TS_USERSPACE=true` in the app
   settings and the extra privileges go unused.
3. **Bridge network with `expose:`** — rejected: the tunnel would then terminate in
   the container's own namespace, so nothing on the PCS or the LAN would be reachable
   over the tailnet.
4. **Dropping `SYS_MODULE`** — viable on any host that already has the `tun` module
   loaded, and it is the one capability here that could be removed without changing
   what the app does on such a host. It is retained for first-boot reliability across
   PCS images; a deployment that can guarantee `tun` is preloaded should remove it.
5. **Managing a host-installed `tailscaled` instead of a container** — rejected:
   app install hooks run inside the Maison container and cannot manage host services,
   and a host package would be outside the app lifecycle entirely. If the host already
   runs its own Tailscale daemon the user is told, in `tips.before_install`, to stop
   it before installing — two daemons cannot share `tailscale0`.

## Data protection

- All persistent state — the node key, tailnet identity and preferences — lives in
  `/DATA/AppData/tailscale/state/`, declared in `x-compose-app.folders`, so Maison
  creates and chowns it before first start and it survives uninstall / reinstall and
  upgrades: the node rejoins the tailnet with the same identity instead of appearing
  as a duplicate device.
- The container reads no user data. It carries packets; it never opens
  `/DATA/Documents`, `/DATA/Downloads`, `/DATA/Media` or `/DATA/Gallery`, none of
  which are mounted.
- The auth key is supplied by the user through the app settings and is stored in the
  app's own compose environment on the PCS; it is never baked into the store entry.
- Revocation is out-of-band and immediate: removing the node from the Tailscale (or
  Headscale) admin console cuts it off regardless of what the container does.
