# Guide — Rationale

## What deviation / exception is being requested
Guide ships **with no authentication** (no AppShield/OIDC sidecar, no Basic Auth, no built-in login). All routes on `guide-${APP_DOMAIN}` (and the `nip.io` / `sslip.io` aliases) are publicly reachable.

## Why it is necessary
Guide is a **fully-static documentation site** — the container is a plain `nginx:alpine` serving `index.html`, `guide.html`, a bundle of Markdown docs under `/docs`, a public catalogue JSON, and a small set of screenshots. There is no database, no user state on the server, and nothing behind an auth gate that would benefit from protecting. Its whole purpose is to be the first URL a new PCS owner opens after setup, to help them decide what to install — putting Authelia SSO in front of it would only add friction to the *"just landed on my PCS, what now?"* moment it is designed for.

This mirrors the "public website" exception explicitly called out in `CONTRIBUTING.md` § Security Checklist ("A public website that does not require authentication").

## Security mitigations in place
- **No sensitive endpoints exposed.** Guide has no admin surface, no write API, and no upload path. `nginx.conf` allows only `GET` on static files under `/usr/share/nginx/html/` via `try_files $uri $uri/ =404;`.
- **Onboarding answers stay client-side.** The user's audience / level / interests picks are written to browser `localStorage` (`guide.onboarding`, `guide.lang`) and never leave the browser. Deleting the container does not lose them; deleting the browser storage does.
- **Local Markdown sanitisation on the guide viewer.** The bundled Markdown viewer parses docs through a strict allowlist (`ALLOWED_TAGS`, `ALLOWED_ATTRS` in `src/js/app.js`), strips `on*` event handlers, blocks `javascript:` / `data:` / `vbscript:` URLs, drops `<script>` / `<iframe>` / `<style>` / `<object>` / `<embed>` / `<form>` outright, and auto-adds `rel="noopener noreferrer"` to any external `target="_blank"` link. Even if a doc later contained raw HTML, XSS cannot execute.
- **Runtime env whitelist.** Only `CASAOS_URL` is read from env at boot; the boot script writes exactly one JSON key into `config/runtime.json`. No other env vars are surfaced to the frontend.
- **No outbound network at runtime.** The catalogue is baked into the image at build time (`Dockerfile` stage 1 clones `Yundera/AppStore` once, syncs, and copies `catalog.json`). Runtime nginx never phones home.
- **Small resource footprint.** 64 MB memory cap, cpu_shares 30. Trivial blast radius even if compromised.
- **No `/DATA` volumes at all.** Nothing to leak.
- **Specific image tag.** Referenced by digest via the `ghcr.io/yundera/guideapp` release channel (no `:latest` at deploy time in the shipped compose).

## Alternatives considered and rejected
- **AppShield (OIDC) sidecar** — rejected because it defeats the app's purpose (be the first place a fresh PCS owner lands to learn what to install). It would gate the onboarding wizard behind a login the user has not yet been walked through, before they have installed anything worth protecting.
- **AppShield in "hash-lock" (unauthenticated shared-secret) mode** — provides no meaningful protection for content that is intentionally public, while still adding a moving part.
- **Built-in login (like Immich / Jellyfin)** — would require introducing user accounts and a session store, contradicting the static-site nature of the app and duplicating the auth already provided elsewhere on the PCS.

## Data protection
There is no user data on the server side to protect:
- No `/DATA/AppData/guide/` volume — the container is stateless.
- No `/DATA/<user-dir>/` mounts.
- User preferences (language, wizard answers) live in browser `localStorage`; they survive container removal and reinstall automatically because they never left the browser.
- Uninstall / reinstall / upgrade are trivial: no migration, no backup step required.
