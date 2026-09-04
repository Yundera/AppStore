# Radicle — Rationale

## What deviation / exception is being requested

Two, both on the security checklist:

1. **No authentication gate.** Neither of the app's two domains (`radicle-<domain>`, the
   web UI, and `radicle-api-<domain>`, the JSON API) is behind AppShield/Authelia or any
   other login.
2. **A published host port.** `8776/tcp` is bound on the host so peers on the Radicle
   network can dial in.

## Why it is necessary

**A Radicle node is a public participant in a public network.** Radicle is peer-to-peer
Git: repositories are replicated between nodes and served to anyone who asks. A node
nobody can reach is not a degraded Radicle node, it is not a Radicle node at all. The
same is true of the API: `radicle-httpd` is the read side of that participation.

**The web UI cannot be gated separately from the API.** Radicle Explorer is a static
bundle that runs entirely in the visitor's browser; every piece of data it shows is
fetched by *the browser* from `radicle-api-<domain>`, cross-origin. Putting the SSO gate
in front of the UI while the API stayed open would gate nothing — the data would remain
readable at the API domain — while adding a login page and a sidecar container. It would
be a padlock drawn on the door, not a lock.

**Port 8776 is the protocol.** Radicle's peer protocol is not HTTP, so Caddy cannot carry
it. Without the published port the node still pushes outward to public seeds, but no peer
can ever fetch from *this* node — the one thing the user installed it for. The app is
tagged `needs-public-ip` so that this is visible before install.

## Security mitigations in place

- **Only public repositories are served.** `radicle-httpd` filters its repository
  listings and lookups on `visibility().is_public()`; a repository created with
  `rad init --private` is not listed and not reachable through the API. Nothing the user
  has not published is exposed.
- **The API is read-only.** As of `radicle-httpd` 0.25 the daemon has no session,
  authentication or write endpoints at all — its whole surface is `GET` over
  `/repos`, `/node`, `/delegates`, `/stats`. There is nothing to authenticate *to*,
  and no request can change state on the server.
- **The node stores nothing by default.** The shipped configuration sets
  `seedingPolicy.default = block`: a fresh node replicates nothing until the user
  explicitly seeds a repository with `rad seed <rid>`. It cannot be used as an
  unbounded drop box for whatever the network gossips at it.
- **The web UI is not a control surface.** It only browses. Creating repositories,
  issues and patches requires the `rad` CLI and the user's own signing key, which never
  leaves their machine.
- **Ordinary container hardening.** All three services run as `$PUID:$PGID`, never root;
  each has a memory limit and a CPU share; only the two HTTP services join the shared
  `pcs` network, and the node — the one with the published port — sits on an app-private
  bridge with no route into the rest of the deployment.
- **No credentials to leak.** The node's key pair is generated on the server and is used
  to secure peer connections; it signs nothing permanent. Upstream's own seed-node guide
  recommends leaving it without a passphrase for exactly this reason, since a passphrase
  would have to be supplied on every start.

## Alternatives considered and rejected

- **AppShield in front of the web UI only** — rejected: the data is served by the API
  domain, which must stay open for the UI to work at all, so the gate would protect
  nothing while implying that it did. Misleading security is worse than none.
- **AppShield in front of both** — rejected: it breaks the app. The browser's
  cross-origin calls from the UI domain to the API domain carry no SSO session, and a
  peer or a `git clone` cannot log into Authelia either.
- **Not publishing 8776** — rejected as the default: it turns the node into a
  write-only client that no peer can fetch from. Users whose PCS has no reachable public
  IP still get a working app (repositories replicate outward), which is what the
  `needs-public-ip` tag communicates.
- **A permissive seeding policy** (`default: allow`) — rejected: it would make every
  install replicate whatever the network offers onto the user's disk without them
  asking.

## Data protection

All state lives in `/DATA/AppData/radicle/`: `home/` (the node's key pair, repository
storage, policy and COB databases) and `caddy/` (the web server config). Both survive
uninstall/reinstall, so the node keeps its identity — its Node ID — across the app
lifecycle; losing that key would mean losing the node's identity on the network, so
nothing in the app ever regenerates it once present.

Repository content in `storage/` is Git object data that the user chose to seed. It is
public by definition, signed by its authors, and verified on fetch: a peer cannot alter
what this node serves, because every ref is signed by the key of the delegate that
published it.
