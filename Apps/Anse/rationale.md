# Anse — rationale

## No data volume

`anse-app` (`ddiu8081/anse`) is an Astro (Node) server that only serves the web UI and, when
the user turns on *Request With Backend*, relays a chat request to the AI provider. It stores
nothing: conversations, settings and API keys are kept in the browser's IndexedDB and
`localStorage`, on the user's device, not in the container (upstream: "abandoned use environment
variables"; the image's Dockerfile declares no volume and writes no file at runtime). There is
therefore no state location to map, and no folder under `/DATA/AppData/anse/` is needed. The
description and tips tell the user that their data lives in their browser.

## Root container

`anse-app` runs as the image's default user (root, from `node:alpine`) and touches no host path
at all: it has no bind mount (rule D1). No privilege, capability or host namespace is added.

## `/manifest.webmanifest` is served outside the gate, by the app's own router

Anse is a PWA. Browsers fetch a page's `<link rel=manifest>` without credentials, so the SSO
cookie never reaches the gate: it would answer with a 302 to the login host, which the browser
blocks as a cross-origin redirect, logging a console error on every first load (the same fault
`Apps/ITTools` documents). `/manifest.webmanifest` is static PWA metadata (app name, theme
colours, icon paths) and carries nothing about the user.

The gate carries **no** `ALLOWED_PATHS` (AppShield matches an exempt path as a raw prefix).
Instead `anse-router` (nginx, in front of the gate, as in `Apps/ITTools` and `Apps/Vaultwarden`)
has one exact-match `location = /manifest.webmanifest`, proxied to the backend with that fixed
URI. nginx resolves dot segments and percent-escapes before matching, so
`/manifest.webmanifest/../` normalises to `/` and goes to the gate like every other path
(checked on demostaging2: 302 to the AppShield login), `/sw.js`, `/api/*` and the gate's own
`/AppShield/` endpoints included.
