# Piwigo — Rationale

## What exception is requested

- `piwigo` (linuxserver image) and `piwigo-db` (MariaDB) have no `user:` and start as root.

## Why it is necessary

**piwigo:** the linuxserver image is built on s6-overlay. Its init stage runs as root to
create `/config` and `/gallery`, write the nginx and php-fpm config, symlink Piwigo's
`local/`, `plugins/`, `themes/`, `_data/`, `upload/` and `galleries/` into those volumes,
and chown them to `abc` (= `PUID:PGID`). nginx and php-fpm then run as `abc`. With
`user: $PUID:$PGID` the init stage cannot do that work and the container does not start.

**piwigo-db:** the official MariaDB entrypoint starts as root only to hand
`/var/lib/mysql` to its own `mysql` user, then drops to it. Same as `Apps/Ghost`.

## Mitigations

- Both services bind only into `/DATA/AppData/piwigo/` (`config/`, `gallery/`, `db/`). No
  user folder, no Docker socket, no extra capabilities, no host network.
- The web server and PHP run as `PUID:PGID`, so every file Piwigo writes (photos, config,
  thumbnails) is owned by the box owner.
- `piwigo-db` is on the app-internal network only; only `piwigo` is on the shared network,
  and it publishes no port.
- Memory limits on both services (1G / 512M).

## Alternatives considered

- **`user: $PUID:$PGID` on the linuxserver image:** unsupported by linuxserver; s6 init
  fails on its root-only steps.
- **The Piwigo project's own `piwigo/piwigo` image:** recent and also multi-arch, but
  linuxserver's build has the longer track record (tens of millions of pulls), a documented
  `PUID`/`PGID` model that keeps every written file owned by the box owner, and a weekly
  rebuild on current Alpine/PHP.

## Data protection

All state (database, Piwigo config and plugins, photos) lives under
`/DATA/AppData/piwigo/` and survives uninstall/reinstall. The auto-install step is guarded
on `config/www/local/config/database.inc.php`, so it never runs against an installed gallery.

Login: the gallery is private as shipped. The admin account is created by the install
step with a generated password (`PIWIGO_ADMIN_PASSWORD`), guests are redirected to the
login page (`guest_access = false`), self-registration is turned off, and new albums are
private, so the web API lists nothing to a guest either. As in every Piwigo install, the
photo files themselves are served by nginx from `upload/` and `_data/i/` under random,
unguessable file names; there is no listing of those directories.
