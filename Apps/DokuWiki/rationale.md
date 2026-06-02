# DokuWiki — Rationale

## What deviation / exception is being requested
Both services run as `user: "0:0"` (root). Authentication is handled via DokuWiki's first-launch setup wizard at `/install.php` (no pre-configured credentials).

## Why it is necessary
- **DokuWiki**: The official image runs Apache as root and manages file permissions in `/storage`. Running as non-root causes permission errors when writing wiki pages, uploading media, and installing plugins.
- **nginx-hash-lock**: Used solely as a port proxy (8080 → 80), not for authentication. The official DokuWiki image hardcodes Apache on port 8080, which cannot be changed via environment variables. Caddy expects port 80, so nginx-hash-lock bridges the gap.

## Security mitigations in place
- All volumes map exclusively to `/DATA/AppData/$AppID/` — no access to user directories
- No privileged mode, no elevated capabilities (cap_add removed)
- Memory limits on both services (nginx: 128M, DokuWiki: 512M)
- CPU limits on DokuWiki (0.5 cores)
- DokuWiki's built-in ACL (Access Control Lists) handles user authentication and authorization
- Setup wizard (`/install.php`) requires admin account creation on first launch

## Alternatives considered and rejected
- `user: $PUID:$PGID` — causes Apache file ownership conflicts; DokuWiki cannot write pages or manage plugins
- Removing nginx-hash-lock — not possible because the upstream image hardcodes port 8080 and Caddy expects port 80

## Data protection
- All wiki data (pages, media, config) persists in `/DATA/AppData/$AppID/storage/`
- Plain text files — no database migration needed
- Data survives uninstall/reinstall
