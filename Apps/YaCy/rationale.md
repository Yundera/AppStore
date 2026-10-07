# YaCy — Rationale

## What deviation / exception is being requested

The YaCy **search page is reachable without logging in** at `yacy-<user>.<domain>`. No
AppShield sidecar sits in front of the app.

## Why it is necessary

YaCy is a search engine: its search page is meant to be public, the way any search
portal is. Its administration (crawler, index, settings, account pages, every `*_p.html`
page) is behind YaCy's own login, which is **enabled at install**: the seeded
`data/SETTINGS/yacy.conf` sets user `admin` with a password hash derived from
`$APP_DEFAULT_PASSWORD`. Putting AppShield in front would also hide the search page,
which defeats the point of running a search portal.

## Security mitigations in place

- Admin login enabled by default: `adminAccountForLocalhost=false`, so requests from
  inside the box get no automatic admin access either.
- The password hash is computed at install (`x-compose-app.init`, `admin-hash`), so the
  compose file holds no credential. YaCy's built-in default password (`yacy`) never applies.
- Runs as `$PUID:$PGID`, mounts only `/DATA/AppData/yacy/data`, 2 GB memory cap.
- Port 8090 is not published on the host. Only Caddy reaches the app, over `pcs`.

## Alternatives considered and rejected

- **AppShield in front of the whole app**: would require a login to search, which makes the
  public search page pointless.
- **Setting the password with `bin/passwd.sh` after start**: would need a post-start hook
  calling into the running container. Seeding the config is simpler and is in place
  before the first start.

## Data protection

The index and settings live in `/DATA/AppData/yacy/data`. The seeded `yacy.conf` is
create-if-absent, so a reinstall keeps the existing configuration and any password the
user changed in the admin UI.
