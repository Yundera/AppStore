# IT Tools — rationale

## No data volume

`ittools-backend` (`corentinth/it-tools`) is a static single-page application served by
nginx. Every tool runs in the browser; the server stores nothing. What a user would expect to
persist — favourite tools, a tool's last settings, the theme — is kept in the browser's
`localStorage`, on the user's device, not in the container. There is therefore no state
location to map, and no folder under `/DATA/AppData/ittools/` is needed.

## Root container

`ittools-backend` runs as the image's default user (root, as the official nginx image does)
and touches no host path at all: it has no bind mount (rule D1). No privilege, capability or
host namespace is added.

## `/manifest.webmanifest` is served outside the gate, by the app's own router

Browsers fetch a page's `<link rel=manifest>` without credentials, so the SSO cookie never
reaches the gate: it answers with a 302 to the login host, which the browser then blocks as a
cross-origin redirect, logging a console error on every first load (observed on
demostaging2). `/manifest.webmanifest` is static PWA metadata (app name, theme colours, icon
paths) and carries nothing about the user.

The gate carries **no** `ALLOWED_PATHS`: AppShield matches an exempt path as a raw prefix and
forwards it un-normalised, so `/manifest.webmanifest/../<any path>` reached the backend
without a login (round-1 audit). Instead `ittools-router` (nginx, in front of the gate, as in
`Apps/Vaultwarden`) has one exact-match `location = /manifest.webmanifest`, proxied to the
backend with that fixed URI. nginx resolves dot segments and percent-escapes before matching,
so a path such as `/manifest.webmanifest/../token-generator` normalises to `/token-generator`
and goes to the gate like every other path, `/`, every tool page and the gate's own
`/AppShield/` endpoints included. This is not a machine-client path, so `OAUTH_RESOURCE` does
not apply; the other remedy, `crossorigin="use-credentials"` on the link, is in IT Tools'
built HTML and not something the listing can change.
