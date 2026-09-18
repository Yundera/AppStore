#!/bin/sh
# Applied on every start, before the daemon binds anything: Kubo's entrypoint runs
# /container-init.d/*.sh after `ipfs init` and before `exec ipfs daemon`, so these are
# offline edits of the repo config, not API calls.
#
# Everything set here is derived from the deployment or is a security property of the
# packaging — never a preference. That is why it is re-applied rather than seeded once:
# the app's domains change when the PCS is renamed or moved, and a config that still
# allowlists the old ones leaves the WebUI unable to call its own API. Anything the user
# is meant to tune is an environment variable in docker-compose.yml, not a hand edit of
# the config file, which this script would overwrite.
set -e

# Kubo answers 403 to any request carrying a browser `Origin` that is not allowlisted --
# and browsers attach `Origin` to same-origin POSTs too, which is every call the WebUI
# makes. Out of the box only localhost origins are allowed, so the bundled WebUI is dead
# on a real hostname until the app's own domains are listed here. Verified on 0.43.1:
# with the list set, the app origin gets 200 and every other origin still gets 403.
if [ -n "$IPFS_ALLOWED_ORIGINS" ]; then
  ipfs config --json API.HTTPHeaders.Access-Control-Allow-Origin "$IPFS_ALLOWED_ORIGINS"
  ipfs config --json API.HTTPHeaders.Access-Control-Allow-Methods '["POST","GET"]'
fi

# The WebUI previews a file by fetching it from whatever "Local HTTP Gateway" is set to
# in its settings, which on this deployment is the gateway hostname -- a different origin
# from the WebUI's own, so the fetch needs the gateway's permission.
#
# `*`, not the list above, because the gateway does not implement the API server's origin
# matching: it writes whatever is configured here verbatim, and a list comes out as one
# comma-joined header, which is not valid CORS and which browsers reject (observed on
# wisera). `*` is also what the public gateways send, and it gives nothing away here --
# this hostname is already world-readable, carries no cookies and no session, and serves
# only blocks the owner pinned, so allowing a script to read bytes it could already fetch
# server-side changes nothing.
ipfs config --json Gateway.HTTPHeaders.Access-Control-Allow-Origin '["*"]'
ipfs config --json Gateway.HTTPHeaders.Access-Control-Allow-Methods '["GET","HEAD","OPTIONS"]'

# The gateway host is public and unauthenticated (see rationale.md). NoFetch keeps it
# serving only what this node already holds: a CID that is pinned answers 200, anything
# else 404s in under a millisecond without touching the network. Without it the box is an
# open IPFS gateway -- anyone could pull arbitrary content from the network through its
# address and bandwidth.
ipfs config --json Gateway.NoFetch "${IPFS_GATEWAY_NOFETCH:-true}"

# The gateway port also answers /routing/v1 -- a delegated-routing endpoint that turns
# this node into a DHT lookup proxy for whoever finds the hostname. Kubo's default is on
# and the docs assume the listener is bound to 127.0.0.1; here it is a public hostname,
# so it is turned off.
ipfs config --json Gateway.ExposeRoutingAPI false

# What gets announced to the DHT. Kubo's default is "all" -- every block in the
# datastore, each announced to ~17 holders -- and on a fresh node that is a real load:
# pinning the 419-block WebUI bundle alone scheduled 422 CIDs and held the provide
# workers at 13/16 for minutes, which showed up on wisera as 50-135% of a core long
# after the daemon claimed to be idle.
#
# "pinned+mfs+entities" is upstream's suggested setting for a node with GC enabled: it
# announces the files and directories you pinned or put in MFS, and skips the internal
# chunks they are made of. The trade-off is that a client resuming a byte range mid-file
# has to look up the file's root rather than the chunk; whole-file retrieval, which is
# what a share link does, is unaffected.
if [ -n "$IPFS_PROVIDE_STRATEGY" ]; then
  ipfs config Provide.Strategy "$IPFS_PROVIDE_STRATEGY"
fi

# Soft cap on the block store. Kubo stops accepting new blocks past this and, with
# --enable-gc on the daemon, collects unpinned ones at Datastore.GCPeriod. Pinned data is
# never collected, so this bounds the cache, not the library.
if [ -n "$IPFS_STORAGE_MAX" ]; then
  ipfs config Datastore.StorageMax "$IPFS_STORAGE_MAX"
fi
