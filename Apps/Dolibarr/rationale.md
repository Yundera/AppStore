# Dolibarr — Rationale

## What deviation / exception is being requested
Both services run as `user: "0:0"` (root). Authentication uses Dolibarr's built-in login with auto-configured admin credentials (`$APP_DEFAULT_PASSWORD`).

## Why it is necessary
- **Dolibarr**: The official image requires root to manage Apache, write to `/var/www/documents`, install modules, and handle file permissions. The image uses `WWW_USER_ID` / `WWW_GROUP_ID` environment variables to control the web server user internally. Running as non-root causes permission errors on document uploads and module installation.
- **MariaDB**: Requires root for database initialization, InnoDB file management, and schema migrations (`MARIADB_AUTO_UPGRADE`). Standard practice for MariaDB containers.

## Security mitigations in place
- All volumes map exclusively to `/DATA/AppData/$AppID/` — no access to user directories
- No privileged mode, no elevated capabilities
- Memory limits on both services (1G each)
- Database isolated on internal `dolibarr-network` — not exposed on `pcs`
- MariaDB healthcheck ensures DB is fully ready before Dolibarr starts (`depends_on: condition: service_healthy`)
- Admin credentials use `$APP_DEFAULT_PASSWORD` (no hardcoded secrets)
- `DOLI_PROD: 1` disables debug output in production

## Alternatives considered and rejected
- `user: $PUID:$PGID` — Dolibarr's entrypoint expects root to set up Apache and file ownership via `WWW_USER_ID` / `WWW_GROUP_ID`
- Separate reverse proxy (nginx-hash-lock) — not needed because Dolibarr serves on port 80 directly and handles its own authentication

## Data protection
- Documents persist in `/DATA/AppData/$AppID/documents/`
- Custom modules persist in `/DATA/AppData/$AppID/custom/`
- Database persists in `/DATA/AppData/$AppID/db/`
- All data survives uninstall/reinstall
