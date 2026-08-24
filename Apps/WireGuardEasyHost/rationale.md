# WireGuard Easy (Host Network) — Rationale

## What deviation / exception is being requested

Three, and they are linked:

1. The `wgeasyhost` service runs as **`user: "0:0"`**.
2. It runs with **`network_mode: host`** — no network namespace of its own.
3. It adds **`NET_ADMIN`** and **`SYS_MODULE`**.

| Capability | Why it is added |
| --- | --- |
| `NET_ADMIN` | Create and configure the `wg0` interface and program WireGuard's cryptokey routing. Because the container shares the host namespace, this interface is created **on the host**. |
| `SYS_MODULE` | Load the `wireguard` kernel module on hosts where it is available but not resident. |

The `wgeasyhost-proxy` sidecar also runs as `user: "0:0"`, for an unrelated reason
documented inline in the compose file: the CasaOS installer injects `user: $PUID:$PGID`
into any service without an explicit `user:`, and the `nginx` master process cannot
create `/var/cache/nginx` as a non-root UID. Declaring `0:0` prevents that injection.

This is the most privileged combination in this app's family, and it is deliberate.
It is a separate store listing from `WireGuardEasy` precisely so that a user picks it
knowingly rather than inheriting it.

## Why it is necessary

- **Host networking is the entire point of this listing.** In bridge mode the VPN
  terminates inside the container's namespace, so clients reach the container and
  nothing else. Here `wg0` lives on the host, which means the VPN server address
  `10.9.0.1` **is** the host — so a connected client can reach host-bound services
  (Samba on `:445`, Guacamole, anything else the user runs) at that address. That is
  the capability the app exists to provide, and there is no way to get it from inside
  a namespace.
- **`NET_ADMIN` is unavoidable** for the same reason as the bridge-mode app: WireGuard
  is kernel-space and the container must create and program the interface.
- **`SYS_MODULE` covers hosts that have not loaded the module.** Same reasoning as the
  sibling app.
- **The sysctls cannot be set on the container.** `net.ipv4.ip_forward` and
  `net.ipv4.conf.all.src_valid_mark` are namespaced settings, and a host-mode container
  shares the host's namespace — Docker therefore refuses a `sysctls:` block here, since
  it would be mutating the host. They are set on the host by `pre-install-cmd` instead.
- **A host-mode container cannot be a Caddy upstream**, which is why the web UI is not
  served directly. `wgeasyhost` binds the UI on host port `51821`, and the bridged
  `wgeasyhost-proxy` sidecar on the `pcs` network carries the gateway labels and
  forwards to it via `host.docker.internal`.

## Security mitigations in place

- **Authentication is on by default.** `INIT_ENABLED: 'true'` with
  `INIT_USERNAME: admin` and `INIT_PASSWORD: $APP_DEFAULT_PASSWORD` provisions the admin
  account at first boot, so the app is never published in its unauthenticated first-run
  wizard state. The credentials appear in `tips.before_install`.
- **The default tunnel is split, not a catch-all.** `INIT_ALLOWED_IPS: '10.9.0.0/24'`
  seeds new clients with the VPN subnet only — not `0.0.0.0/0`. A connected client
  reaches host services and other peers; its normal internet traffic stays direct and
  is not routed through, or visible to, the PCS.
- **The VPN subnet is deliberately separated.** `10.9.0.0/24` avoids colliding with the
  bridge-mode `WireGuardEasy` app on `10.8.0.0/24`, so both can be installed without
  one silently breaking the other's routing.
- **Blast radius on disk is one directory.** The only bind mount is
  `${DATA_ROOT:-/DATA}/AppData/wgeasyhost/wireguard`, declared in
  `x-compose-app.folders` so Maison creates and chowns it. No user directory is mounted.
- **Resource limits are enforced** on both services (`256m` / `cpu_shares: 50` for the
  VPN, `64m` / `cpu_shares: 80` for the proxy).
- **The proxy image is pinned** to `nginx:1.29.3-alpine`, and its config is bind-mounted
  read-only.
- **Host port exposure is disclosed before install.** `tips.before_install` tells the
  user that UDP `51820` must be open on their firewall and that the management UI also
  binds host port `51821` over plain HTTP, with the advice to reach it through the
  HTTPS gateway link and firewall `51821` otherwise.

## Alternatives considered and rejected

1. **Bridge networking (i.e. just install `WireGuardEasy`)** — rejected *for this
   listing*: it is the safer default and it is shipped, as a separate app. It cannot
   give clients access to host-bound services, which is the only reason this variant
   exists. Users who do not need that should install the bridge-mode app.
2. **Host mode without `SYS_MODULE`** — works wherever the kernel already has WireGuard
   loaded, and fails opaquely where it does not. Operators who know their kernel can
   remove it from the compose after install.
3. **Publishing the UI directly from the host-mode container** — rejected: it would put
   the management interface on a host port with no TLS and no gateway auth in front of
   it. The bridged proxy sidecar exists so the UI is reached only through the Yundera
   gateway.
4. **Running the proxy as `$PUID:$PGID`** — rejected: `nginx:alpine`'s master process
   fails to create `/var/cache/nginx` and the container will not start. The sidecar
   holds no capabilities, no host network and no user data, so root there is the
   narrowest of the three exceptions in this file.
5. **A `0.0.0.0/0` default for `INIT_ALLOWED_IPS`** — rejected: it would turn every new
   client into a full-tunnel VPN by default, routing all of a user's traffic through
   their PCS without them having asked for it.

## Data protection

- All app state — server keypair, peer configs, the wg-easy database — lives under
  `/DATA/AppData/wgeasyhost/wireguard` and survives uninstall / reinstall and upgrades.
- Private keys never leave the PCS; client configs are generated server-side and handed
  over the authenticated HTTPS UI.
- The app mounts no user directory and stores no user documents, so removing it removes
  nothing the user put on the machine.
- Because the tunnel is split by default, the app is not in the path of the user's
  general internet traffic and has no opportunity to observe it.
