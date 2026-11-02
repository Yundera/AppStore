# Docusaurus — Rationale

## What deviation / exception is being requested

Both services run as root — `user: "root"` on the AppShield front door and
`user: "0:0"` on the Nginx backend. The one-shot builder step runs as
`$PUID:$PGID`.

Authentication is **not** disabled: the app is fronted by the AppShield OIDC
sidecar (`ghcr.io/yundera/appshield:2.0.6`) in OIDC-only mode, so every request
is authenticated against the PCS's built-in SSO before it reaches the site.

## Why it is necessary

- **`docusaurus` (AppShield sidecar)** — runs as root, the same as every other
  AppShield-fronted app in this store. The sidecar image expects it.
- **`docusaurus-init` (node:20-alpine)** — runs `npx create-docusaurus` and
  `npm run build` as `$PUID:$PGID` (with `HOME=/tmp`, so npm has a writable
  cache), then copies the generated project and its build output into two bind
  mounts under `/DATA/AppData/$AppID/`, which end up owned by the user.
- **`docusaurus-backend` (nginx:1.27-alpine)** — the official Nginx image's
  entrypoint runs its template/permission setup as root and then drops the
  worker processes to the unprivileged `nginx` user itself.

## Security mitigations in place

- **Authentication is on.** AppShield is the only service carrying Caddy labels
  and the only one on the shared `pcs` network's front door; there is no
  unauthenticated path to the site.
- **The backend is not published.** `docusaurus-backend` and `docusaurus-init`
  sit on the app-private `docusaurus-internal` network and are reachable only
  through the sidecar. No `ports:` are published anywhere in the app.
- **Read-only web serving.** Nginx mounts the build output `:ro`. There is no
  admin panel, no upload path, and no write access through the web interface —
  it serves static HTML only.
- **Resource limits** (`cpu_shares`) are set on every service.
- **Data isolation.** Everything the app writes lives under
  `/DATA/AppData/$AppID/` (`src/` and `build/`). No user directory
  (`/DATA/Documents`, `/DATA/Downloads`, `/DATA/Media`, `/DATA/Gallery`) is
  mounted, and nothing outside `/DATA/AppData/$AppID/` is touched.
- **The builder is one-shot and unprivileged.** The `docusaurus-init` step runs
  as `$PUID:$PGID` and exits as soon as the first build finishes.

## Alternatives considered and rejected

- **Running Nginx as a non-root user** — the official image's entrypoint needs
  root for its own setup and drops privileges for the workers on its own; there
  is no gain in pre-empting it.
- **Serving the site without the AppShield gate** — a Docusaurus site is often
  intended to be public, but this store's default is authenticated access and
  the app ships that way. A user who wants the site public should say so
  explicitly rather than have it be the shipped default.

## Data protection

- No user data is processed: the app serves static HTML generated from Markdown
  the user puts under `/DATA/AppData/docusaurus/src/`.
- The web-facing container has read-only access to the build output.
- Content is edited and rebuilt through the separate **Docusaurus MCP** app,
  which is itself behind the same SSO gate.
