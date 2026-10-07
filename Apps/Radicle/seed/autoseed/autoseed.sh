#!/bin/sh
# Keeps this node seeding every repository its owner's own node announces.
#
# The node's seeding policy is `block`: it stores nothing it is not told to. Without
# this loop, "telling it" means `docker exec radicle-node rad seed <rid>` on the
# server, which most users have no shell for. Instead the user names their own
# Node ID once (RADICLE_OWNER, in the app's .env) and this loop does the rest:
#
#   1. follows the owner, so their refs are fetched for any seeded repository;
#   2. reads the routing table for repositories the owner's node has announced —
#      `rad init` and `rad seed` on their machine both announce — and seeds each
#      new one with scope `followed` (its delegates + the owner, nobody else).
#
# The policy stays `block`: a repository nobody in RADICLE_OWNER announces is never
# stored. It talks to the node over the control socket in the shared Radicle home,
# so it needs no network at all.
#
# It only ever adds. Unseeding is left to the user (`rad unseed <rid>` on the
# server) and is undone on the next pass while the owner's node still announces
# that repository — stop seeding it on your own machine first.

set -u

INTERVAL="${AUTOSEED_INTERVAL:-120}"
ALIVE=/tmp/autoseed.alive

log() { echo "autoseed: $*"; }

# RADICLE_OWNER may hold several IDs, comma- or space-separated, each either a bare
# Node ID (`rad self --nid`) or a DID (`rad self --did`).
owners() {
	printf '%s\n' "${RADICLE_OWNER:-}" | tr ', \t' '\n\n\n' | sed 's/^did:key://' |
		grep -E '^z6Mk[1-9A-HJ-NP-Za-km-z]{40,}$' || true
}

if [ -z "$(owners)" ]; then
	if [ -n "${RADICLE_OWNER:-}" ]; then
		log "RADICLE_OWNER='${RADICLE_OWNER}' holds no valid Node ID (expected z6Mk…); idle"
	else
		log "RADICLE_OWNER is not set; idle — set it in the app's .env to auto-seed your repositories"
	fi
else
	log "auto-seeding repositories announced by: $(owners | tr '\n' ' ')"
fi

while :; do
	touch "$ALIVE"
	for nid in $(owners); do
		# Both reads go through the control socket; until the node is up they fail
		# and the pass is simply retried.
		follows=$(rad follow 2>/dev/null) || continue
		case "$follows" in
		*"$nid"*) ;;
		*) rad follow "did:key:$nid" --alias owner >/dev/null 2>&1 && log "following owner $nid" ;;
		esac

		seeded=$(rad seed 2>/dev/null) || continue
		for rid in $(rad node routing --json --nid "$nid" 2>/dev/null | grep -o 'rad:z[1-9A-HJ-NP-Za-km-z]*'); do
			case "$seeded" in *"$rid"*) continue ;; esac
			# Sets the policy, then fetches. A failed fetch (owner offline) still leaves
			# the policy in place, and the node fetches on the owner's next announce.
			timeout 300 rad seed "$rid" --scope followed >/dev/null 2>&1
			if rad seed 2>/dev/null | grep -q "$rid"; then
				log "seeding $rid (announced by $nid)"
			else
				log "could not seed $rid yet; retrying next pass"
			fi
		done
	done
	sleep "$INTERVAL"
done
