# Odysseus — packaging rationale

Notes on the choices in `docker-compose.yml` that deviate from the store defaults.

The app is also published in AppStoreLab; the two definitions are the same apart
from the CDN base and the store-specific metadata fields.

## Container image comes from a community fork

`ghcr.io/worph/odysseus:1.0.2-dev.7c8070f`

Upstream does not currently publish a pullable image:

- `ghcr.io/odysseus-dev/odysseus` — the current org's package is **private**; every
  tag returns `unauthorized`.
- `ghcr.io/pewdiepie-archdaemon/odysseus` — the pre-rename org's package is public
  but **frozen since 2026-07-12**, with nothing indicating it is stale.

See [odysseus-dev/odysseus#5728](https://github.com/odysseus-dev/odysseus/issues/5728).
The image used here is built from unmodified upstream source with the upstream CI
workflow. It is public, anonymous-pullable, and a proper multi-arch index
(`linux/amd64` + `linux/arm64`).

The tag embeds the source commit (`7c8070f`), so it behaves as an immutable
reference even though upstream's own `1.0.2` tag is mutable and has been rebuilt
several times.

**This is the one thing to keep an eye on.** The app is only as available as that
fork's CI: if the rebuild stops, new installs break even though existing ones keep
running. Two ways out, in order of preference — swap the `image:` line the moment
upstream makes its own package public, or mirror this image to
`rg.fr-par.scw.cloud/aptero` so the store does not depend on a third party's
GitHub account. Nothing else in this file changes in either case.

## Four containers, ~4.6 GB of memory limits

Odysseus needs both a vector store and a search backend to be functional:

| Service | Limit | Why |
|---|---|---|
| `odysseus-proxy` | 128 MB | AppShield auth proxy, owns the published routes |
| `odysseus-backend` | 3 GB | Python app + FastEmbed (ONNX MiniLM) + a headless Chromium for the built-in browser MCP server |
| `odysseus-chromadb` | 1 GB | persistent long-term memory |
| `odysseus-searxng` | 512 MB | private metasearch backing Deep Research |

Measured idle usage on a test PCS right after first start: ~840 MB / ~45 MB /
~145 MB. The limits leave headroom for agent runs and research jobs, which spawn
the bundled Chromium.

Upstream's compose also ships an `ntfy` service for push notifications. It is
dropped here — the store already has a standalone Ntfy app, and `NTFY_BASE_URL`
is left empty so the feature simply stays off.

## ChromaDB persist path

Upstream's compose mounts `/chroma/chroma`, which was correct for Chroma 0.x.
Chroma 1.5.x reads `persist_path` from the `/config.yaml` baked into the image,
and that value is `/data`. The mount here targets `/data`; copying upstream's
path would silently give an ephemeral vector store.

## No model backend is configured

Odysseus is an interface and agent runtime, not a model. Nothing sensible can be
picked on the user's behalf:

- Pointing at the store's Ollama app is not possible out of the box — that app
  keeps `ollama-api` on its own `ollama_default` network and only `expose`s
  11434, so it is unreachable from here, and Compose has no notion of an optional
  external network.
- Baking in a cloud provider would require a key the user has not given.

So `OPENAI_API_KEY`, `OLLAMA_BASE_URL`, `RESEARCH_LLM_ENDPOINT` and
`EMBEDDING_URL` all ship empty, and `tips.before_install` tells the user this is
the first thing to set up. Embeddings still work offline via the bundled
FastEmbed model, so memory and search are functional before a chat model exists.

## AppShield in front

The published routes belong to an `ghcr.io/yundera/appshield` container
(`odysseus-proxy`, `container_name: odysseus`), which proxies to `odysseus-backend:7000`.
The app container keeps `expose: 7000` but has no Caddy labels, so nothing reaches it
from the internet except through the shield. This is the same shape the other ~20
protected store apps use, and it puts Odysseus behind the PCS single sign-on instead
of leaving its own login form as the only thing between the internet and an agent
runtime that holds the user's API keys.

The backend also sits on the shared `pcs` network — it has to, since that's the only
network it has in common with `odysseus-proxy` — so with `AUTH_ENABLED=false` any
other co-resident container can reach `odysseus-backend:7000` directly, unauthenticated.
That is not a gap specific to this app: 11 of the 24 AppShield-fronted store apps place
their backend on `pcs` the same way, including Jellyfin, which ships
`AUTH_DISABLED=true` by the same reasoning and audits clean.

`hostname: odysseus` is required: AppShield derives its OIDC redirect URIs from
`os.hostname()` and the auth-registrar attests the app name via the container's PTR
record, so a default random-container-ID hostname fails registration.

## Capabilities: no `privileged`, no `SYS_ADMIN`/`NET_ADMIN`

No service in this app runs `privileged`, and none adds `SYS_ADMIN` or `NET_ADMIN`.
Earlier revisions of this file carried `privileged: true` plus those two capabilities
on the AppShield proxy, copied from other store apps; nothing in AppShield needs
them — it is nginx plus a Node auth service listening on port 80, which is why the
other AppShield-fronted apps (Docusaurus, Beacon) run it with no extra privilege.
They are removed.

`odysseus-searxng` is the one service with an explicit capability set, and it is a
net *reduction*: `cap_drop: ALL` followed by `cap_add` of only `CHOWN`, `SETGID`,
`SETUID` and `DAC_OVERRIDE`. The SearXNG image's entrypoint starts as root, fixes
ownership of the bind-mounted `/etc/searxng/` and then drops to the `searxng` user
with `su-exec`; those four capabilities are exactly what that sequence needs
(`CHOWN` + `DAC_OVERRIDE` to repair the mount, `SETGID`/`SETUID` to drop). Every
other capability the Docker default set would grant — `NET_RAW`, `MKNOD`,
`SYS_CHROOT` and the rest — is dropped.

## Authentication: `AUTH_ENABLED=false`, AppShield is the only layer

Leaving the app's own auth on is not an option behind the shield, and the reason is a
path collision rather than a preference. AppShield's nginx config declares
`location /login` for its own credential form. Odysseus also serves its login form at
`/login`. With `AUTH_ENABLED=true` the app 302s to `/login`, AppShield answers that path
itself, and the user gets AppShield's "🔒 Login Required" page — footer *"Protected by
Nginx Hash Lock"* — instead of Odysseus's. Verified on holyhorse: the backend returns its
own `<title>Odysseus — Login</title>` on `http://odysseus-backend:7000/login`, but the
published URL never reaches it. The app is unusable in that configuration.

So `AUTH_ENABLED=false` and AppShield is the single gate — the same trade ConvertX makes
with `ALLOW_UNAUTHENTICATED=true`. `SECURE_COOKIES=true` and `LOCALHOST_BYPASS=false` stay
as they were.

`ODYSSEUS_ADMIN_USER`/`ODYSSEUS_ADMIN_PASSWORD` are kept: they still seed the admin record
on first start, so the app has an owner for settings and API keys even though nothing
prompts for the password. Verified after the change — Settings opens, and
`/api/health`, `/api/models` and `/api/prefs/*` all return 200.

`ALLOWED_ORIGINS` still lists all three published hostnames; AppShield forwards the
original `Host`, so the origins the app sees are unchanged.
- `ODYSSEUS_ADMIN_USER` + `ODYSSEUS_ADMIN_PASSWORD` seed the admin account on
  first start. Both must be set together, or `setup.py` falls back to printing a
  random password into the container log. **`ODYSSEUS_ADMIN_PASSWORD` must be at
  least 8 characters** — below that, `setup.py` errors out and creates no admin
  at all. `$APP_DEFAULT_PASSWORD` is 12 characters on a PCS.
- `ALLOWED_ORIGINS` is a comma-separated list of *exact* origins with no wildcard
  support, so all three published hostnames are listed. Omitting the `.nip.io`
  and `.sslip.io` entries breaks login on those URLs.

## `user: "0:0"` on the main service

The image has no `USER` directive on purpose: its entrypoint starts as root,
repairs ownership on the bind-mounted `/app/data` and `/app/logs`, then drops to
`PUID`/`PGID` with `gosu` before running uvicorn. Forcing a non-root `user:` here
would break that repair step. Verified on a test PCS: files under
`/DATA/AppData/odysseus/data/` end up owned by `1000:1000`.

## `init: true` on the main service

The image's entrypoint `exec`s uvicorn, so uvicorn becomes PID 1 — and uvicorn
does not reap orphaned children. Odysseus ships a built-in Playwright browser
MCP server that spawns Chromium, so every browser the agent starts is left
behind as a zombie. Observed on a test PCS: 30 `chromium` / `chrome_crashpad`
zombies accumulated within a few hours of light use.

That is not just untidy. Zombies stay in the host process table, and once enough
pile up, Docker's `containers/json` enumeration slows to the point where CasaOS's
app-grid request times out — the whole dashboard shows "Failed to load apps,
please refresh later" for *every* app on the box, not just this one.

`init: true` puts Docker's `docker-init` at PID 1 to reap them. After the change,
PID 1 is `docker-init`, uvicorn is PID 7, and the zombie count under the
container stays at 0.

## SearXNG configuration via a `seed/` template, not `pre-install-cmd`

SearXNG needs a `settings.yml` that enables the `json` output format (Odysseus
queries it as an API) and carries a `secret_key`. That file is
`seed/searxng/settings.yml.tmpl`, and the secret is `SEARXNG_SECRET_KEY` under
`x-compose-app.secrets` (`hex:32`) — Maison generates it once, keeps it in the
app's `.env`, and substitutes it into the template on first start.

This used to be a `pre-install-cmd` hook writing the file with `printf` and
`openssl rand -hex 32`, which is exactly the pattern CONTRIBUTING warns against:
`openssl` is not in Maison's runtime, so the substitution silently produced an
empty string, the file was written anyway, and its own `[ ! -s ]` guard meant it
was never rewritten — every install carried an empty `secret_key`. The
`seed/` + `x-compose-app.secrets` mechanism replaces it and does not have that
failure mode.

Upstream instead overrides the SearXNG `entrypoint:` with an inline shell script
that templates the secret at container start. That is not reproduced here either
way — the seed template does the same job without replacing the image's entrypoint.

## Testing

Re-validated on `holyhorse.nsl.sh` after the AppShield change (2026-07-31), installed
through a real CasaOS store registration rather than a hand-run `docker compose up`:

- All four containers start; `odysseus-backend` reports healthy and AppShield reaches it
  on `http://odysseus-backend:7000/api/health` (200).
- An unauthenticated request to `https://odysseus-<domain>/` 302s to
  `/nhl-auth/oidc/login` and on to Dex with `client_id=odysseus`, confirming the OIDC
  client registered under the right name.
- "Log in with CasaOS" lands directly in the Odysseus chat UI — no second login prompt.
  Settings opens and the app's API endpoints return 200.
- CasaOS uninstall archives `/DATA/AppData/odysseus` to a timestamped zip before deleting
  it, so the reinstall started from a clean data dir.

Earlier validation of the pre-AppShield packaging, on 2026-07-29/30:

- All three containers start; `odysseus` reports healthy ~40 s after `up`.
- ChromaDB connects and creates its collections; FastEmbed loads the MiniLM model
  (384 dimensions); SearXNG returns JSON results to the app.
- `https://odysseus-<domain>/` redirects to `/login` and serves the UI; login with
  `admin` / `$APP_DEFAULT_PASSWORD` returns 200 and sets a `Secure; HttpOnly`
  session cookie; authenticated requests to `/` and `/api/models` return 200.
- Appears as a managed app tile in the CasaOS dashboard, with the `tips.before_install`
  block rendering correctly in the ⋮ → Tips dialog.
- `docker compose down && up` preserves `auth.json` and the database — setup logs
  `[skip] auth.json already exists` and the same credentials still work.

**Known gap:** the `caddy_2` Let's Encrypt route
(`odysseus-<ip>.sslip.io`) did not obtain a public certificate on that box.
Caddy's ACME order is cancelled by a config-reload race whenever a new app is
added, and it then pins the local-CA fallback certificate. This is not specific
to this app — `casadash-<ip>.sslip.io`, already installed on the same host, fails
identically. The gateway (`nsl.sh`) and `nip.io` routes both work.
