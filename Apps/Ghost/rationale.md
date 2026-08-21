# Ghost — Rationale

## What deviation / exception is being requested

- Both `ghost` and `db` (MariaDB) services run as `user: "0:0"` (root).
- Authentication relies on Ghost's own first-launch onboarding (no AppShield/OIDC).

## Why it is necessary

**Root containers:** Ghost writes content, themes, and config files to `/var/lib/ghost/content` with its own internal UID. Running as a non-root user causes permission failures on volume mounts. MariaDB similarly requires root to initialize its data directory properly.

**First-launch auth:** Ghost presents a setup wizard on first visit where the admin account is created. This is the standard Ghost deployment pattern and equivalent to Jellyfin/Immich onboarding.

## Security mitigations in place

- Both services map volumes exclusively to `/DATA/AppData/$AppID/` (no user directory access).
- Ghost is exposed only via Caddy reverse proxy with HTTPS.
- MariaDB is not exposed publicly — only reachable on the internal `ghost-network`.
- Memory limits applied to both services (512M each).

## Alternatives considered and rejected

- **AppShield OIDC:** Ghost has its own membership/subscriber system that integrates with authentication. Fronting with AppShield would interfere with Ghost's native login and subscriber management flows.
- **Non-root user:** Ghost's upstream image does not support non-root operation without significant bind-mount permission workarounds.

## Data protection

All data is stored under `/DATA/AppData/$AppID/` and persists across uninstall/reinstall cycles.
