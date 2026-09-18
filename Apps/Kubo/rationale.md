# Kubo (IPFS) — Rationale

## What deviation / exception is being requested

1. **One hostname is served without authentication.** `kubo-gateway-${APP_DOMAIN}` reaches
   the node's read-only gateway with no login in front of it.
2. **Caddy labels sit on the backend container**, not only on the AppShield sidecar.
3. **A host port is published**: `4001/tcp` and `4001/udp`, the libp2p swarm.

## Why it is necessary

**1. The share link is the feature.** Pinning content you cannot hand to anyone is a
backup, not IPFS. A recipient who has to sign into the owner's server first is not a
recipient — the link has to open in a stranger's browser. This is the same exception the
store already grants FileBrowser's `share/` prefix, except that here the public surface is
a whole hostname rather than a path, for the reason in the next paragraph.

**Why a separate hostname rather than a path split on the main one.** A path gateway serves
every shared object from the origin it was reached on. Shared content is a file the owner
chose, but it can be HTML, and HTML on `kubo-${APP_DOMAIN}` would run as same-origin script
next to `/api/v0/*` — the node's unauthenticated, total control API — with the visitor's
SSO session cookie already attached. That is a stored-XSS-to-node-takeover path, and it is
created by the packaging, not by IPFS. Moving the gateway to its own hostname makes that
script cross-origin to the API, where Kubo's own origin check rejects it: the API allowlist
(`API.HTTPHeaders.Access-Control-Allow-Origin`) names only the three WebUI hostnames, and
anything else gets 403. Verified on Kubo 0.43.1 — allowlisted origin 200, every other
origin 403.

**2. The labels on `kubo-backend` are what publish that hostname.** They name
`{{upstreams 8080}}` and nothing else. Caddy builds routes only from what a label names, so
port 5001 — the RPC API and the WebUI — has no route on any hostname except through the
AppShield sidecar. This is the shape `Apps/Radicle` already ships for `radicle-api`.

**3. libp2p is not HTTP.** An HTTP reverse proxy cannot carry the swarm protocol, so a node
that is to be dialable has to publish the port. It is shipped enabled rather than commented
out because without it the node can only pull: other peers and the public gateways cannot
fetch what this node pins, and Kubo's AutoTLS never obtains the `libp2p.direct` certificate
that lets browsers open a connection to it. The app is degraded, not broken, without a
reachable address — hence `needs-public-ip` rather than a hard requirement.

## Security mitigations in place

- **`Gateway.NoFetch: true`.** The public hostname serves only blocks this node already
  holds; any other CID answers 404 without touching the network. Without it the box is an
  open IPFS gateway that anyone who finds the address can pull arbitrary content through,
  on the owner's bandwidth and IP. Measured: a pinned CID 200s, an unheld CID 404s in
  0.8 ms. The owner is therefore the only party who can decide what that hostname serves.
- **The public hostname is read-only.** Kubo's gateway has no write path; every mutation is
  an RPC call on 5001, which is not routed there.
- **`Access-Control-Allow-Origin: *` on the gateway, and only there.** The WebUI previews a
  file by fetching it from the gateway hostname, which is a different origin from its own,
  so it needs the header. It is `*` rather than the app's own hostnames because the gateway
  writes configured headers verbatim instead of matching the request origin the way the API
  server does: a list comes back as one comma-joined header, which is not valid CORS and
  which browsers reject (observed on wisera). On this origin the wildcard grants nothing —
  no cookies, no session, no credentialed requests, and only blocks the owner pinned — so it
  lets a script read bytes it could already have fetched server-side. The public gateways
  send the same header. The API's allowlist on 5001 is unaffected and stays exact.
- **The RPC API and WebUI are behind AppShield in OIDC mode** and carry no Caddy labels of
  their own, so 5001 never leaves the shared network unauthenticated.
- **Origin allowlist is explicit**, re-applied from the deployment's own domains on every
  start, and covers those three hostnames only.
- **Resource limits** on both services; `GOMEMLIMIT` under the container limit so the Go
  runtime collects rather than being OOM-killed at the edge.
- **`--enable-gc` with `Datastore.StorageMax`** bounds the block store. Pinned data is never
  collected.

## Residual risk accepted

All shared objects share the one gateway origin, so content the owner pinned can read
content the owner pinned — the standard path-gateway caveat. With `NoFetch` on, everything
on that origin was put there by the owner, which is the boundary that makes it acceptable.
A user who pins untrusted third-party HTML re-opens it; that is a property of path gateways
generally, and turning `Gateway.DeserializedResponses` off to close it would stop shared
files rendering at all and take the feature with it.

## Alternatives considered and rejected

- **Gate the gateway too.** Kills sharing outright — see above.
- **Path split on one hostname** (`/ipfs/*` public, the rest gated, as `Apps/Vaultwarden`
  does for `/admin`). Cheaper in labels, but it is exactly the same-origin arrangement the
  separate hostname exists to avoid.
- **`Gateway.DeserializedResponses: false`.** Closes the origin question by serving raw
  blocks with a download disposition — a shared photo arrives as
  `application/vnd.ipld.raw`, and a multi-block file does not reassemble at all. Sharing
  stops working.
- **Rely on a public gateway** (`dweb.link`, `ipfs.io`) for share links instead of serving
  them. Only resolves if the content is fetchable from the wider network, which needs the
  swarm port and the DHT to have caught up; a link that works in five minutes, sometimes,
  is not a share button. The owner's own hostname answers immediately, from local blocks.
- **Publish 4001 commented out**, as `Apps/qBittorrent` does for 6881. Rejected because the
  analogy does not hold: a torrent client without inbound peers still downloads, whereas an
  undialable IPFS node cannot serve anyone the thing they were given a CID for.
- **A separate `ipfs-webui` container.** It is the same application, and it would make the
  app harder to use rather than easier: served on its own, the bundle assumes the RPC API is
  at `http://127.0.0.1:5001` — the machine the *browser* is running on — and greets the user
  with its "can't connect" screen until they type an address into Settings. Served by Kubo
  from the API port, it addresses the origin it was loaded from, which is the hostname the
  user already has. Confirmed by serving it on a non-default port (15001): it connected with
  no console errors and no configuration.

## Data protection

Everything — identity key, config, pins and blocks — lives in
`/DATA/AppData/kubo/data`, mode 0700, owned by `$PUID:$PGID`. Nothing outside the app's own
folder is mounted. The init script edits only the config keys it documents and is
idempotent, so reinstalling or upgrading re-applies them and leaves the node's identity,
pin set and every other preference untouched. Garbage collection never collects a pin.
