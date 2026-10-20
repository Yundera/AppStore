#!/bin/bash
# Data migration 2: refuse to put Odoo 19 on an Odoo 18 database.
#
# Runs with the app stopped. Starts a throwaway PostgreSQL of the cluster's own
# major on postgres-data, reads each database's `base` module version, and:
#   - no cluster yet, or every Odoo database on 19  -> exit 0, nothing changed
#   - any database on an older major                 -> exit 1, Maison restores
#     the pre-update backup and Odoo 18 keeps running on its unchanged data.
#
# It only reads: the probe server is stopped cleanly before the next step
# (postgres-15-to-18) runs pg_upgrade on the same directory.
set -euo pipefail

data="$APP_DIR/postgres-data"
probe="${AppID}-migration-${MIGRATION_ID}"

pgv="$(docker run --rm --network none --entrypoint cat -v "$data:/d:ro" postgres:18.3 /d/pgdata/PG_VERSION 2>/dev/null || true)"
if [ -z "$pgv" ]; then
  echo "No PostgreSQL cluster in postgres-data yet: nothing to check."
  exit 0
fi
case "$pgv" in
  15) image=postgres:15.15 ;;
  18) image=postgres:18.3 ;;
  *)
    echo "postgres-data holds a PostgreSQL $pgv cluster, which no Odoo release from this store used. Not guessing." >&2
    exit 1
    ;;
esac

docker rm -f "$probe" >/dev/null 2>&1 || true
trap 'docker stop -t 60 "$probe" >/dev/null 2>&1 || true; docker rm -f "$probe" >/dev/null 2>&1 || true' EXIT
docker run -d --name "$probe" --network none \
  -e PGDATA=/var/lib/postgresql/data/pgdata \
  -v "$data:/var/lib/postgresql/data" \
  "$image" >/dev/null

ready=""
for _ in $(seq 1 90); do
  if docker exec "$probe" pg_isready -U odoo -d postgres -q; then ready=1; break; fi
  sleep 2
done
if [ -z "$ready" ]; then
  echo "PostgreSQL $pgv did not come up on postgres-data within 3 minutes:" >&2
  docker logs --tail 20 "$probe" >&2 || true
  exit 1
fi

old=""
for db in $(docker exec "$probe" psql -U odoo -d postgres -Atc \
    "SELECT datname FROM pg_database WHERE NOT datistemplate AND datname <> 'postgres'"); do
  v="$(docker exec "$probe" psql -U odoo -d "$db" -Atc \
    "SELECT latest_version FROM ir_module_module WHERE name = 'base'" 2>/dev/null || true)"
  if [ -z "$v" ]; then
    echo "database $db: not an Odoo database, skipped"
    continue
  fi
  echo "database $db: Odoo $v"
  major="${v%%.*}"
  case "$major" in
    ''|*[!0-9]*) old="$old $db ($v)" ;;
    *) if [ "$major" -lt 19 ]; then old="$old $db ($v)"; fi ;;
  esac
done

if [ -n "$old" ]; then
  cat >&2 <<EOF
Odoo 19 cannot open these databases:$old
They were created by an older Odoo, and Odoo does not convert its database
between major versions by itself: started on them, Odoo 19 answers an error on
every page. The update is undone and your Odoo keeps running on its current
version with its data unchanged.

To move to 19, convert each database with OpenUpgrade first, then run this
update again:
https://github.com/Yundera/AppStore/blob/main/Apps/Odoo/upgrade-18-to-19.md
EOF
  exit 1
fi

echo "Every Odoo database is on 19: nothing to convert."
