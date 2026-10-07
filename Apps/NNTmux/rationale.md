# NNTmux — Rationale

## What deviation / exception is being requested

1. The **NNTmux web UI is published on its own hostname** (`nntmux-<user>.<domain>`) with no
   AppShield sidecar in front of it — it is protected by NNTmux's own login only.
2. The seeded `nntmux.env` contains TMDB and TVDB API keys as literals.

## Why it is necessary

1. NNTmux is a Laravel application with its own user table, session handling and admin
   role. Its admin account is created at install from `$APP_DEFAULT_PASSWORD`, so
   authentication is **enabled by default** — the "app's own built-in auth" alternative the
   security checklist accepts. Fronting it with AppShield as well would double-prompt on
   every page and break its own OTP and password-reset flows. Its Newznab API is keyed per
   user (`apikey` / `r=`), as every Newznab client expects.
2. Those two keys are NNTmux's upstream project defaults, shipped in its own
   `.env.example`. They are shared read-only application keys for public metadata catalogs,
   not user credentials, and they make the app work immediately after installation. An
   operator can replace them from the NNTmux admin UI.

## Security mitigations in place

- The admin password and the database password both come from `$APP_DEFAULT_PASSWORD`, the
  platform-generated secret — never a hardcoded literal — and are surfaced in
  `tips.before_install`.
- `nntmux-db`, `nntmux-redis`, `nntmux-manticore` and `nntmux-scanner` are on the
  app-private `nntmux-internal` network, carry no Caddy labels and publish no host port. Only
  the web container joins the shared `pcs` network.
- API users made with `nntmux-setup api-user <name>` get a random password nobody knows (they
  are used by API key only) and the plain User role's permissions — not admin rights — with
  raised daily request caps. The helper refuses to turn an admin account into an API client.
- Public registration defaults to **closed** (`NNTMUX_REGISTRATION`), re-applied by the
  scanner on every pass because nntmux re-seeds its settings on each boot.
- The app settings reach only the scanner, under a `SETUP_` prefix, so a blank value never
  overrides nntmux's own `.env`. The NNTP password is never printed by `nntmux-setup status`.
- NNTP provider credentials are left **blank** in the seed. The `nntmux.env` seed is guarded
  by `[ ! -f … ]`; `scanner.sh` and `nntmux-setup` are shipped code (the app's `seed/`) and are
  rewritten on every start.
- All binds are under `/DATA/AppData/nntmux/`, declared in `x-compose-app.folders`;
  `cpu_shares` on every service; the NNTmux and Manticore images are pinned by digest.

## Alternatives considered and rejected

- **AppShield in front of NNTmux.** Two independent login gates on one UI; its OTP,
  password-reset and API endpoints break behind the OIDC redirect.
- **Blank the TMDB/TVDB keys.** Covers and metadata then silently fail until the user finds
  two upstream registration flows.

## Data protection

All state — MariaDB and the NZB store — is under `/DATA/AppData/nntmux/`, the unit Maison
archives on uninstall and restores from backup, so a reinstall with "keep user data" comes
back with the release catalogue intact rather than re-scanning Usenet from scratch.

Two traps guard that catalogue across recreates:
- `/app/_install` (the install lock) is bind-mounted. Without the lock, the image's entrypoint
  runs `nntmux:install`, which drops every table.
- `nntmux-db` starts through a small wrapper that removes a `tc.log` carrying MariaDB's
  clean-shutdown marker (first byte `A`). The app manager's recreate leaves that file behind,
  and MariaDB then crash-loops on "Bad magic header in tc log". A `tc.log` with any other
  header (a real crash) is left to MariaDB's own recovery.
