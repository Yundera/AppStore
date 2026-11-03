# Aube — rationale

## What exception is requested

The AppShield gate leaves one path prefix open: `ALLOWED_PATHS: "pwa"`.

## Why it is necessary

Aube is installed as a phone app (PWA) so it can receive the morning web push. When Chrome on
Android installs a PWA, it hands the manifest and icon URLs to Google's WebAPK minting server,
which fetches them **anonymously**. Behind the gate those requests get a login page, and Android
falls back to a plain home-screen shortcut, which cannot receive web push reliably.

## Mitigations

- `/pwa/` holds only static, public files built into the image: `manifest.webmanifest` and the
  app icons (SVG and PNG). No data, no API, nothing written at runtime.
- Every other path — the pages, the API, `/mcp`, the service worker — stays behind the gate.
- The backend has no route and publishes no port; the gate is the only way in.

## Alternatives considered

- Gating `/pwa/` too: Android then installs a shortcut instead of an app (observed with Newsdesk).
- `OAUTH_RESOURCE`: meant for machine clients holding a token; the WebAPK server holds none.

## Data protection

No user data is reachable without a login.
