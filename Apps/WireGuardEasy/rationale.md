# WireGuard Easy — Rationale

## What deviation / exception is being requested

The `wgeasy` service runs as **`user: "0:0"`** and adds two Linux capabilities:

| Capability | Why it is added |
| --- | --- |
| `NET_ADMIN` | Create and configure the `wg0` interface, set addresses and routes, and program the WireGuard cryptokey routing table inside the container's network namespace. |
| `SYS_MODULE` | Load the `wireguard` kernel module when the host kernel does not already have it (kernels < 5.6, or a host where the module is built but not auto-loaded). |

It also sets two container-scoped `sysctls` — `net.ipv4.ip_forward=1` and
`net.ipv4.conf.all.src_valid_mark=1` — and publishes **UDP 51820** with a
`ports:` entry rather than `expose:`.

`SYS_MODULE` is the significant one: it lets a root container load code into the
**host** kernel, so it is documented here explicitly rather than left to be
inferred from the compose file.

## Why it is necessary

- **WireGuard is a kernel-space VPN.** `wg-easy` does not implement the data path
  itself; it drives `wg`/`wg-quick`, which need `NET_ADMIN` to create the interface
  and install peer routes. Without it the container starts and the UI renders, but
  no tunnel can ever be established.
- **`SYS_MODULE` covers hosts where the module is not already resident.** Yundera
  PCS instances are provisioned across a range of kernels and images; on a host that
  has `wireguard.ko` available but not loaded, the container is the only thing that
  knows it needs it. This is the same pair the store's `Tailscale` app carries for
  the same reason.
- **`ip_forward` is required to route between peers.** Without it, clients can reach
  the server but not each other, which silently breaks the common "connect two of my
  devices" case. `src_valid_mark` is wg-quick's standard companion setting for
  reverse-path filtering.
- **UDP 51820 must be a real published port.** WireGuard clients dial it directly
  from the internet; it is not HTTP and cannot be routed through the Caddy gateway,
  so `expose:` would make the VPN unreachable. The app carries the reserved
  `needs-public-ip` handling for this reason.

## Security mitigations in place

- **Authentication is on by default.** `INIT_ENABLED: 'true'` with
  `INIT_USERNAME: admin` and `INIT_PASSWORD: $APP_DEFAULT_PASSWORD` provisions the
  admin account at first boot, so the app is never published in its unauthenticated
  first-run setup state. The credentials are surfaced in `tips.before_install` in all
  five supported locales.
- **The sysctls are container-scoped.** They are declared under the service's
  `sysctls:` key, which the kernel applies inside the container's own network
  namespace. This app does **not** run with `network_mode: host`, so they do not
  mutate the host's networking. (The host-network variant of this app is a separate
  listing, `WireGuardEasyHost`, with its own rationale.)
- **Blast radius on disk is one directory.** The only bind mount is
  `${DATA_ROOT:-/DATA}/AppData/$AppID/wireguard`. No user directory — `/DATA/Documents`,
  `/DATA/Downloads`, `/DATA/Media` — is mounted, so root inside the container cannot
  reach user files.
- **The web UI is not host-bound.** Port 80 is `expose:`d only and reached through the
  shared `pcs` network with TLS terminated at the Yundera gateway; `INSECURE: 'true'`
  refers to the app serving plain HTTP behind that gateway, not to a disabled auth gate.
- **IPv6 is disabled** (`DISABLE_IPV6: 'true'`), removing a second address family from
  the exposed surface.
- **CPU weight is capped** (`cpu_shares: 50`) so a saturated VPN cannot starve the rest
  of the PCS.

## Alternatives considered and rejected

1. **Run as `$PUID:$PGID` without capabilities** — rejected: `wg-quick` cannot create
   `wg0` or write the interface config, and the container exits during startup. There
   is no userspace fallback in this image.
2. **`NET_ADMIN` alone, dropping `SYS_MODULE`** — rejected as the default: it works on
   any host whose kernel already has WireGuard loaded, but fails opaquely on hosts
   where it does not, presenting as "the VPN just doesn't connect" with nothing useful
   in the app's own logs. Operators who know their kernel ships WireGuard in-tree can
   safely remove `SYS_MODULE` from the compose after install.
3. **A userspace implementation (`boringtun`/`wireguard-go`)** — rejected: it removes
   `SYS_MODULE` but not `NET_ADMIN`, costs a significant throughput penalty, and is not
   what `ghcr.io/wg-easy/wg-easy` ships.
4. **Routing the VPN through the Caddy gateway instead of publishing UDP 51820** —
   rejected: the gateway terminates TLS for HTTP(S); it has no path for the raw UDP
   WireGuard protocol.

## Data protection

- All app state — the server keypair, peer configs and the wg-easy database — lives in
  `${DATA_ROOT:-/DATA}/AppData/$AppID/wireguard` and survives uninstall / reinstall
  and image upgrades.
- Private keys never leave the PCS. Client configurations are generated on the server
  and handed to the user over the authenticated HTTPS UI (file download or QR code);
  the app makes no outbound calls to any WireGuard-related service.
- The app stores no user documents and mounts no user directory, so removing it removes
  nothing the user put on the machine.
