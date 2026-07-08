# Stremio — Rationale

## What deviation / exception is being requested
1. Both containers run as root (`user: root` on AppShield, `user: "0:0"` on stremiocommunity)
2. AppShield uses `credentials_only` auth mode instead of OIDC
3. `ALLOW_HASH_CONTENT_PATHS: "true"` is set on AppShield

## Why it is necessary

**Root containers**: `stremiocommunity` (tsaridas/stremio-docker) requires root to write to `/root/.stremio-server` and to run FFmpeg for HLS transcoding. AppShield's standard deployment also runs as root.

**credentials_only instead of OIDC**: The original configuration used `OIDC_REGISTRAR_URL`, which depends on Dex — a separate platform service. Dex can crash or lose its static IP (`172.31.7.2`) to `auth-registrar` on container restart. When this happens, AppShield's auth service fails to register an OIDC client and returns HTTP 500 on every request, making Stremio completely inaccessible. This was reproduced consistently on both a production server and a Yundera demo server, confirming it is a platform-level reliability issue rather than a one-off misconfiguration. Switching to `credentials_only` removes this external dependency while keeping AppShield as the authentication layer, satisfying CONTRIBUTING.md's requirement that an authentication method be enabled.

**ALLOW_HASH_CONTENT_PATHS**: Stremio's streaming server exposes content through 40-character hex paths (e.g. `/bca2d44dcd7655.../stream.m3u8`) that function as bearer tokens for individual streams. AppShield ships a dedicated flag for this exact pattern, documented in its entrypoint as being "for Stremio and similar apps." Without it, every HLS segment request would be blocked by the auth layer, breaking playback.

## Security mitigations in place
- AppShield enforces login on all non-streaming paths
- Password is set via `$DEFAULT_PWD`, the platform's per-installation default password, not a static hardcoded value
- No privileged mode on either container
- Data is limited to `/DATA/AppData/stremio/server/` only — no user media directories are mounted
- Memory limits set on both services (512M AppShield, 1024M stremiocommunity)
- Hash-path bypass is scoped to the exact 40-character hex pattern used by Stremio's own access-token mechanism, not a general auth bypass

## Alternatives considered and rejected
- **Keeping OIDC**: Dex instability makes this mode unreliable across all servers, including demo/staging instances — the failure is reproducible and platform-wide, not specific to one deployment
- **nginx-hash-lock with AUTH_DISABLED**: Removes authentication entirely; rejected in favor of keeping AppShield with real credentials, per reviewer guidance to fix AppShield configuration rather than replace it
- **Non-root containers**: Both the AppShield proxy and the stremio-docker backend require root for their respective functions (port binding at the proxy layer historically, and FFmpeg/file ownership on the backend); no non-root path is currently supported by the upstream image

## Data protection
- Stremio server state persists in `/DATA/AppData/stremio/server/`
- No user media directories are accessed or mounted
- All data survives uninstall/reinstall
