#!/bin/sh
# nntmux scan launcher (NNTmux app, nntmux-scanner container).
#
# The pyrowman/nntmux image runs frankenphp and NOTHING else: no cron, no
# supervisord, no queue worker. So `settings.running=1` changes nothing on
# its own, because nothing ever starts the loop. This is that loop.
#
# It runs as a SECOND CONTAINER off the same image + the same /app/.env and
# nzb volume, rather than as a second process inside the web container, so
# the web container's entrypoint (install/populate under `set -e`) is left
# untouched.
#
# INVOCATION IS NOT FREE CHOICE. Measured PER RUNNER on a live box, NOT a
# blanket "Forking works":
#   * multiprocessing/binaries.php   — Forking OK.
#   * multiprocessing/backfill.php   — NO-OP. Reports "...3 job(s) to do
#     using a max of 0 child process(es)" and returns in 0s having done
#     nothing. Backfill must be driven DIRECTLY, per group (see the
#     backfill block below).
#   * collation MUST go through tinker/ProcessReleases DIRECTLY.
#     multiprocessing/releases.php aborts every batch on a benign PHP
#     warning (ReleaseCleaning.php:165) that turns fatal inside the Spatie
#     child -> 0 releases while collections pile into the tens of
#     thousands.
#
# Every knob comes from nntmux's own `settings` table (edited at
# /admin/tmux-edit), never from env — otherwise there are two sources of
# truth for one number.
set -u

cd /app || exit 1

setting()     { php artisan tinker --execute="echo DB::table('settings')->where('name','$1')->value('value');" 2>/dev/null | tr -dc '0-9'; }
set_setting() { php artisan tinker --execute="DB::table('settings')->where('name','$1')->update(['value'=>'$2']);" >/dev/null 2>&1; }
groups()  { php artisan tinker --execute="foreach (DB::table('usenet_groups')->where('active',1)->pluck('name') as \$g) echo \$g, PHP_EOL;" 2>/dev/null | grep -E '^[a-z0-9.]+$'; }

log() { echo "[scanner $(date -u +%H:%M:%S)] $*"; }


log "launcher started"
while true; do
    # The app settings (Env tab: NNTP_*, NNTMUX_*) — re-applied before EVERY
    # pass, because the web container's entrypoint re-seeds `settings` and
    # `usenet_groups` on each boot. Prints only what it changed.
    nntmux-setup apply 2>&1 | while IFS= read -r l; do log "$l"; done
    if [ "$(setting running)" != "1" ]; then
        log "settings.running=0 — idle"
        sleep 30
        continue
    fi

    if [ "$(setting binaries)" = "1" ]; then
        qty="$(setting backfill_qty)"; [ -n "$qty" ] || qty=20000
        log "header scan (qty=$qty)"
        php misc/update/multiprocessing/binaries.php "$qty" 2>&1 | tail -3
    fi

    # Backfill must run DIRECT, per group. multiprocessing/backfill.php
    # reports "max of 0 child process(es)" and silently does nothing — the
    # Forking wrapper leaves maxProcesses=0 for this runner specifically.
    # Depth is capped by settings.backfill_days, so this reaches back that
    # far and then stops advancing; it is NOT a full-retention backfill.
    if [ "$(setting backfill)" = "1" ]; then
        # The ONLY setting this loop writes. `delaytime` (hours, default 2)
        # blocks ProcessReleases from advancing a collection until it ages
        # past it. Correct for the leading edge — a posting may still be
        # uploading — but pointless for backfill, where every article is
        # already days old. Left at 2 during backfill it stalls the catalog
        # for two hours with a failure mode indistinguishable from a broken
        # pipeline (collections climb, releases flatline, nothing logs an
        # error).
        #
        # Asserted every pass, not once at boot, because the nntmux
        # entrypoint RE-SEEDS `settings` on every container start (trap #7)
        # — a restart silently puts this back to 2 and the tier quietly
        # stops producing. Scoped to `backfill=1` so a pure forward-tailing
        # deployment (`backfill=0`) keeps the operator's own value: this is
        # a per-phase mode, not a preference we get to override.
        if [ "$(setting delaytime)" != "0" ]; then
            log "asserting delaytime=0 for the backfill phase (was $(setting delaytime))"
            set_setting delaytime 0
        fi
        qty="$(setting backfill_qty)"; [ -n "$qty" ] || qty=20000
        log "backfill direct (backfill_days=$(setting backfill_days), qty=$qty)"
        groups | while read -r g; do
            [ -n "$g" ] || continue
            php misc/update/backfill.php "$g" "$qty" 2>&1 | grep -iE "articles|backfill|Group|no new" | tail -2
        done
    fi

    # Collation, per active group, DIRECT (never multiprocessing/releases.php).
    # Never wrap this in a short `timeout`: killing it between the release
    # INSERT and createNZBs() leaves a release row with no .nzb.gz, which
    # the feeder then correctly skips forever.
    groups | while read -r g; do
        [ -n "$g" ] || continue
        log "collate $g"
        php artisan tinker --execute="(new Blacklight\\processing\\ProcessReleases)->processReleases(1, 1, \"$g\", new Blacklight\\NNTP);" 2>&1 | grep -iE "releases (ready|created)|Added [0-9]+ releases|NZB" | tail -3
    done

    # Name fixing. Collation names a release after its post subject, which
    # for most postings is a raw `[n/m] - "file.vol12+13.par2" yEnc` line or
    # an obfuscated string, so ~85% of releases land uncategorised. This
    # renames them from the subject's file name, else from the file names
    # inside one par2 file (one article fetch per release, each release
    # tried once). Bounded per pass so the scan keeps moving; a backlog
    # drains over the following passes.
    nntmux-setup prune 2>&1 | while IFS= read -r l; do log "$l"; done
    nntmux-setup fixnames 300 2>&1 | while IFS= read -r l; do log "$l"; done

    delay="$(setting monitor_delay)"; [ -n "$delay" ] || delay=30
    log "pass complete; sleeping ${delay}s"
    sleep "$delay"
done
