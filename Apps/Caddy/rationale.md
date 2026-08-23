# Caddy — Rationale

## What deviation / exception is being requested

No authentication is enabled by default. The site Caddy serves is reachable at
`https://caddy-$APP_DOMAIN/` without a login, an AppShield sidecar, or Basic Auth.

This is the exception CONTRIBUTING names as valid — "public websites" — recorded here
because the guide requires the exception to be written down rather than assumed.

## Why it is necessary

Despite the name, this app is **not** deployed as a reverse proxy. Its bundled
`Caddyfile` is a static file server: `root * /srv` + `file_server`, with `/srv` bound to
`/DATA/AppData/caddy/www/`. The app exists to publish the user's own HTML/CSS/JS —
portfolios, landing pages, documentation, SPAs, static-generator output.

- **An auth gate defeats the product.** A portfolio, landing page or documentation site
  that demands a password before it renders is not a published website. The whole
  purpose of the app is that the content is reachable by anyone with the URL.
- **There is nothing to authenticate.** The container exposes no admin panel, no upload
  form, no settings UI and no API — Caddy only reads files off disk and returns them.
  There is no account, no session and no credential in the app for an attacker to take.
- **There is no write path through the web surface.** Every request is a read. Content
  is changed only from the host filesystem — SSH, or an authenticated file manager such
  as FileBrowser — never through the published site.
- **A generic gate would also break the served content.** AppShield reserves top-level
  paths (`/login`, `/health`, `/nhl-auth/`); a user site that uses those routes would
  silently stop working, and the `try_files {path} /index.html` SPA fallback means the
  app cannot tell which paths the user's site actually owns.

The two precedents in this store are the same app shape and take the same exception:
`Apps/Nginx/rationale.md` and `Apps/Docusaurus/rationale.md`.

## Security mitigations in place

- **Read-only by construction**: the Caddyfile defines only `file_server`. No PHP, CGI,
  upload handler or write endpoint is configured, so the public surface cannot mutate
  anything on disk.
- **Config is immutable to the container**: `/etc/caddy/Caddyfile` is mounted
  `read_only: true`, so a compromise of the served content cannot rewrite the server
  configuration to add a write path.
- **Unprivileged**: the container runs as `user: $PUID:$PGID`, not root, and its only
  mounts are under `/DATA/AppData/caddy/` — no `/DATA/Documents`, `/DATA/Downloads`,
  `/DATA/Media` or any other user directory is reachable from it.
- **Dotfiles are blocked**: `@hidden { path */.* }` responds 404, so a stray `.env`,
  `.git/` or editor backup dropped into `www/` is not served.
- **Hardening headers**: `X-Frame-Options: SAMEORIGIN`, `X-Content-Type-Options:
  nosniff`, `X-XSS-Protection`, and the `Server` header is stripped.
- **Blast radius is capped**: 128M memory / 0.25 CPU limits, `cpu_shares: 50`.
- **The user is warned before installing**: `tips.before_install` states in as many words
  that the site is public with no login, and that private material must not be placed in
  `www/`.

## Alternatives considered and rejected

- **AppShield sidecar** — rejected: it puts a login in front of the published site, which
  is precisely what the app exists to avoid, and its reserved paths can collide with the
  user's own routes.
- **Basic Auth in the Caddyfile** (`basic_auth` with a bcrypt hash) — rejected for the
  same reason: a shared password in front of a public website. It also gives the visitor
  no way in, since the credential would have to be handed out out-of-band to everyone the
  site is meant for, at which point it protects nothing.
- **Auth on by default, user turns it off** — rejected: the off switch is an edit to
  `/DATA/AppData/caddy/Caddyfile` over SSH. Shipping every static site broken-by-default
  behind a gate most users must then learn to remove is worse for both usability and
  security than shipping it public and saying so plainly.
- **Leaving authentication to the user** — this is in fact what the app does, and it is
  the right layer: a user who needs a private site can add `basic_auth`, an auth portal,
  or an IP matcher to their own `Caddyfile`, which is a persistent, user-owned file.

## Data protection

- No user data, credentials or personal information is processed or stored by the app.
  It serves whatever the user chose to publish, and nothing else.
- All state lives under `/DATA/AppData/caddy/` (`www/` content, `data/` TLS material,
  `config/` autosave) and survives uninstall/reinstall.
- `data/` holds Caddy's internally-issued TLS keys only; it is not web-reachable, because
  only `/srv` is ever served.
- The container cannot reach any user directory outside its own AppData, so a defect in
  the published content cannot expose documents, downloads or media.
