# WordPress — Rationale

## What deviation / exception is being requested
Both services run as `user: 0:0` (root). Authentication is handled via WordPress's first-launch onboarding wizard (no pre-configured credentials).

## Why it is necessary
- **WordPress**: The official image requires root to copy core files, install themes/plugins, and manage file permissions in `/var/www/html`. Running as non-root causes file permission errors during installation and plugin management.
- **MariaDB**: Requires root for database initialization and file ownership in `/var/lib/mysql`. Standard practice for MySQL/MariaDB containers.

## Security mitigations in place
- All volumes map exclusively to `/DATA/AppData/$AppID/` — no access to user directories
- No privileged mode
- Memory limits on both services (1GB each)
- Network isolation: DB only on internal `wordpress-network`, not on `pcs`
- WordPress onboarding requires admin account creation on first launch (cannot be bypassed)

## Alternatives considered and rejected
- `user: $PUID:$PGID` — causes file ownership conflicts; WordPress cannot install plugins or update itself
- Custom entrypoint scripts — added complexity without resolving core permission issues

## Data protection
- WordPress files persist in `/DATA/AppData/$AppID/html/`
- Database persists in `/DATA/AppData/$AppID/db/`
- Both survive uninstall/reinstall
