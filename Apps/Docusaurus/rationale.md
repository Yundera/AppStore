# Docusaurus — Rationale

## What deviation / exception is being requested

1. **No authentication.** The site is served without the AppShield SSO gate.
2. **Root containers.** The Nginx web server and the `docusaurus-build` rebuild
   container run with `user: "0:0"`.

## Why it is necessary

- **No authentication** — Docusaurus publishes documentation: FAQs, guides and
  knowledge bases meant to be read by anyone with the link, including customers
  who have no account on the server. CONTRIBUTING lists "a public website that
  does not require authentication" as an accepted exception. AppShield cannot
  serve a whole site publicly (`ALLOWED_PATHS` opens sub-paths only, never `/`),
  so the gate is left out rather than configured around.
- **`docusaurus` (nginx:1.31.9-alpine)** — the official Nginx image's entrypoint
  runs its template/permission setup as root and then drops the worker processes
  to the unprivileged `nginx` user itself. It only touches its own app folder,
  mounted read-only.
- **`docusaurus-build` (node:20.19.2-alpine3.20)** — rebuilds the site on every
  start. Installs made by the older root-run init left `node_modules` root-owned,
  and the `npm ci` fallback (run when a build fails, e.g. after a restore dropped
  `node_modules/.cache`) must be able to replace them.

The one-shot `docusaurus-init` step runs as `$PUID:$PGID`, so the generated
project stays editable by the user and by the Docusaurus MCP app.

## Security mitigations in place

- **Read-only, static only.** Nginx mounts the build output `:ro` and serves
  static HTML. There is no admin panel, no login, no upload path and no write
  access through the web interface, so there is nothing to protect behind a gate.
- **Editing is not public.** Content is edited and rebuilt only through the
  separate **Docusaurus MCP** app, which stays behind the SSO gate / OAuth.
- **The build container is not reachable.** `docusaurus-build` has no route, is
  not on the shared `pcs` network, and exits once the build is copied out.
- **No published ports.** The site is reached only through its route on the
  shared network; no `ports:` are published.
- **Resource limits** (`cpu_shares`, memory limit) are set on every service.
- **Data isolation.** Everything the app writes lives under
  `/DATA/AppData/$AppID/` (`src/` and `build/`). No user directory
  (`/DATA/Documents`, `/DATA/Downloads`, `/DATA/Media`, `/DATA/Gallery`) is
  mounted.

## Alternatives considered and rejected

- **Keeping AppShield and opening paths with `ALLOWED_PATHS`** — tested on
  AppShield 3.2.0: sub-paths such as `docs` open, but the root `/` (the home page)
  cannot be bypassed with any value, so visitors would still hit a login on the
  landing page.
- **Running Nginx as a non-root user** — the official image's entrypoint needs
  root for its own setup and drops privileges for the workers on its own.

## Data protection

- No user data is processed: the app serves static HTML generated from Markdown
  the user puts under `/DATA/AppData/docusaurus/src/`.
- Do not put private or internal-only content in the site: everything in the
  build is readable by anyone with the link.
