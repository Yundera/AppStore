# Audiobookshelf — Rationale

## What deviation is being requested

1. **The SSO gate covers the web UI, not the client API.** The app's router
   (`audiobookshelf-router`) sends the paths the Audiobookshelf mobile apps and podcast
   players call — `/api/`, `/hls/`, `/auth/`, `/socket.io/`, `/feed/`, `/status`, `/ping`,
   `/healthcheck`, and `POST /login` / `POST /logout` — plus the web app manifest and its two
   icons, each with or without the server's `/audiobookshelf` base path, straight to
   Audiobookshelf. Everything else, including the web UI and first-run setup, goes through
   the AppShield gate.
2. **The first account is created on first visit.** Audiobookshelf has no setting to preseed
   its root user: the first browser to open it is asked to create one (`POST /init`).

## Why it is necessary

The Android and iOS apps sign in with an Audiobookshelf username and password and then send
its token on every call. They cannot follow a browser SSO redirect, so a gate in front of
the API would make the mobile apps — half of what the app is for — unusable. Browsers fetch
the web app manifest without cookies, so behind the gate it would only get the SSO redirect.

## Why it is still safe

- Every API path checks Audiobookshelf's own token (`/api/`, `/socket.io/` events,
  `/auth/openid/config`), is a sign-in call that Audiobookshelf rate-limits, or is public
  by Audiobookshelf's design: `/status` and `/ping` (server identity, for the apps' connect
  screen) and `/feed/` (RSS feeds a user explicitly opens for one item). The manifest and
  icons are static files of the open-source web client.
- The router is an allow-list: anything not listed goes to the gate. `/init`, the only
  unauthenticated write, is not listed, so the first-visit root-user window is only open to
  someone who has already passed the box's single sign-on. Nobody on the internet can
  claim the server between install and the owner's first visit.
- Only the router and the gate are on the shared network; Audiobookshelf itself is on the
  app's own network and publishes no port, so the split cannot be bypassed.

## Media folders

The server runs as `$PUID:$PGID` and mounts `/DATA/Media/Audiobooks` and
`/DATA/Media/Podcasts` read-write: uploads and podcast episode downloads are written there,
owned by the box user. Both are named in the description.
