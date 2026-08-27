# DokuWiki — Rationale

## What deviation / exception is being requested
The AppShield sidecar (`dokuwiki-proxy`) runs as `user: "0:0"` (root).

No authentication exception is claimed. The app is fronted by the **AppShield** OIDC
sidecar, so every request — including `/install.php` — is behind the PCS's Authelia SSO
before it reaches DokuWiki.

## Why it is necessary
- **AppShield sidecar**: runs as root like every other AppShield deployment in this store
  (see `Apps/ConvertX`, `Apps/Spliit`) — it binds port 80 in the container and manages its
  own OIDC session state.

## Why AppShield is compatible with DokuWiki
AppShield reserves `/login`, `/health` and `/nhl-auth/`. DokuWiki does not use any of them:
its login is an *action* on a page (`/doku.php?do=login`, or `/<page>?do=login` with the
image's `userewrite=1`), never a `/login` path, and the image's own healthcheck hits
`/health.php` on the backend directly. The only side effect is that a wiki page literally
named `login` would be shadowed by AppShield's sign-in page.

DokuWiki's built-in ACL is kept enabled on top of the SSO gate as a second layer — the
installer still creates the wiki superuser, which the admin interface needs.

## Security mitigations in place
- SSO (OIDC/Authelia) in front of everything; the DokuWiki backend publishes no port and
  lives only on the app-private `dokuwiki-internal` network
- The backend runs as `$PUID:$PGID`, not root
- All volumes map exclusively to `/DATA/AppData/$AppID/` — no access to user directories
- No privileged mode, no elevated capabilities
- Memory limits on both services (sidecar: 128M, DokuWiki: 512M); CPU limit on DokuWiki (0.5 cores)
- `tips.before_install` links to the installer with the recommended ACL policy
  pre-selected, and warns that the installer's own default is the more permissive
  *Open Wiki*

## Alternatives considered and rejected
- **Leaving the app on the plain `nginx-hash-lock` port proxy** — it carried no credential
  at all, so `/install.php` was anonymously reachable and the wiki could be claimed by the
  first visitor. Replaced by AppShield in OIDC mode.
- **Running the backend as root** — the image entrypoint then runs
  `chown -R www-data:www-data /storage` on every boot, overwriting the `$PUID:$PGID`
  ownership Maison sets and leaving the wiki's config unreadable to the user in a file
  manager. Started as `$PUID:$PGID` the entrypoint skips that chown and Apache serves on
  8080 unchanged. `x-compose-app.folders` uses `recursive: true` to reclaim trees an
  earlier root-running version left owned by uid 33.
- **Removing the sidecar** — not possible: the upstream image hardcodes Apache on 8080 and
  Caddy expects 80, and the sidecar is also what provides authentication.

## Data protection
- All wiki data (pages, media, config) persists in `/DATA/AppData/$AppID/storage/`
- Plain text files — no database migration needed
- Data survives uninstall/reinstall
