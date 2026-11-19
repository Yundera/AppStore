# Readeck — rationale

## `/manifest.webmanifest` is served outside the gate, by the app's own router

Readeck's pages link `<link rel="manifest" href="/manifest.webmanifest">` with no
`crossorigin` attribute, so browsers fetch it without credentials and the SSO cookie never
reaches the gate: it would answer with a redirect to the login host, which the browser blocks
under Readeck's Content Security Policy, logging a console error on every page. The manifest
is static PWA metadata (app name, theme colour, icon paths) and carries nothing about the user.

The gate carries **no** `ALLOWED_PATHS` (AppShield matches an exempt path as a raw prefix and
forwards it un-normalised). Instead `readeck-router` (nginx, in front of the gate, as in
`Apps/Excalidraw` and `Apps/Vaultwarden`) has one exact-match `location = /manifest.webmanifest`,
proxied to Readeck with that fixed URI. nginx resolves dot segments and percent-escapes before
matching, so a path such as `/manifest.webmanifest/../bookmarks` normalises to `/bookmarks` and
goes to the gate like every other path. This is not a machine-client path, so `OAUTH_RESOURCE`
does not apply; adding `crossorigin="use-credentials"` to the link would need a change to
Readeck's own templates, which a listing cannot make.

## First user created on first visit

Readeck creates its first (administrator) user on first visit. That window is not open to the
internet: every path except the manifest above goes through the AppShield SSO gate, so only
someone already signed in to the box reaches Readeck's onboarding page. The tips say so.
