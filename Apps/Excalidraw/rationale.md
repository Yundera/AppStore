# Excalidraw — rationale

## No data volume

`excalidraw-backend` (`excalidraw/excalidraw`) is a static single-page application served by
nginx. The editor runs entirely in the browser and the server stores nothing: the current
drawing, its library and the editor's preferences are kept in the browser's `localStorage` and
IndexedDB, on the user's device, not in the container. There is therefore no state location to
map, and no folder under `/DATA/AppData/excalidraw/` is needed. Users keep a durable copy with
**Save to...** (an `.excalidraw` file), as the description and tips say.

Live collaboration and shareable links need Excalidraw's own collaboration backend, which this
listing does not run; in the upstream build those buttons talk to excalidraw.com's public
service. The description and tips say so.

## Image pinned by digest

Upstream publishes its current multi-architecture image (amd64, arm64) only under the `latest`
tag; its `sha-*` tags stopped in 2021 and are amd64-only. The listing therefore pins the image
by content digest, `excalidraw/excalidraw@sha256:f7ee194a…` — the `latest` build of
2026-05-06, after release v0.18.1 — which is immutable. `x-compose-app.version` carries that
build date.

## Root container

`excalidraw-backend` runs as the image's default user (root, as the official nginx image does)
and touches no host path at all: it has no bind mount (rule D1). No privilege, capability or
host namespace is added. The same holds for the gate and the router.

## `/manifest.webmanifest` is served outside the gate, by the app's own router

Excalidraw's `index.html` links `<link rel="manifest" href="/manifest.webmanifest">` with no
`crossorigin` attribute, so browsers fetch it without credentials and the SSO cookie never
reaches the gate: it would answer with a redirect to the login host, which the browser blocks
as a cross-origin redirect, logging a console error on every load. `/manifest.webmanifest` is
static PWA metadata (app name, theme colours, icon paths) and carries nothing about the user.

The gate carries **no** `ALLOWED_PATHS` (AppShield matches an exempt path as a raw prefix and
forwards it un-normalised). Instead `excalidraw-router` (nginx, in front of the gate, as in
`Apps/ITTools` and `Apps/Vaultwarden`) has one exact-match `location = /manifest.webmanifest`,
proxied to the backend with that fixed URI. nginx resolves dot segments and percent-escapes
before matching, so a path such as `/manifest.webmanifest/../index.html` normalises to
`/index.html` and goes to the gate like every other path. This is not a machine-client path, so
`OAUTH_RESOURCE` does not apply; adding `crossorigin="use-credentials"` to the link would need
a change to Excalidraw's built HTML, which a listing cannot make.
