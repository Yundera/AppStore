# Guide — Rationale

## What deviation / exception is being requested
Guide requests **two** documented exceptions:

1. **No authentication / no AppShield sidecar.** No AppShield/OIDC, no Basic Auth, no built-in login. All routes on `guide-${APP_DOMAIN}` (and the `nip.io` / `sslip.io` aliases) are publicly reachable — because the container is a read-only tutorial that exposes no actions to gate.
2. **Runs as `user: 0:0` (root).** The single service is an unmodified `nginx:1.27-alpine` bound to port 80, which requires root to bind the privileged port.

## Why it is necessary

### On the auth-disabled deviation
**Guide is a tutorial / no-action container.** The whole app is read-only: it renders text, screenshots, and Markdown docs, and links out to other apps' install URLs. It **cannot mutate the user's PCS**, cannot install anything, cannot call any admin API, cannot upload, cannot proxy, and cannot execute code on behalf of the user. There is no `POST`, no write endpoint, no admin surface — an unauthenticated visitor and an authenticated one have exactly the same capabilities: view the docs. AppShield exists to gate *actions*; there are no actions here to gate.

Concretely, the container is a plain `nginx:alpine` serving `index.html`, `guide.html`, a bundle of Markdown docs under `/docs`, a public catalogue JSON, and a small set of screenshots. There is no database, no user state on the server, and nothing behind an auth gate that would benefit from protecting. Its whole purpose is to be the first URL a new PCS owner opens after setup, to help them decide what to install — putting Authelia SSO in front of it would only add friction to the *"just landed on my PCS, what now?"* moment it is designed for.

This mirrors the "public website" exception explicitly called out in `CONTRIBUTING.md` § Security Checklist ("A public website that does not require authentication").

### On the `user: 0:0` deviation
The container is the stock `nginx:1.27-alpine` upstream image and listens on port 80, which is privileged and requires root to bind. Guide has **no `/DATA` volumes** — no `/DATA/AppData/guide/`, no user-directory mounts — so the "root containers are acceptable when volumes map exclusively to AppData" allowance in `CONTRIBUTING.md` § Permission Strategy applies *a fortiori* (nothing on the host to touch at all). We did not switch to `nginxinc/nginx-unprivileged` because bind-mount-free static serving on port 80 is the exact case where root inside a rootless-network-namespaced container is safe and idiomatic; deviating from the upstream image would add a second custom Dockerfile layer for no measurable security gain.

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

### For the auth deviation
- **AppShield (OIDC) sidecar** — rejected because there is nothing for it to protect: the container is a tutorial with no writes, no admin API, and no action endpoints. AppShield would also defeat the app's purpose (be the first place a fresh PCS owner lands to learn what to install) by gating the onboarding wizard behind a login the user has not yet been walked through, before they have installed anything worth protecting.
- **AppShield in "hash-lock" (unauthenticated shared-secret) mode** — provides no meaningful protection for content that is intentionally public, while still adding a moving part.
- **Built-in login (like Immich / Jellyfin)** — would require introducing user accounts and a session store, contradicting the static-site nature of the app and duplicating the auth already provided elsewhere on the PCS.

### For the `user: 0:0` deviation
- **`user: $PUID:$PGID` on stock nginx** — fails at startup: master nginx can no longer bind port 80 (`permission denied`).
- **`nginxinc/nginx-unprivileged` image on port 8080** — technically viable, but requires a second Caddy hop rewrite and diverges from every other Yundera app that fronts a `:80` upstream; the operational cost outweighs the gain since we have no volumes and no writable filesystem paths for root to abuse.
- **`cap_add: NET_BIND_SERVICE` + non-root user** — would work on Linux but is not portable across all runtimes the store targets and adds an extra capability to the container spec for a static file server.

## Data protection
There is no user data on the server side to protect:
- No `/DATA/AppData/guide/` volume — the container is stateless.
- No `/DATA/<user-dir>/` mounts.
- User preferences (language, wizard answers) live in browser `localStorage`; they survive container removal and reinstall automatically because they never left the browser.
- Uninstall / reinstall / upgrade are trivial: no migration, no backup step required.
