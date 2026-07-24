# AIOStreams — Rationale

## What deviation / exception is being requested

The app uses its **own built-in authentication** (enabled by default) rather than
the recommended AppShield OIDC sidecar, and its Stremio add-on protocol endpoints
(`/stremio/<config>/manifest.json`, `/stremio/<config>/stream/...`) are reachable
without the platform SSO.

## Why it is necessary

AIOStreams is a Stremio add-on. Stremio fetches the manifest and stream endpoints
machine-to-machine when you open a title; it cannot complete an interactive OIDC /
Authelia login. Placing the app behind AppShield SSO would make those endpoints
unreachable and break playback. The add-on's install URL and its human dashboard
share the same `/stremio/` path prefix, so AppShield `ALLOWED_PATHS` cannot exempt
the fetch endpoints without also exposing the dashboard.

This is the same shape as the existing `Apps/SegmentStremioAddon`, which exposes its
add-on API to Stremio while gating its UI.

## Security mitigations in place

- The dashboard and configure page are gated by the app's own login
  (`AIOSTREAMS_AUTH: admin:$APP_DEFAULT_PASSWORD`), enabled by default.
- The add-on endpoints require the per-install, encrypted configuration blob as
  their credential. That blob is encrypted with a 64-character hex `SECRET_KEY`
  generated uniquely per install (see below), so the endpoints are not usable
  without a URL the operator generated.
- Runs as `user: $PUID:$PGID` (non-root), all volumes confined to
  `/DATA/AppData/aiostreams/`, with `cpu_shares` and a memory limit set.

## Alternatives considered and rejected

- **AppShield OIDC in front:** breaks Stremio's machine fetch (no interactive login).
- **AppShield with `ALLOWED_PATHS`:** cannot split the shared `/stremio/` prefix, so
  it would either break fetch or expose the dashboard.
- **No authentication at all:** rejected. The dashboard is gated by default.

## Data protection

All configuration lives in `/DATA/AppData/aiostreams/` (SQLite database plus the
generated `secret_key`). The `SECRET_KEY` is generated once and kept in AppData, so
it survives uninstall/reinstall with "keep data" and previously saved configurations
remain decryptable. No user media is mounted; the app stores only add-on settings.
