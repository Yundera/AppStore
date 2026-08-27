# MetaWatch — Rationale

## What deviation / exception is being requested

1. **Three services run as `user: 0:0` (root):** `metawatch-core`,
   `metawatch-search` and `metawatch-share`. The user-facing service
   (`metawatch-app`) and the AppShield gate do **not**.
2. **Two non-HTTP host ports are published:** TCP `4003` and `4004`.
3. **Two services sit on the shared `pcs` network without Caddy labels:**
   `metawatch-search` and `metawatch-share`.
4. **The app fetches and re-shares third-party content** from a public
   peer-to-peer network.

No volume reaches outside `/DATA/AppData/$AppID/`. The app mounts none of
`/DATA/Documents`, `/DATA/Downloads`, `/DATA/Media` or `/DATA/Gallery`, and
reads no other app's data.

## Why it is necessary

**Root is about one shared volume, not privilege.** The three services share a
single `/meta-core` volume: `metawatch-core` runs the Redis instance and owns
the lock and service-registry files in it, and the two peers read the leader
info and write their own registration files beside it. They are separate
containers writing one directory as one identity, so they must agree on a uid.
meta-core creates that tree on first boot before any of them could be chowned
into place. `metawatch-app` — the only service reached by a browser, and the
only one parsing user input — is unprivileged (`$PUID:$PGID`) with its own
private data dir.

Note this core is deliberately **not `privileged`**, unlike the standalone
MetaCore app. That app needs it for rclone remote mounts; MetaWatch's core runs
with `ENABLE_FILE_WATCHER=false`, mounts no media, and performs no mounts.

**The published ports are the network.** MetaWatch is a peer, not a client of a
server: `4003` (content transport) and `4004` (discovery) are raw libp2p TCP.
libp2p speaks its own multiplexed, Noise-encrypted protocol — it cannot be
carried through an HTTP reverse proxy, so there is no way to fold it behind
AppShield the way the web UI is. Without inbound reachability the app still
installs, starts and works for browsing and playback; it simply cannot serve
bytes to anyone else. That is what the `needs-public-ip` tag declares, and
`tips.before_install` says it in plain words.

**`pcs` without Caddy labels is for app-to-app reach, not browser reach.** The
two peers join the shared network so they can find and query a co-located
MetaGateway — a companion app on the same box — including by mDNS. Neither has
Caddy labels and neither is published on a hostname, so no browser can reach
either through the perimeter. Cross-host discovery rides the public DHT and
needs no shared network at all.

**The content behaviour is the product.** MetaWatch discovers what other peers
publish and, having fetched bytes, seeds them back — that reciprocity is what
makes the network work. It ships no indexer, no tracker and no content of its
own, and it is disclosed twice before install: in the app `description` and in
`tips.before_install`.

## Security mitigations in place

- **Two independent gates.** AppShield (Authelia SSO) fronts the whole app, and
  MetaWatch keeps its own profile sign-in behind it. A profile is a secp256k1
  keypair: signing in means signing a challenge in the browser, and the secret
  key never reaches the server. Sign-out is real (tokens are revoked
  server-side), not just a cleared cookie.
- **Profile creation is invite-gated**, so a publicly reachable box does not
  offer "create a profile" as a button to anyone who finds the URL.
- **The attack surface facing the browser is the unprivileged service.** The
  three root services are reachable only from inside the app's own network; the
  two on `pcs` expose an HTTP API to sibling apps, not to the perimeter.
- **Memory is capped on every service** (`deploy.resources.limits.memory`), so a
  swarm peer that misbehaves cannot exhaust the host — 3 G on the transport
  peer, 1 G on discovery, 768 M on the core, 512 M on the app, 128 M on the
  gate.
- **All images are version-pinned**; none uses `:latest`.
- **The cache is bounded to one directory** (`share-data`), disclosed in
  `tips.before_install` so the owner knows what grows and where to clear it.
