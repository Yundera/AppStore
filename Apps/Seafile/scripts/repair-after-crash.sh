#!/bin/bash
# Step repair-after-crash (at: unclean-boot) — see docker-compose.yml.
#
# Runs once after the server stopped without shutting down (a power cut, a forced
# reset). What it repairs is the mestio incident of 2026-11-15: a hard reset loses the
# kernel's last ~30 s of writes (ext4 commit=30). Seafile keeps each library as
# content-addressed objects under storage/{commits,fs,blocks}/<library>/; the ones
# written in that window exist but are EMPTY, while MariaDB — durable on every commit —
# already points the library at the version they make up. The library then looks
# empty, or its newest folders do, and stays that way.
#
# 1. Find the libraries holding a 0-byte object. A listing, no data read: a full
#    `seaf-fsck` reads every block (16 min for 175 GB on mestio) and is only run on what
#    this finds. A 0-byte object is never valid: an empty file has no blocks, and every
#    commit and fs object is JSON or zlib.
# 2. `seaf-fsck --repair` those libraries: it walks back to the newest version whose
#    tree is intact, commits it as the new head (history is kept) and resets the
#    library's sync tokens, so desktop clients re-sync. It works with Seafile running.
#    A library that no longer exists (deleted, storage not yet collected) is skipped
#    by fsck and left out of the report.
# 3. Move the empty objects to a quarantine folder — required, not tidying. Seafile
#    dedupes by content: a client re-uploading the lost file finds its block "already
#    there" and the new file is silently broken (reproduced on holyhorse). Moved, never
#    deleted.
# 4. Look again: anything still empty fails the step, which raises a critical incident.
#
# What the owner is told is the REPAIRED line written to $MAISON_OUTPUT; nothing is
# written, and nobody hears about Seafile, when the storage is intact.
#
# The work runs inside the seafile container (`compose exec … bash -s`), on its own
# /shared mount, so moved files keep the owner Seafile gave them.

echo "Waiting for Seafile to be running (up to 10 minutes)..."
ready=
for _ in $(seq 1 60); do
  if compose exec seafile pgrep -f seaf-server >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 10
done
if [ -z "$ready" ]; then
  echo "Seafile did not start within 10 minutes; its storage was not checked" >&2
  exit 1
fi

out=$(compose exec -e SHARED_ON_HOST="${DATA_ROOT:-/DATA}/AppData/seafile/shared" seafile bash -s <<'SCRIPT'
set -eu
S=/shared/seafile/seafile-data/storage
FSCK=/opt/seafile/seafile-server-latest/seaf-fsck.sh
if [ ! -d "$S" ]; then
  echo "No Seafile storage yet: nothing to check"
  exit 0
fi
cd "$S"
empties() { find commits fs blocks -mindepth 3 -type f -size 0 2>/dev/null; }

repos=$(empties | cut -d/ -f2 | sort -u)
if [ -z "$repos" ]; then
  echo "No empty objects: Seafile's storage is intact"
  exit 0
fi
count=$(empties | wc -l)
echo "$count empty object(s), in: $(echo $repos)"

log=$(mktemp)
# shellcheck disable=SC2086 # one argument per library
if ! "$FSCK" --repair $repos >"$log" 2>&1; then
  cat "$log"
  echo "seaf-fsck --repair failed" >&2
  exit 1
fi
grep -E "Find available commit|Update repo|doesn't exist|integrity of repo|Fsck finished" "$log" || true

# Every library fsck was given must have been seen through to the end.
for r in $repos; do
  if ! grep -q "Fsck finished for repo ${r:0:8}" "$log"; then
    cat "$log"
    echo "seaf-fsck did not finish library $r" >&2
    exit 1
  fi
done

# One sentence for the owner per library that exists: rolled back, or checked and
# intact.
said=
for r in $repos; do
  p=${r:0:8}
  grep -q "Repo $p doesn't exist" "$log" && continue
  name=$(sed -n "s/.*integrity of repo \(.*\)($p).*/\1/p" "$log" | head -1)
  when=$(sed -n "s/.*Find available commit [0-9a-f]*(created at \([^)]*\)) for repo $p.*/\1/p" "$log" | head -1)
  if grep -q "Update repo $p status" "$log"; then
    said="$said Library \"${name:-$r}\" was rolled back to its last intact version${when:+, saved $when $(date +%Z)}: changes made after that are missing, and its desktop clients will sync it again."
  else
    said="$said Library \"${name:-$r}\" was checked and is intact."
  fi
done

Q=/shared/seafile-quarantine/unclean-boot-$(date -u +%Y%m%dT%H%M%SZ)
empties | while read -r f; do
  mkdir -p "$Q/$(dirname "$f")"
  mv "$f" "$Q/$f"
done
left=$(empties | wc -l)
if [ "$left" -ne 0 ]; then
  echo "$left empty object(s) could not be moved to $Q" >&2
  exit 1
fi
echo "Moved $count empty object(s) to ${Q#/shared/}"
if [ -n "$said" ]; then
  echo "REPAIRED=Seafile found libraries whose last changes before the stop never fully reached the disk.$said The damaged pieces were moved aside to $SHARED_ON_HOST/${Q#/shared/}."
fi
SCRIPT
) || { echo "$out"; echo "Seafile's storage check failed" >&2; exit 1; }
echo "$out" | grep -v '^REPAIRED=' || true
echo "$out" | grep '^REPAIRED=' >>"$MAISON_OUTPUT" || true
