# ChangeDetection — rationale

## `/site.webmanifest` is served outside the gate, by the app's own router

changedetection.io's pages link `<link rel="manifest" href="/site.webmanifest">` with no
`crossorigin` attribute, so browsers fetch it without credentials and the SSO cookie never
reaches the gate: it would answer with a redirect to the login host, and the browser logs a
manifest error on every page. The manifest is static PWA metadata (app name, theme colour,
icon paths), identical for every visitor, and carries nothing about the user; upstream
already exempts it from the app's own login for the same reason.

The gate carries **no** `ALLOWED_PATHS` (AppShield matches an exempt path as a raw prefix and
forwards it un-normalised). Instead `changedetection-router` (nginx, in front of the gate, as
in `Apps/Readeck` and `Apps/Excalidraw`) has one exact-match `location = /site.webmanifest`,
proxied to the app with that fixed URI. nginx resolves dot segments and percent-escapes before
matching, so a path such as `/site.webmanifest/../settings` normalises to `/settings` and goes
to the gate like every other path. This is not a machine-client path, so `OAUTH_RESOURCE`
does not apply.

## No login of its own

changedetection.io ships with its own password off. The AppShield SSO gate in front of it is
the login: every path except the manifest above goes through it, so only someone signed in to
the box reaches the app.
