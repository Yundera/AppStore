# Stremio — Rationale

## What deviation / exception is being requested

Stremio is gated by the **AppShield OIDC sidecar**, which is enabled by default — but with one
documented exception: `ALLOW_HASH_CONTENT_PATHS: "true"`. That flag exempts paths whose first
segment is 40 hexadecimal characters (`/<hash>` and `/<hash>/...`) from the SSO gate. Everything
else — the UI, settings, the add-on manager — stays behind the gate.

## Why it is necessary

Stremio streams and downloads torrent content from URLs of the form `/<infohash>/<file>`. Those
URLs are opened by **external players and casting devices** — a TV, a Chromecast, VLC — which
have no browser session and cannot carry the SSO cookie. Gating them means the app can play
media in its own tab and nowhere else, which removes the point of the app.

The infohash is treated as the capability: it is a 160-bit value the user must already possess
to ask for the content.

## Security mitigations in place

- **The exemption is a whole path segment, not a prefix.** AppShield requires the 40 hex
  characters to be followed by `/` or end-of-path, so `/<40hex>deadbeef` is not treated as a
  hash and stays gated. (Before this was tightened, any path *beginning* with 40 hex characters
  was exempt at any depth.)
- **It does not un-gate the application.** The UI, `/settings`, the add-on installer and every
  non-hash route redirect to the PCS Authelia SSO for an anonymous caller. Verified from a
  cookieless context: `GET /` → `302` to `/nhl-auth/oidc/login`.
- **It does not un-gate the app's own assets by accident any more.** Stremio's web build
  directory is itself named with 40 hex characters, so the exemption overlaps it. The app's
  nginx now serves those files from disk before anything is proxied (see the
  `yundera-download-fix` block in `docker-compose.yml`), so an exempt request for an asset is
  answered by the static root rather than by the torrent backend.
- **No inbound port publishing.** `expose:` only; reached solely through Caddy over TLS on the
  `pcs` network.
- **Resource limits** on both services, and both images pinned — no `:latest`.

## Alternatives considered and rejected

- **Gating the hash paths too** — rejected: it breaks casting and external players, which is the
  primary way the app is used. A browser-only media player is not the product.
- **`ALLOWED_EXTENSIONS`** — rejected: stream segments have no stable extension set, and an
  extension allowlist would exempt files across the *whole* app, not just content paths.
- **A short-lived signed URL per stream** — the correct long-term answer, and it is what
  AppShield's removed `DYNAMIC_PATHS`/`auto-add-hash` mechanism was reaching for: a hash became
  publicly fetchable only after an authenticated user opened it, for a bounded TTL. Restoring
  that is tracked against AppShield, not against this app; until it exists, the exemption is
  granted on path shape.

## Known limitation

The exemption is granted on the **shape** of the path, not on whether the hash refers to content
that exists. Anyone who can construct a well-formed 40-hex path reaches the torrent backend
without authenticating. The blast radius is the backend's own behaviour for unknown infohashes;
it grants no access to the user's account, library, settings or files, and no access to any other
app on the PCS. This is a deliberate, bounded trade for casting support, and it is the reason the
TTL-scoped alternative above is the intended replacement.

## Data protection

- All app state lives under `/DATA/AppData/stremio/`, covered by the bind mount and therefore by
  Maison's archive-on-uninstall.
- No user directories (`/DATA/Documents`, `/DATA/Media`, …) are mounted; the app reaches nothing
  outside its own AppData.
- Nothing is written outside `${DATA_ROOT:-/DATA}`.
