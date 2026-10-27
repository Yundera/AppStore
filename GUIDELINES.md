# AppStore guidelines

How to build a good listing for the Yundera AppStore: how Maison runs an app, the conventions
the store follows, worked examples, and recommendations.

**[CONTRIBUTING.md](CONTRIBUTING.md) is the checklist a listing must pass.** It is what a
review, human or Touchstone, decides go / no-go on. This document explains how to meet it, and
names the requirement each section serves as `` `requirement-id` ``. Anything here that is not a
requirement is a recommendation: worth following, and never a reason on its own to refuse an app.

Maison's own docs are the reference for how each `x-compose-app` key behaves:

- [`docs/x-compose-app.md`](https://github.com/Yundera/Maison/blob/main/docs/x-compose-app.md) — the app manifest
- [`docs/migrations.md`](https://github.com/Yundera/Maison/blob/main/docs/migrations.md) — data migrations
- [`docs/app-env.md`](https://github.com/Yundera/Maison/blob/main/docs/app-env.md) — the variables an app receives

- [Testing and submitting](#testing-and-submitting)
- [Repository layout](#repository-layout)
- [The compose file](#the-compose-file)
- [Data and permissions](#data-and-permissions)
- [Resources](#resources)
- [Routing: `routes` and the shared network](#routing-routes-and-the-shared-network)
- [Publishing host ports](#publishing-host-ports)
- [Authentication](#authentication)
- [Maison and `x-compose-app`](#maison-and-x-compose-app)
- [Rationale (`rationale.md`)](#rationale-rationalemd)
- [Images and languages](#images-and-languages)

## Testing and submitting

*Requirements:* `install` `app-url` `works-immediately` `auth-gate` `clean-boot` `zero-config` `data-persistence`

1. **Get the compose working by hand.** Start from a plain `docker-compose.yml` and make it
   run with `docker compose up -d` on any machine.
2. **Run it on a PCS.** Copy the app folder to `/DATA/AppData/<app>/` on a PCS. Add the
   metadata, write a `.env` with the [system variables](#system-variables), and run
   `docker compose up -d` there over SSH. This is what Maison does at install time: it copies
   your compose byte-for-byte and never edits it. The only files it adds are the app's `.env`
   and a `docker-compose.override.yml` holding the extra domains the box answers on. If the
   app works by hand with a real `.env`, it works as an installed app.
3. **Test the listing.** Push the app to `Apps/<AppName>/` on your fork. Then add your fork as
   a store in Maison (**Settings → App stores**) using its archive URL:
   ```
   https://github.com/<you>/AppStore/archive/refs/heads/<branch>.zip
   ```
   Install from that store. This tests what step 2 cannot: the metadata, the icon, the
   `seed/` tree, `folders`, `secrets` and `steps`. Then test uninstall + reinstall, and an
   update over the previous version's data.
4. **Open a PR** against `main`, with the [CONTRIBUTING.md](CONTRIBUTING.md) checklist filled in. Asset paths are
   relative, so nothing needs rewriting when the PR is merged.

Test on amd64 and arm64 when the image supports both.

## Repository layout

```
AppStore
├─ Apps/                 # one folder per app
├─ category-list.json    # store categories
├─ recommend-list.json   # apps recommended on the store front
├─ store.json            # store name shown in Maison
├─ psd-source/           # PSD templates for icons, thumbnails and screenshots
└─ scripts/              # helpers (gen-thumbnail.sh)
```

An app folder:

```
Apps/MyApp
├─ docker-compose.yml   # required
├─ icon.png             # required
├─ screenshot-1.png     # required; more are welcome
├─ thumbnail.png        # optional, see Images and languages
├─ seed/                # optional: the app's initial files, mirroring /DATA/AppData/<app>/
├─ scripts/             # optional: `.sh` files a script entry names with `file:`
└─ rationale.md         # required when the app takes an exception
```

## The compose file

*Requirements:* `name-regex` `pinned-image-tag`

- The top-level `name` is the **store app ID**. It must be unique across the store and match
  `^[a-z0-9][a-z0-9_-]*$`. Use the same value for `x-compose-app.id` and as the data folder
  name under `/DATA/AppData/`.
- Pin every image to a specific version.
  [Why `:latest` is wrong](https://github.com/IceWhaleTech/CasaOS-AppStore/issues/167).
- Locale keys are lowercase: `en_us`, `fr_fr`.

### Store info

*Requirements:* `app-metadata-coherence` `description` `architectures`

The store card and the dashboard tile are described in `x-compose-app`:

```yaml
x-compose-app:
  schema_version: 2
  id: syncthing                   # = the compose `name`
  title:                          # a plain string, or one entry per locale
    en_us: Syncthing
  tagline:
    en_us: Continuous file synchronisation between your devices.
  description:
    en_us: Syncthing synchronizes files between two or more computers in real time.
  developer: Syncthing
  category: Backup
  icon: icon.png                  # a path beside the compose
  thumbnail: thumbnail.png
  screenshots:
    - screenshot-1.png
  architectures: [amd64, arm64]
  tips:                           # Markdown, shown from the tile menu
    en_us: |
      Anything the user should know after installing.
  routes:                         # how the app is reached; see Routing
    - { service: syncthing, name: syncthing, upstream-port: 8384 }
```

**Mirror the same values in an `x-casaos` block.** Maison reads `x-compose-app` and ignores
`x-casaos` when both are present. CasaOS, and Maison builds older than `x-compose-app`-only
support, read only `x-casaos`, and an app without it disappears from their catalog. Keep the
two blocks equal:

| `x-compose-app` | `x-casaos` |
|---|---|
| `id` | `store_app_id` |
| `title`, `tagline`, `description`, `developer`, `category`, `icon`, `thumbnail`, `architectures` | same names |
| `screenshots` | `screenshot_link` |
| `tips` | `tips.before_install` |
| `routes` (the first one) | `hostname` (`<name>-${domain}`) / `index` (its `path`) |
| — | `webui_port` (the exposed web UI port) |
| — | `main` (the first route's service; CasaOS only, Maison does not read it) |
| `requires: [public-ip]` | `tags: [..., "needs-public-ip"]` |
| `resources` | — (`min_memory`, in MB, is the closest; prefer `resources`) |
| — | `tags` (topical tags have no `x-compose-app` key) |

Rules:

- **Don't raise `schema_version` above 2.** A Maison build that predates the declared version
  drops the whole `x-compose-app` block, including `folders` and `secrets`.
- Don't write the per-service `x-casaos.envs` / `volumes` / `ports` / `devices` description
  lists. Nothing reads them. Anything the user must know goes in `description`, `tips` or
  `rationale.md`.
- `requires` and `resources` are described in [Requirements](#requirements). `min_memory` (MB)
  is superseded by `resources.min.memory`.

Field reference: [Maison `x-compose-app.md` › Fields](https://github.com/Yundera/Maison/blob/main/docs/x-compose-app.md#fields).

### System variables

*Requirements:* `portable-references`

Maison writes these into the app's `.env` at install and refreshes them on every start.
Maison never edits your compose file, so a variable reaches your app only if your compose
references it.

| Variable | Value |
|---|---|
| `APP_NET` | The shared network apps join (`pcs` on a PCS). Always write `${APP_NET:-pcs}`. |
| `DATA_ROOT` | The data folder as the **Docker host** sees it, normally `/DATA`. Always write `${DATA_ROOT:-/DATA}` as the prefix of every bind source. |
| `APP_DOMAIN` | The domain root, e.g. `alice.nsl.sh`. Use it for what is really the domain (`admin@${APP_DOMAIN}`), not to spell the app's own address. |
| `APP_URL` / `APP_HOST` | The app's own address: an origin (`https://myapp-alice.nsl.sh`, no trailing slash) and its host. Set by a Maison that knows the app's routes, so always write it with today's spelling as the fallback: `${APP_URL:-https://myapp-${APP_DOMAIN}}`. See `own-address` in CONTRIBUTING. |
| `ROUTE_<NAME>_URL` / `ROUTE_<NAME>_HOST` | The same for each further host the app routes (`hubsassets` → `ROUTE_HUBSASSETS_HOST`). |
| `APP_PUBLIC_IP_DASH` | The public IPv4 with dashes, as the box's IP-based domains spell it. |
| `APP_EMAIL` | The admin email, `admin@<domain>`. |
| `AppID` | The app's compose `name`. |
| `PUID` / `PGID` | The owner of user files, usually `1000:1000`. |
| `TZ` | The system timezone. |
| `APP_DEFAULT_PASSWORD` | **Legacy, do not use.** One password shared by every app on the box. Installed apps keep it; new apps declare their own [secrets](#3-credentials). |

`APP_NET` and `DATA_ROOT` differ between deployments, so writing them as references keeps
the app portable. The `:-default` keeps a hand-run `docker compose up` working before
Maison has written a `.env`. In this document, `/DATA/...` is shorthand for the data folder.
In a bind source, always write the variable.

```yaml
services:
  myapp:
    environment:
      BASE_URL: ${APP_URL:-https://myapp-${APP_DOMAIN}}
      TZ: $TZ
    volumes:
      - ${DATA_ROOT:-/DATA}/AppData/$AppID/data:/app/data
```

Full list and precedence: [Maison `app-env.md`](https://github.com/Yundera/Maison/blob/main/docs/app-env.md).

## Data and permissions

*Requirements:* `data-under-datadir` `permissions` `state-persistence` `broad-mount-disclosure`

```
/DATA/
├── AppData/
│   └── <app>/          # the app folder: docker-compose.yml, .env, and all app data
├── Documents/          # user files, owned by PUID:PGID
├── Downloads/
├── Gallery/
└── Media/
```

**The app folder** (`/DATA/AppData/<app>/`) holds the compose, its `.env` and every byte of
app state: config, databases, caches. It is what Maison backs up, archives on uninstall and
restores. Map all persistent data into it.

**User folders** (`Documents`, `Downloads`, `Gallery`, `Media`) are browsed and edited by
people. Anything an app writes there must be owned by `PUID:PGID` and have readable names.

### `user:`

Maison does not rewrite your compose, so a service with no `user:` runs as whatever its
image says, often root. Say what you mean:

| The service writes to | Use |
|---|---|
| A user folder (alone, or together with its app folder) | `user: $PUID:$PGID`. Mandatory. |
| Only its own app folder | `user: $PUID:$PGID` preferred, so the owner can edit the config. Root is acceptable. |
| Needs root and also writes to user folders | Split it into two services, or justify it in `rationale.md`. |

A directory the app needs before its first start must be declared under
[`folders`](#folders) so it exists with the right owner. Otherwise Docker creates a missing
bind source as an empty root-owned directory, and an app running as `PUID:PGID` then gets
"permission denied" on first start.

```yaml
services:
  filemanager:
    image: filebrowser/filebrowser:v2.63.2
    user: $PUID:$PGID
    volumes:
      - ${DATA_ROOT:-/DATA}/AppData/$AppID/config:/config
      - ${DATA_ROOT:-/DATA}/Documents:/srv/documents
      - ${DATA_ROOT:-/DATA}/Media:/srv/media:ro      # read-only when the app only reads
```

### Persistence

- **Reinstall must reuse existing data.** Every step that creates a default must first check
  whether the data already exists. Use `seed/` (create-if-absent), or a [step](#5-imperative-work-steps)
  guarded on the data itself (`[ -e "$APP_DIR/…" ] && exit 0`).
- **Container startup must never erase or overwrite user data.**
- **Upgrades must not corrupt or downgrade data.** The store serves only the latest version, so
  a user can jump several releases in one update. If the image cannot convert the data on its
  own, ship a [data migration](#version-data_version-and-migrations).

## Resources

*Requirements:* `cpu-shares` `log-limits`

**`cpu_shares` is mandatory on every service.** It is a relative weight that only matters
under load, and it is a top-level service field (not under `deploy:`):

| Weight | Use for | Examples |
|---|---|---|
| 100 | Reserved for the system | — |
| 90 | Admin tools that must stay responsive | dashboards, monitoring |
| 80 | Interactive web front ends, proxies, AppShield sidecars | most web UIs |
| 70 | Interactive apps with heavy background work | Nextcloud, databases behind an interactive app |
| 50 | Default | most services |
| 30 | Background services | backup jobs, schedulers |
| 20 | Heavy batch work | ML inference, transcoding |
| 10 | Reserved for system maintenance | — |

**A memory limit is recommended on every service.** It stops one misbehaving app from
pushing the whole box into swap. Size it from observed use with headroom, rather than from
the image's documentation.

```yaml
services:
  myapp:
    image: myapp:1.2.3
    cpu_shares: 80
    deploy:
      resources:
        limits:
          memory: 512M
```

**A log limit is mandatory on every service.** Docker's default `json-file` log never
rotates, and the PCS sets no host-wide default: the limit has to be in the compose. Declare
it once as an `x-logging` anchor before `services:` and reference it from each service. Keep
`max-size` meaningful on its own: Podman honours it but may ignore `max-file`. Raise it only
for an app whose logs you need to keep, and say why in a comment.

```yaml
x-logging: &logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"

services:
  myapp:
    image: myapp:1.2.3
    cpu_shares: 80
    logging: *logging
```

## Routing: `routes` and the shared network

*Requirements:* `routes-wiring` `container-name`

A listing says **what** is reachable, never **how**. Each host the app answers on is one entry of
`x-compose-app.routes`; the box's routing setting decides the rest, and Maison writes it — on a
Yundera PCS, Caddy labels on every domain the box has (its own, nip.io, sslip.io, the ip zone);
at home, a published port; behind someone else's proxy, nothing but a route table. So a listing
carries no proxy label, no domain and no TLS setting.

```yaml
name: immich
services:
  immich:
    image: ghcr.io/immich-app/immich-server:v1.135.3
    container_name: immich
    expose:
      - 2283
    networks:
      - pcs
      - immich-internal
  immich-db:
    image: postgres:16.13-alpine
    container_name: immich-db
    networks:
      - immich-internal       # never on pcs: only its siblings talk to it

networks:
  pcs:
    name: ${APP_NET:-pcs}
    external: true
  immich-internal:
    driver: bridge

x-compose-app:
  routes:
    - { service: immich, name: immich, upstream-port: 2283 }

x-casaos:
  main: immich
  webui_port: 2283
```

| Field | Meaning |
|---|---|
| `service` | The service that answers. Default: the only service. |
| `name` | The host's leading label (`immich` → `immich-alice.nsl.sh` on a PCS). Default: the app id. |
| `upstream-port` | The port **inside** the container. Must be in its `expose:`. |
| `path` | Where the web UI opens (`/webui/`), for the first route. Default `/`. |
| `upstream-scheme`, `insecure-upstream` | `https` and `true` for a backend that only speaks self-signed HTTPS. |

The rules that must hold together:

- The **first route is the web UI**: the tile opens it, and its address is `APP_URL`. There is
  no `webui-host` / `webui-path` beside `routes`.
- `x-casaos.main` names the first route's service, and `x-casaos.webui_port` its port. CasaOS
  takes the app's identity and health from it; Maison does not read it.
- Every service attached to `pcs` sets `container_name`: lowercase letters, digits and `-`,
  not starting with a digit. The proxy resolves the upstream by container name.
- A route's name starts with the app id. Never take a name the platform uses itself: `auth`,
  `local-auth`, `auth-console`, `mesh-console`, `maison`, `admin`.
- Any port works. The URL stays clean whatever the backend port is.

An app that serves more than one hostname (its own Dex, for example) gives each its own route
(`Apps/Outline`); a route other than the first reads its address back as `ROUTE_<NAME>_URL`.
Anything beyond host → one port — dispatch by path, an auth hook, a redirect, a header fix —
is the app's own nginx router (`in-app-router` in CONTRIBUTING; `Apps/Seafile`,
`Apps/Vaultwarden`).

### Shared-network hygiene

*Requirements:* `network-isolation`

`pcs` is one flat network shared by every app on the box, and so is its DNS: service names and
container names resolve across apps. Two apps that each attach a service called `db` can
cross-resolve, and one app's web tier can end up talking to another app's database.

- **Attach only what needs outside reachability**: route services, and anything
  another app talks to. Databases, caches and workers go on an app-internal
  `driver: bridge` network.
- **Prefix what you attach**: use `outline-dex`, not `dex`, for both the service name and
  `container_name`.

## Publishing host ports

*Requirements:* `no-published-web-port`

`expose:` covers every HTTP port. **Never publish a web UI port.** The platform's proxy already
reaches the container over `pcs`, so a published UI port is a second way in that skips the certificates
and the login gate. On an AppShield app, never publish the backend's HTTP port.

**`ports:` is legitimate for traffic an HTTP proxy cannot carry**, when peers or clients must
dial the box directly:

| App | Published | Why |
|---|---|---|
| `Apps/Crafty` | `25500-25600/tcp`, `19132/udp` | Minecraft Java + Bedrock |
| `Apps/Factorio` | `34197/udp` | Factorio multiplayer |
| `Apps/Hubs` | `40000-40050/tcp+udp` | WebRTC media |
| `Apps/Kubo` | `4001/tcp+udp` | IPFS swarm |
| `Apps/MetaWatch` | `4003/tcp`, `4004/tcp` | libp2p (share, search) |
| `Apps/Radicle` | `8776/tcp` | Radicle peer-to-peer |
| `Apps/WireGuardEasy` | `51820/udp` | WireGuard |
| `Apps/AnnasTorrents` | `6881/tcp+udp` | BitTorrent peers + DHT |
| `Apps/qBittorrent` | `6881/tcp+udp` (commented out) | same, but the client works without it |

Samba publishes nothing by default: SMB belongs on a VPN address, which the owner adds through
the app's override.

- Publish **only** the non-HTTP ports, and add a comment beside each one saying what it is for.
- Use fixed ports that stay clear of the host's own (`22`, `80`, `443`). Two apps that publish
  the same port cannot run side by side.
- A published port is open to the internet with no SSO in front. Make sure nothing else the
  container listens on is reachable through it.
- **Ship the port enabled if the app needs it to work.** Comment it out only when it is a pure
  enhancement, and say in `tips` what to uncomment.

## Requirements

*Requirements:* `requires-public-ip` `resources-declared` `architectures`

What the app needs from the box. Maison uses it to decide what the store shows on each box:

```yaml
x-compose-app:
  architectures: [amd64, arm64]
  requires: [public-ip]               # public-ip | gpu-nvidia | gpu-dri
  resources:
    min:         { memory: 2G }       # only for a real floor
    recommended: { cpu: 2, memory: 4G }
```

- **`requires`** lists what the app **cannot work without**. Maison hides the app on a box
  that lacks one, and asks the owner to confirm before installing it anyway.
  - `public-ip`: inbound connections from the internet reach the host. A PCS behind CGNAT, or
    one routed through the mesh-router WireGuard tunnel, gets its HTTPS routes from the gateway
    but has no reachable address for raw TCP/UDP. There the app installs and starts, then
    quietly fails: a torrent client with no inbound peers, a game server nobody can join. Every
    app that publishes a port on every address needs it, and `maison lint` checks this.
  - `gpu-nvidia`: the app reserves an NVIDIA GPU (`deploy.resources.reservations.devices`).
  - `gpu-dri`: the app needs `/dev/dri` for video acceleration.
  - An app that only runs **better** with something lists nothing. A media server that falls
    back to CPU transcoding does not `require` a GPU.
- **`resources`** states the box the app wants, in compose sizes (`512M`, `4G`).
  - `recommended`: below it the store shows a note. Declare it on any app whose service limits
    add up to 2G or more, or that has an uncapped service. Base it on those limits plus the
    `rationale.md` notes.
  - `min`: below it, installing asks for confirmation. Set it only for a floor the app
    documents, such as Immich's 4G.
- Keep the CasaOS mirror: `needs-public-ip` stays in `x-casaos.tags`. CasaOS shows it, and a
  Maison that reads only `x-casaos` translates it to `requires: [public-ip]`.

## Authentication

*Requirements:* `auth-default` `appshield-wiring`

A login gate enabled by default is **mandatory**. Acceptable gates:

- **AppShield** (recommended): an SSO sidecar that plugs into the PCS's built-in login.
- The app's own login, protected by a [generated credential](#3-credentials).
- An onboarding flow that creates the first account on first visit (e.g. Jellyfin). This
  needs a `rationale.md` explaining why the window before the first account is created is
  acceptable: that the app's own login is mandatory once the account exists, why no
  credential can be generated for it, and what happens to a later sign-up (refused, or held
  for the admin's approval). `Apps/UptimeKuma` and `Apps/Ollama` are examples.

What `auth-default` asks is that a login is **there** as shipped, not who provides it. An app
whose own login is mandatory does not need AppShield in front of it as well.

A public website with no login also needs a `rationale.md`.

### AppShield

Put the `ghcr.io/yundera/appshield` container in front of the app. Make the sidecar the route's
service and keep the backend off the routes. The sidecar registers itself as an
OIDC client with the PCS's `auth-registrar` on first login, so there are no client IDs,
secrets or issuer URLs to configure.

References: `Apps/Spliit` (plain web UI), `Apps/Beacon` and `Apps/BrowserMCP` (MCP servers
with OAuth for machine clients).

```yaml
name: myapp
services:
  myapp-proxy:
    image: ghcr.io/yundera/appshield:3.2.0
    container_name: myapp        # = the compose name; the OIDC client id derives from it
    hostname: myapp              # = container_name; the registrar names the app from it
    restart: unless-stopped
    environment:
      BACKEND_HOST: "myapp-backend"
      BACKEND_PORT: "8080"
      LISTEN_PORT: "80"
      OIDC_REGISTRAR_URL: "http://auth-registrar:9092"
      REDIRECT_HOST_SUFFIXES: "${APP_HOST_SUFFIXES:-${APP_DOMAIN}}"
    expose:
      - 80
    depends_on:
      - myapp-backend
    cpu_shares: 80
    deploy:
      resources:
        limits:
          memory: 128M
    networks:
      - pcs                      # the proxy reaches the sidecar
      - myapp-internal           # the sidecar reaches the backend

  myapp-backend:
    image: myapp/myapp:1.2.3
    container_name: myapp-backend
    restart: unless-stopped
    expose:
      - 8080                     # no route, no ports: reachable only through the sidecar
    cpu_shares: 50
    deploy:
      resources:
        limits:
          memory: 512M
    networks:
      - myapp-internal

networks:
  pcs:
    name: ${APP_NET:-pcs}
    external: true
  myapp-internal:
    driver: bridge

x-compose-app:
  routes:
    - { service: myapp-proxy, name: myapp, upstream-port: 80 }

x-casaos:
  main: myapp-proxy              # the sidecar, never the backend
  webui_port: 80
```

| Variable | Required | Purpose |
|---|---|---|
| `BACKEND_HOST` / `BACKEND_PORT` | yes | The protected container's name and port. |
| `LISTEN_PORT` | yes | The port AppShield listens on. Matches `expose` and the route's `upstream-port`. |
| `OIDC_REGISTRAR_URL` | yes | `http://auth-registrar:9092`. Its presence enables SSO. |
| `REDIRECT_HOST_SUFFIXES` | yes | The primary domain only, as above. The gate sends the registrar its callback path and adopts the hosts the registrar returns, so it does not need — and must not guess — the platform's other zones. This one names the canonical host: the OAuth issuer, and where a login from an unrecognised host is sent. |
| `OAUTH_RESOURCE` | optional | Enables AppShield's OAuth 2.1 broker on exactly the path in the URL (e.g. `${APP_URL:-https://myapp-${APP_DOMAIN}}/mcp`). This is the machine/API path for MCP servers. |
| `OAUTH_SCOPE` | optional | The scope the resource advertises (default `access`; MCP apps use `mcp`). |
| `OAUTH_DATA_DIR` | optional | Set to `/data/oauth` and bind-mount `${DATA_ROOT:-/DATA}/AppData/<app>/oauth` there, so registered clients survive redeploys. |

What a review checks for an AppShield app is `appshield-wiring` in
[CONTRIBUTING.md](CONTRIBUTING.md#appshield-wiring--the-sso-sidecar-is-wired-so-it-cannot-be-bypassed).
The two that catch people out are `hostname:` and `x-casaos.main`:

- `auth-registrar` identifies the app by its container's PTR record and rejects redirect URIs
  that don't match it. If `hostname:` is missing, Docker uses the random container ID and
  registration fails at first login. The service name itself may differ from the container name.
- If `x-casaos.main` names the backend, CasaOS takes the app's health from the backend: the
  tile can show green while the public route returns 502.

**Don't copy these from older apps:**

- `AUTH_HASH` / `/?hash=…`: a CasaOS-era token. Maison never generates it, so it resolves to
  an empty string.
- `ALLOWED_PATHS` for machine clients: with no hash, this leaves the path open to anyone. Use
  `OAUTH_RESOURCE`.
- `CREDENTIAL_VALIDATE_URL`: pointed at a CasaOS bridge that no longer exists.
- `USER` / `PASSWORD: $APP_DEFAULT_PASSWORD` as an extra basic-auth gate. If you need one, use
  an app [secret](#3-credentials).

On the PCS, `auth-registrar` and the login service run in the mesh template's `auth` stack.
If they are missing, the sidecar logs `ENOTFOUND auth-registrar` at first login.

## Maison and `x-compose-app`

`x-compose-app` is Maison's definition of an app. Maison reads **one block or the other,
never both**:

```
compose has x-compose-app  →  x-compose-app only (x-casaos beside it is ignored)
otherwise                  →  x-casaos, translated whole (plain CasaOS apps)
```

So a field that exists only in this store's `x-casaos` block is invisible to Maison. That is
why [store info](#store-info) lives in `x-compose-app` first.

Declare `schema_version: 2`, which `folders` and `steps` require. The other keys (`secrets`,
`variables`, `credentials`, `files`, `lifecycle`, `backup`, `migrations`) are
additive and don't raise it.

### The stack-up sequence

**Every** `docker compose up` Maison runs goes through this sequence: install, start, update,
and saving the app's settings:

```
folders → secrets → variables → setup steps → seed → files
        → docker compose up -d → started steps
```

An update that raises `data_version` also runs each pending [migration](#version-data_version-and-migrations)
once, between `variables` and the setup steps.

An install is this same sequence: nothing runs only on install. Work for a fresh install is a
`run: once` [step](#5-imperative-work-steps).

Everything before `docker compose up` is **fatal**: an app whose secret could not be
generated, whose config could not be rendered, or whose setup step failed, does not start.
A failing started step is logged and retried on the next up.

Reference: [`x-compose-app.md` › The stack-up sequence](https://github.com/Yundera/Maison/blob/main/docs/x-compose-app.md#the-stack-up-sequence).

### `folders`

*Requirements:* `declared-folders`

```yaml
x-compose-app:
  schema_version: 2
  folders:
    - /DATA/AppData/$AppID/config            # shorthand: owner PUID:PGID, mode 0755
    - path: /DATA/AppData/$AppID/db
      user: "999"
      group: "999"
      mode: "0700"                           # must be quoted
    - path: /DATA/Media
      recursive: true                        # also re-own what is already inside
```

Maison creates each folder with its owner before any image is pulled and before every up.
It does **not** read `volumes:` to guess which bind sources are directories, so a directory
your app needs is a directory your app declares. Paths are written with `/DATA`, which Maison
maps itself. A relative path, a path outside `/DATA`, or a variable that resolves to nothing
fails the up. Use `recursive: true` only to reclaim a tree the app did not create, and never
on a large media folder that is already correct.

Reference: [`x-compose-app.md` › Folders](https://github.com/Yundera/Maison/blob/main/docs/x-compose-app.md#folders).

### First-run setup

Prefer the first option that fits, in this order.

#### 1. Files: `seed/`

`Apps/<AppName>/seed/` mirrors the app folder. Maison copies it at install and writes each file
**create-if-absent on every up**. A missing file comes back; a file the app or the user edited
is left alone.

```
Apps/MyApp/seed/config/init.sql       → /DATA/AppData/myapp/config/init.sql
Apps/MyApp/seed/config/app.yml.tmpl   → /DATA/AppData/myapp/config/app.yml   (rendered)
```

A `.tmpl` file is rendered with the app's variables, and an unresolved `${VAR}` fails the
install. Other files are copied byte-for-byte, keeping the exec bit. `docker-compose.yml`, the
override and `.env` may not appear in `seed/`. Seed files replace fetching assets from
jsDelivr: the store is already on the box.

#### 2. Values: `secrets` and `variables`

*Requirements:* `no-hardcoded-credentials` `per-app-secrets`

```yaml
x-compose-app:
  secrets:                                          # generated once, kept forever
    MYAPP_SECRET_KEY: hex:32
    MYAPP_DB_PASSWORD: alnum:32                     # internal, nobody types it
    MYAPP_ADMIN_PASSWORD: password:24               # a person logs in with it
    MYAPP_ADMIN_HASH: bcrypt:${MYAPP_ADMIN_PASSWORD}
  variables:                                        # re-rendered on every up
    MYAPP_URL: ${APP_URL:-https://myapp-${APP_DOMAIN}}
```

The generators are `hex:N`, `base64:N`, `alnum:N`, `password:N`, `uuid` and `bcrypt:TEXT`.
A secret is written to the app's `.env` once and survives restarts, updates and restores.
Use **one secret per purpose**: the database password is never the login password.

Never generate a credential in a step: declare it under `secrets`. A key no generator can
produce (an RSA keypair) is the exception; see `Apps/Wger`.

**Converting an app that used `$APP_DEFAULT_PASSWORD`.** Installed boxes already initialised
their database with that value, so a fresh secret would not match it. Seed the secret from the
old value instead:

```yaml
  secrets:
    MYAPP_DB_PASSWORD: ${APP_DEFAULT_PASSWORD}|alnum:32
```

Installed apps keep their value; fresh installs get a generated one.

Reference: [`x-compose-app.md` › Secrets and variables](https://github.com/Yundera/Maison/blob/main/docs/x-compose-app.md#secrets-and-variables).

#### 3. Credentials

*Requirements:* `credentials-shown`

Show the login Maison generated. It appears, masked and with copy buttons, the first time the
app is opened and from its tile menu:

```yaml
x-compose-app:
  credentials:
    - label: Administrator
      username: admin
      password: ${MYAPP_ADMIN_PASSWORD}
      change:
        apply: script
        script: |
          compose exec -e MYAPP_ADMIN_PASSWORD myapp \
            myapp-cli user set-password admin
```

Add `change` when the password can be replaced after install. The owner then changes it from
the app's **Security** tab in Maison:

- `apply: env`: the app re-reads the variable on **every** start. Maison writes `.env` and
  recreates the container. If the value only reaches a container through a rendered file, give
  that container a label carrying the secret so the recreate happens (`Apps/Outline`,
  `Apps/Filestash`).
- `apply: script`: the app keeps its own copy (a user table) but has a command to change it.
  The [script entry](#the-script-entry) runs against the running app and gets the **new**
  value in the secret's own variable (`OLD_<NAME>` holds the previous one). Pass it with the bare `-e NAME` form so it
  never appears on a command line, and exit non-zero when nothing changed (`Apps/Nextcloud`,
  `Apps/Guacamole`, `Apps/WireGuardEasy`).
- No `change`: the value is read only at first boot and nothing can reset it.

`change.policy` (length, charset, required classes) is optional. Only a value declared under
`secrets` can be changed.

`tips` no longer needs a password table.

Reference: [`x-compose-app.md` › Changing a credential](https://github.com/Yundera/Maison/blob/main/docs/x-compose-app.md#changing-a-credential).

#### 4. A file that tracks the deployment: `files`

`seed/` is create-if-absent. When a config embeds a value that can change, such as a domain,
declare it so it is re-rendered on every up:

```yaml
x-compose-app:
  files:
    - path: /DATA/AppData/myapp/element/config.json
      from: element/config.json.tmpl    # a path in seed/
      ensure: always                    # `once` (default) = create-if-absent
      mode: "0640"
```

#### 5. Imperative work: `steps`

*Requirements:* `step-idempotency` `step-security` `step-scope`

What is left once the four declarations above are used: work that needs the app's own binary
(seeding its database), a running service (an API call, `occ`), another program's output
(waiting for it to write its config, then patching it), or the host.

```yaml
x-compose-app:
  steps:
    - name: init-db
      at: setup            # setup | started
      run: always          # once (default) | always
      script: |
        [ -e "$APP_DIR/db/database.db" ] && exit 0
        docker run --rm --user "$PUID:$PGID" -v "$APP_DIR/db:/db" \
          filebrowser/filebrowser:v2.63.23 config init --database /db/database.db
    - name: configure
      at: started
      run: once
      script: |
        compose exec nextcloud php occ background:cron
```

| `at` | Runs | On failure |
|---|---|---|
| `setup` | Before the stack starts: after `secrets` and `variables`, before `seed` and `files`. | **fatal**: the app does not start |
| `started` | After `docker compose up` returns. The containers have started; the app may still be booting, so wait for it. | logged; retried on the next up |

| `run` | |
|---|---|
| `once` | Until it succeeds once. The marker is `.init/<name>` in the app folder, so it travels with the backup, but an uninstall-keep-data removes it. When the step must follow the *data*, use `always` and guard on the data. |
| `always` | On every up: install, start, update, config save. It must be idempotent. |

Steps run in the order written, `setup` ones first.

#### The script entry

A step, a [migration](#version-data_version-and-migrations) step and a
[credential change](#3-credentials) all run the same thing: a **script entry**, through the
same runner. Only *when* it runs differs. What a script can do in one place, it can do in the
other two.

| Key | |
|---|---|
| `script` | Inline bash. |
| `file` | Instead of `script`: a `.sh` under the app's `scripts/` folder (`file: scripts/patch.sh`), copied with the app on install and update. For anything long enough to want its own file and `shellcheck`. |
| `images` | Images the script runs, pulled with the app's own images before anything is stopped. Optional; required in practice for a migration, which runs after the stop. |
| `timeout` | Go duration. Defaults: step 10m, migration 2h, credential change 2m. |

| In | Its own keys | Runs | On failure | Extra variables |
|---|---|---|---|---|
| `steps` | `name`, `at`, `run` | every up | `setup`: the app does not start. `started`: logged, retried | — |
| `migrations` | `id`, `name` (or `blocked`) | once, in the update that crosses `id` | the update is rolled back | `MIGRATION_ID`, `DATA_VERSION_FROM`, `DATA_VERSION_TO` |
| `credentials[].change` | `apply: script`, `policy` | when the owner changes the password | nothing changes | `<NAME>` (the new value), `OLD_<NAME>` |

`MAISON_OUTPUT` and `MAISON_ENV` (below) exist in all three places. `$MAISON_ENV` always
reaches the `.env`; `$MAISON_OUTPUT` reaches whatever runs or renders after the script in
the same up, so it has no reader in a credential change.

**Where a script runs.** `bash -euo pipefail` **inside the Maison container**, in the app folder,
with `docker` talking to the **host** daemon. The environment holds the app's `.env`, the
[system variables](#system-variables), `AppID`, `APP_DIR` (the app folder), `DATA_ROOT`,
`COMPOSE_PROJECT_NAME` / `COMPOSE_FILE`, `MAISON_OUTPUT` / `MAISON_ENV`, and the extra
variables above. The script is not interpolated: write `$VAR`, never `$$VAR`.
Don't use `${VAR:?}`, which `docker compose` rejects when it reads the file.

**Paths.** Maison mounts `DATA_ROOT` at the same path the host uses, so `$APP_DIR/db` is
right both for the shell (`[ -e … ]`, `cat`) and for `docker run -v`. Write `$APP_DIR`, not
`/DATA/AppData/<app>`.

**Talking to the app.** `compose` is `docker compose` bound to the app's project:
`compose exec <service> …`, `compose restart <service>`. `exec` never allocates a TTY and
passes stdin, so `printf … | compose exec database psql …` works.

**Running a tool in an image.** Pass values with `-e`, never by splicing them into the inner
script, and quote the heredoc so nothing is expanded twice:

```bash
docker run --rm -i --entrypoint sh --user "$PUID:$PGID" \
  -v "$APP_DIR/config:/out" -e CRAFTY_ADMIN_PASSWORD \
  registry.gitlab.com/crafty-controller/crafty-4:4.10.7 -s <<'SH'
set -e
printf '{"password":"%s"}' "$CRAFTY_ADMIN_PASSWORD" > /out/default.json
SH
```

**Ownership.** A file written from the script's own shell belongs to Maison's user. Appending
(`>>`) keeps the owner; `sed -i`, `>` on a new file and `mv` don't. Edit a file the app owns
from a container run as `--user "$PUID:$PGID"`, or inside the app with `compose exec`.

**Handing values on.** Write `KEY=value` lines to one of two files:

| File | Reaches | Lifetime |
|---|---|---|
| `$MAISON_OUTPUT` | later steps, `.tmpl` files and `files` | this up only; recomputed next time |
| `$MAISON_ENV` | the app's `.env`, so the compose and every later up | kept. **Adds a key only when the `.env` lacks it**, so a user edit or a generated keypair is never overwritten. |

```bash
hash=$(printf 'admin:YaCy:%s' "$YACY_ADMIN_PASSWORD" | md5sum | cut -d' ' -f1)
echo "YACY_ADMIN_HASH=$hash" >> "$MAISON_OUTPUT"   # used by seed/…/yacy.conf.tmpl
echo "RADICLE_OWNER=" >> "$MAISON_ENV"             # an empty setting shown in App settings › Env
```

Assign a command substitution to a variable first, as above: `set -e` catches a failed
`hash=$(…)`, not a failed `echo "$(…)"`.

**Commands.** Only a fixed set is available (`bash`, `docker`, `compose`, coreutils, `sed`,
`grep`, `find`, `md5sum`, `wget`, …). `openssl`, `curl`, `python`, `jq` and `git` are not: run
them in a pinned image. Host-scoped commands (`sysctl`, `ip`, `mount`, …) would only affect the
Maison container, so they are refused.

**Changing the host** goes through the Docker socket. Pin the image, and justify it in
`rationale.md`:

| To change | Recipe |
|---|---|
| Kernel parameters | `docker run --rm --privileged --network=host <image> sysctl -w <key>=<value>` |
| Network state | `docker run --rm --privileged --network=host <image> ip ...` |
| Files, users, `/etc` | `docker run --rm -v /:/host <image> chroot /host sh -c '...'` |
| Kernel modules | `docker run --rm --privileged <image> modprobe ...` |

**CasaOS.** `pre-install-cmd` / `post-install-cmd` run only for a compose with no
`x-compose-app`, as a `setup` / `started` step with `run: once`.

Worked examples: `Apps/FileBrowser` (a tool in an image), `Apps/Gitea` (`compose exec` and
waiting for the app), `Apps/YaCy` and `Apps/SeafileDrive` (`$MAISON_OUTPUT`), `Apps/Wger` and
`Apps/Hubs` (`$MAISON_ENV`), `Apps/Seafile` (patching what the app wrote),
`Apps/WireGuardEasyHost` (the host, and a step in a `file:`).

A shipped step is reviewed against `step-idempotency`, `step-security` and `step-scope`
in [CONTRIBUTING.md](CONTRIBUTING.md#4-first-run-setup-and-steps).

Reference: [`x-compose-app.md` › Steps](https://github.com/Yundera/Maison/blob/main/docs/x-compose-app.md#steps).

### The tile: `links`, `view`, `parent`

```yaml
x-compose-app:
  links:                        # extra buttons on the detail view, absolute URLs
    - name: Documentation
      url: https://docs.example.org
  view: service                 # apps (default) | service | system — the grid, nothing more
  parent: jellyfin              # nest this app under another app's tile
```

- The tile opens the first route (`routes`, under Routing) at its `path`. An app with no web
  UI declares no route.
- An app with no web UI lands in `service` on its own. Leave `view` alone unless the app is a
  platform piece, such as Terminal, the owner's host shell. A platform piece is `system` whether it
  ships preinstalled or comes from the store. Say why in `rationale.md`.
- `parent` is for apps that only make sense beside another one, such as a companion indexer or
  a request front end. It is presentation only. If the parent is not installed, the app shows
  as an ordinary tile.

Reference: [`x-compose-app.md` › Views](https://github.com/Yundera/Maison/blob/main/docs/x-compose-app.md#views).

### `lifecycle`

*Requirements:* `lifecycle-rationale`

```yaml
x-compose-app:
  lifecycle:
    stoppable: false      # Stop refused; updated without stopping; left out of "Update all"
    uninstallable: false  # Uninstall refused
    updatable: false      # outside Maison's update system entirely
```

All three default to `true`. They exist for platform stacks: the dashboard, the gateway, an
admin app that something other than Maison keeps up to date. **A store app needs a
`rationale.md` entry to set any of them to `false`.** An app the user cannot stop, remove or
update is a review question, not a default.

Reference: [`x-compose-app.md` › Lifecycle](https://github.com/Yundera/Maison/blob/main/docs/x-compose-app.md#lifecycle-what-the-operator-may-do-to-the-app).

### Backups

Maison backs up the app folder whole. Declare regenerable data so it isn't copied off-box every
night:

```yaml
x-compose-app:
  backup:
    exclude:
      - cache/                  # <app folder>/cache
      - data/transcodes/
      - "**/thumbs/"            # any depth; must be quoted
```

An excluded directory comes back **empty** after a restore, so list only what the app rebuilds
by itself, and declare it in `folders` if it must exist before start. Only directories are
accepted: no file globs, no negations, nothing outside the app folder.

`backup.skip: true` drops the app from backups entirely. Use it only when nothing in its folder
is worth keeping.

Reference: [`x-compose-app.md` › Backup exclusions](https://github.com/Yundera/Maison/blob/main/docs/x-compose-app.md#backup-exclusions).

### `version`, `data_version` and migrations

*Requirements:* `migrations-wellformed` `migration`

```yaml
x-compose-app:
  version: "2.4.0"      # optional, display only
  data_version: 2       # only once the app needs its first migration
  migrations:
    - id: 2
      name: postgres-15-to-17
      image: pgautoupgrade/pgautoupgrade:17.6-trixie
      environment:
        PGAUTO_ONESHOT: "yes"
        POSTGRES_USER: myapp    # = the postgres service's user; the default `postgres` fails
        POSTGRES_DB: myapp
      volumes:
        - /DATA/AppData/${AppID}/db:/var/lib/postgresql/data
```

**`version`** is optional and only displayed. Updates are detected from the compose file,
not from this field. If you set it, use the main app's image tag without a leading `v` or
variant suffix (`ghost:6.59.0-alpine` → `"6.59.0"`), quote it, and keep it in step with the tag.
For an AppShield app, use the backend's version.

**`data_version`** is the shape of the app's data: an integer that starts at 1 and rises by
exactly one per migration. Leave it out until the first migration is needed (absent means 1).

**Most updates need no migration**, because the image converts its own data on first start.
Ship one when it can't: a PostgreSQL major version, Odoo 18 → 19, a config file that moved, an
app that must boot every intermediate major version.

A step is exactly one of:
- a [script entry](#the-script-entry): `script:` inline, or `file: scripts/0002-….sh`, with
  every image it runs listed under `images:` so they are pulled while the old version still
  serves (`Apps/Guacamole`: one `docker run` of pgautoupgrade; `Apps/Odoo`: a file);
- **`blocked:`** (a message; the update is refused before anything is pulled).

Store rules:

- **Every install today starts at data version 1**, whatever version it runs: no install had a
  marker before migrations existed. So a step must **read the data and exit 0 when it is
  already converted**, the way `pgautoupgrade` checks `PG_VERSION`. Exit 0 means "applied";
  there is no "try next time".
- Use `blocked` only when the step lands together with the image bump that needs it. It cannot
  look at the data, so it would also refuse installs that are already converted. When old data
  cannot be converted automatically, use a script that checks and fails: the update is rolled
  back and the app keeps its old version. `Apps/Odoo` is the worked example (step 2 refuses
  Odoo 18 databases; step 3 is the `pgautoupgrade` above).
- **When to merge:** Maison runs steps from **v1.1.58**. Older builds ignore them and update
  straight onto the new image. So if the step lands **with** the image bump that needs it,
  wait until v1.1.58+ is on the fleet. If the store **already** ships the new image (a
  conversion that was missed), merge at once: the migration only adds protection.
- **The invariant to review against:** a fresh install at data version N must end up where an
  older install plus every migration up to N ends up. A change to what `seed/`, `files`,
  `folders` or a `run: once` step produce never reaches existing installs unless a migration carries it.

An update with pending steps always takes a rollback point, and is rolled back as a whole if
a step fails.

Reference: [Maison `migrations.md`](https://github.com/Yundera/Maison/blob/main/docs/migrations.md).

### Keys Maison writes itself

`store-ref` and `generated-routes` appear in an installed app's override file (older
installs may also carry `store` / `store-app-id`). Don't use those names for your own fields.

## Rationale (`rationale.md`)

An app that takes an exception ships `Apps/<AppName>/rationale.md`. Reviewers read it first.

It is required when the app:
- runs as root with access to user folders, or mounts anything outside `/DATA/AppData/<app>/`
  and the user folders;
- ships with no login enabled by default, or relies on first-visit onboarding;
- changes the host from a step;
- sets any `lifecycle` key to `false`;
- deviates from anything else in this document.

```markdown
# <AppName> — Rationale

## What exception is requested
<e.g. "runs as root", "no login", "mounts /DATA/Downloads read-write">

## Why it is necessary
<upstream constraint, runtime requirement, …>

## Mitigations
<resource limits, read-only mounts, disabled features, …>

## Alternatives considered
<each alternative and why it did not work>

## Data protection
<what protects user data given this exception>
```

Keep it short and factual. A reviewer should be able to decide in a minute.
`Apps/Stirling-PDF/rationale.md` is a full example.

## Images and languages

*Requirements:* `assets` `description`

Asset fields name files beside the compose (`icon: icon.png`, `screenshots: [screenshot-1.png]`).
Maison serves them from the store copy already on the box. An absolute URL still works but
is not the normal form.

| Image | Spec |
|---|---|
| `icon.png` | Required. 192×192, transparent background. |
| `screenshot-N.png` | At least one required. 1280×720, PNG or JPG, as small as possible. |
| `thumbnail.png` | Optional. 784×442 with a rounded-corner mask. Supply it only as a purpose-made tile; otherwise omit it and the store uses `screenshot-1.png`. Featured apps should have one. |

Use the [PSD templates](psd-source) to make these.

**Languages:** English (`en_us`) is mandatory for `title`, `tagline` and `description`. French
(`fr_fr`), Korean (`ko_kr`), Chinese (`zh_cn`) and Spanish (`es_es`) are recommended for
`tagline` and `description`.

## Feedback

Suggestions about this process are welcome via GitHub issues.
