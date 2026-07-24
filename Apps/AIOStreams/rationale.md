# AIOStreams Rationale

## What deviation / exception is being requested

The app uses its **own built-in authentication** rather than the recommended
AppShield OIDC sidecar, and its Stremio add-on protocol endpoints
(`/stremio/<config>/manifest.json`, `/stremio/<config>/stream/...`) are reachable
without the platform SSO.

## Why it is necessary

AIOStreams is a Stremio add-on. Stremio fetches the manifest and stream endpoints
machine-to-machine when a title is opened; it cannot complete an interactive OIDC
login. Placing the app behind AppShield SSO would make those endpoints unreachable
and break playback.

The add-on's install URL and its human-facing configure page share the same
`/stremio/` path prefix (`/stremio/<config>/manifest.json` versus
`/stremio/configure`), so a prefix-based AppShield `ALLOWED_PATHS` entry cannot
exempt the fetch endpoints without also exposing the configure page.

This is the same shape as the existing `Apps/SegmentStremioAddon`, which exposes
its add-on API to Stremio (`ALLOWED_PATHS: "/api/"`) while gating its UI behind
AppShield. AIOStreams cannot use that mechanism only because its two surfaces are
not separable by prefix.

## Security mitigations in place

- The configure page and dashboard are gated by the app's own login, set via
  `AIOSTREAMS_AUTH: admin:$APP_DEFAULT_PASSWORD` **and**
  `AIOSTREAMS_AUTH_REQUIRED: "true"`. Both are required: `AIOSTREAMS_AUTH` only
  defines the credential map, and the enforcement flag defaults to `false`, which
  would leave the configure page public.
- Enabling `AIOSTREAMS_AUTH_REQUIRED` also activates the `CONFIG_ACCESS_KEY` gate,
  which is generated and persisted automatically on first run and checked on
  config create, update and serve.
- The add-on endpoints are addressed by a per-install configuration blob encrypted
  with a 64-character hex `SECRET_KEY` generated uniquely per install, so they are
  not usable without a URL the operator generated.
- Runs as `user: $PUID:$PGID`, all volumes confined to `/DATA/AppData/aiostreams/`,
  with `cpu_shares` and a memory limit set.

## Alternatives considered and rejected

- **AppShield OIDC in front:** breaks Stremio's machine-to-machine fetch, since the
  client cannot complete an interactive login.
- **AppShield with `ALLOWED_PATHS`:** cannot split the shared `/stremio/` prefix, so
  it would either break the fetch or expose the configure page.
- **No authentication at all:** rejected. This is what the app does by default, and
  is why `AIOSTREAMS_AUTH_REQUIRED` is set explicitly.

## Data protection

All configuration lives in `/DATA/AppData/aiostreams/` (SQLite database plus the
generated `secret_key`). The `SECRET_KEY` is generated once and kept in AppData, so
it survives uninstall/reinstall with "keep data" and previously saved configurations
remain decryptable. No user media is mounted; the app stores only add-on settings.
