# Upgrading an Odoo 18 install to Odoo 19

The store's Odoo moved from 18 to 19 in March 2026. Odoo does not convert its database
between major versions by itself, so an install still on 18 refuses the update with
*"Odoo 19 cannot open these databases"* and keeps running 18. This page converts the
database with [OpenUpgrade](https://github.com/OCA/OpenUpgrade), the community's
migration scripts; after it, the update in Maison goes through and also moves
PostgreSQL from 15 to 18.

**Before you start**

- **Check coverage.** OpenUpgrade migrates the modules listed in its
  [coverage table](https://oca.github.io/OpenUpgrade/) for 19.0. Odoo Enterprise
  modules are not covered. A module of your own, or from a third party, in
  `/DATA/AppData/odoo/addons/` needs a 19.0 version before you start.
- **Expect some downtime**: about ten minutes for a small database, longer for a large one.
- You need a terminal on the box (SSH, or the Terminal app) with `sudo`.

## 1. Back up

In Maison, open Odoo → **Backups** → **Back up now**, and wait until it finishes.
Every step below can be undone by restoring that backup.

## 2. Stop Odoo, then start only its database

In Maison, open Odoo and **Stop** it. Then, in the terminal, start the database alone:

```bash
sudo docker start odoo-postgres-1
```

**Do not start Odoo from Maison until step 5 is done.** It would bring Odoo 18 back up
on a database that is about to become 19.

## 3. Convert each database

List your databases:

```bash
sudo docker exec odoo-postgres-1 psql -U odoo -d postgres -Atc \
  "SELECT datname FROM pg_database WHERE NOT datistemplate AND datname <> 'postgres'"
```

Then run OpenUpgrade once per database. Replace `DBNAME`:

```bash
DB=DBNAME
PW=$(sudo grep '^ODOO_DB_PASSWORD=' /DATA/AppData/odoo/.env | cut -d= -f2-)
sudo docker run --rm --network odoo_odoo-internal -u 0 -e PW="$PW" -e DB="$DB" \
  -v /DATA/AppData/odoo/addons:/mnt/extra-addons:ro \
  --entrypoint bash odoo:19.0 -c '
set -e
pip install -q --break-system-packages openupgradelib==3.13.7
python3 -c "
import io, tarfile, urllib.request
u = \"https://github.com/OCA/OpenUpgrade/archive/refs/heads/19.0.tar.gz\"
tarfile.open(fileobj=io.BytesIO(urllib.request.urlopen(u).read())).extractall(\"/ou\")"
OU=/ou/OpenUpgrade-19.0
odoo -d "$DB" --db_host postgres --db_user odoo --db_password "$PW" \
  --addons-path=/usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons,$OU \
  --upgrade-path=$OU/openupgrade_scripts/scripts \
  --load=base,web,openupgrade_framework \
  -u all --stop-after-init --no-http --log-level=warn
'
echo "exit code: $?"
```

It must end with `exit code: 0`. Warnings such as *"Could not delete obsolete record"*
or *"Can't render custom view"* are normal. Odoo deletes the records that a
module defined in 18 and no longer defines in 19 (mostly demo data); records you
created are not among them.

## 4. Check the result, then stop the database

```bash
sudo docker exec odoo-postgres-1 psql -U odoo -d DBNAME -Atc \
  "SELECT count(*) FROM ir_module_module WHERE state = 'installed' AND latest_version NOT LIKE '19.%'"
```

It must print `0`. Anything else means a module did not migrate: restore the backup
(step 6) and check that module's coverage.

Then stop the database again, so the whole app is stopped for the update:

```bash
sudo docker stop odoo-postgres-1
```

The update backs the app up first. A stopped app is copied as it is and left stopped
during the copy, but if any of its containers is running, the backup restarts the
**whole** app afterwards, Odoo 18 included.

## 5. Update in Maison

Open Odoo → **Update** and run it, with the app still stopped. Maison backs the app
up again, checks that every database is now on 19, upgrades PostgreSQL 15 → 18, and
starts Odoo 19. Log in and check your data.

## 6. If anything went wrong

Open Odoo → **Backups** and restore the backup from step 1. It puts back Odoo 18, its
database and its configuration exactly as they were.

---

Tested on 2026-10-14 with an Odoo 18.0 database running 99 modules (CRM, Sales,
Invoicing, Project, Inventory, Employees, Website), OpenUpgrade 19.0 and
openupgradelib 3.13.7. Records were kept, login and business records were checked
in Odoo 19 afterwards.
