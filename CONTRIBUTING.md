# Contributing to the AppStore — requirements

This is the checklist every app in the Yundera AppStore must pass. It is the reference a review
decides **go / no-go** on, whether the reviewer is a person or Touchstone, Yundera's
conformance agent. Each item has a stable ID, a severity, and the conditions for pass, fail and
n-a.

How to meet these requirements (conventions, worked examples, how Maison runs an app) is in
**[GUIDELINES.md](GUIDELINES.md)**. Recommendations there are not requirements.

## How an app is judged

Each requirement gets one verdict:

| Verdict      | Means                                                                                   |
| ------------ | --------------------------------------------------------------------------------------- |
| `pass`       | Checked, and it holds.                                                                  |
| `fail`       | Checked, and it does not. Always carries the severity given by the item.                |
| `n-a`        | The item cannot apply to this app, for the reason the item states. Never "not checked". |
| `unverified` | Could not be settled. Never counted as a pass.                                          |

**GO** means every applicable requirement is `pass`. **NO-GO** means any requirement is `fail`
or `unverified`. Severity ranks how urgent the fix is. It never waives one.

| Severity     | Used for                                                                                                                                               |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Critical** | Security or data loss: no or bypassable login, exposed credentials, undocumented privilege, state lost on reinstall.                                   |
| **Major**    | Breaks the store contract: the app cannot install, start or be reached as shipped, a required file is missing, or a load-bearing convention is broken. |
| **Minor**    | Hygiene: correct behaviour today, but wrong, fragile or misleading.                                                                                    |

**Exceptions.** Only an item that says *"`rationale.md` can cover it"* accepts an exception, and
only when `Apps/<AppName>/rationale.md` names that exact deviation and explains it (see
[GUIDELINES › Rationale](GUIDELINES.md#rationale-rationalemd)). A rationale that does not
describe the actual deviation covers nothing.

**Check** says how each item is settled: **static** items are read from the app's files,
**functional** items need the app installed on a PCS.

**Scope.** The app's files as they stand in the store: `docker-compose.yml`, its assets,
`seed/`, `scripts/` and `rationale.md`. "Every service" includes every service in the
compose. "Every image" includes migration steps and every `docker run` in a step.

**Service apps.** An app whose compose declares no web UI (no `x-compose-app.routes` entry and no
`webui-host`) is a **service app**: Maison puts its tile in the Services grid, and a click opens
its settings rather than a page. Samba is one. Items that need a web UI say so on their `n-a`
line, and a service app is reviewed on the rest.

---

## 1. Compose

### `name-regex` — the app ID is valid

**Check:** static · **Severity:** Major

- **Pass:** the top-level `name` matches `^[a-z0-9][a-z0-9_-]*$`, is unique in the store, and
  equals `x-compose-app.id` when `id` is set.

### `pinned-image-tag` — every image is pinned

**Check:** static · **Severity:** Major for a service image; Minor for a migration or step image

- **Pass:** every image names a specific version tag or digest.
- **Fail:** no tag, or a floating tag (`latest`, `main`, `master`, `stable`, `nightly`, a
  bare major such as `:16`).

### `portable-references` — the deployment's paths and network are references

**Check:** static · **Severity:** Major

- **Pass:** every bind source under the data folder is written `${DATA_ROOT:-/DATA}/…`, and the
  shared network is declared `name: ${APP_NET:-pcs}` with `external: true`.
- **Fail:** a bare `/DATA/…` bind source, a bare `name: pcs`, or a shared network with no `name:`.
- `folders`, `files` and `migrations` paths are written with `/DATA`, and steps use
  `$APP_DIR` / `$DATA_ROOT`; none are covered by this item.

### `cpu-shares` — every service has a CPU weight

**Check:** static · **Severity:** Minor

- **Pass:** every service sets `cpu_shares` as a top-level service field, with a value from the
  tiers in [GUIDELINES › Resources](GUIDELINES.md#resources).

### `log-limits` — every service has a bounded log

**Check:** static · **Severity:** Minor

- **Pass:** every service sets `logging:` with the `json-file` driver and a `max-size` option
  (and `max-file`), as in [GUIDELINES › Resources](GUIDELINES.md#resources). The shared
  `x-logging` anchor counts.
- **Fail:** a service with no `logging:`, or one with no `max-size`. Docker's default json-file
  log never rotates, so it grows until the disk is full.

### `architectures` — supported platforms are declared

**Check:** static · **Severity:** Minor

- **Pass:** `architectures` is declared and every image listed supports each architecture named.
  Maison refuses to install the app on a box of an architecture not listed, so a missing entry
  hides a working app and an extra one breaks an install.

### `resources-declared` — heavy apps say what they need

**Check:** static · **Severity:** Minor
**n-a:** the service memory limits add up to less than 2G, and no service is uncapped.

- **Pass:** `x-compose-app.resources.recommended` states the box the app wants (`memory`, and
  `cpu` when the app is CPU-bound). `resources.min` is set only for a floor the app really has.
  See [GUIDELINES › Requirements](GUIDELINES.md#requirements).

---

## 2. Routing and network

### `routes-wiring` — the app says what is reachable, never how

**Check:** static · **Severity:** Major
**n-a:** a service app.

A listing declares where it can be reached — `x-compose-app.routes`, one entry per host the app
answers on — and nothing about the proxy in front: the box's routing setting decides that
(labels for its proxy on a PCS, a published port at home, an external router elsewhere) and
Maison writes it. A route is `{ service, name, upstream-port }`, with `path` for where the web
UI opens, and `upstream-scheme: https` plus `insecure-upstream: true` for a backend that only
speaks self-signed HTTPS. Anything beyond host → one port is the app's own job
(`in-app-router`).

- **Pass:** all of the following hold:
  - `x-compose-app.routes` is declared, the web UI first;
  - no service carries a proxy label (`caddy*`, `traefik.*`), and `x-compose-app` has no
    `webui-host`, `webui-path`, `webui-port` or `webui-scheme` — `routes` replaces them;
  - each route's `upstream-port` is in its service's `expose:`, and the service is on the
    shared network;
  - each `name` is the app id or starts with it (`outline-auth`, `kubo-gateway`), unless the
    listing says why another name must be kept (Tuwunel's `matrix` identity);
  - `x-casaos.main` names the first route's service and `x-casaos.webui_port` its port, for
    CasaOS;
  - `maison lint` passes.
- **Fail:** any one of these is broken, or a route takes a name the platform uses itself
  (`auth`, `local-auth`, `auth-console`, `mesh-console`, `maison`, `admin`).

### `own-address` — the app learns its address from the platform

**Check:** static · **Severity:** Minor
**n-a:** nothing in the listing names one of the app's own hosts.

Where an app is reached is the deployment's choice: the box's domain today, a published port
or another router tomorrow. Maison tells each app its address, so a listing that names its
own host reads that value and keeps today's spelling only as the fallback for a Maison
that does not provide it yet.

- **Pass:** every one of the app's own hosts — in `environment:`, `files` and their seed
  templates, steps and tips alike — is written as:
  - the first route's: `${APP_URL:-https://<app>-${APP_DOMAIN}}` for a URL,
    `${APP_HOST:-<app>-${APP_DOMAIN}}` for a bare host;
  - any other route's: `${ROUTE_<NAME>_URL:-https://<name>-${APP_DOMAIN}}` /
    `${ROUTE_<NAME>_HOST:-<name>-${APP_DOMAIN}}`, `<NAME>` being the route's name upper-cased
    with `-` as `_` (`hubsassets` → `ROUTE_HUBSASSETS_HOST`);
  - a list of all of them (CORS or CSRF origins, trusted hosts):
    `${APP_URLS:-<today's addresses, comma-separated>}` or `${APP_HOSTS:-…}` (and
    `ROUTE_<NAME>_URLS` / `_HOSTS`), primary first. A consumer that wants another separator
    or a JSON array converts the comma list itself (`Apps/Kubo`, `Apps/Nextcloud`);
  - a step that passes these to a container names them with `-e`, or the container sees only
    the fallback (`Apps/SABnzbd`).

  `APP_URL` is an origin (`scheme://host[:port]`, no trailing slash): append the path after
  the closing brace, `${APP_URL:-https://gitea-${APP_DOMAIN}}/`. `APP_DOMAIN` stays fine for
  what is really the domain (`admin@${APP_DOMAIN}`), and another app's host is written as it
  is: nothing gives its address.
- **Fail:** an own host spelled `<app>-${APP_DOMAIN}` with no variable in front, or a list that
  names the box's other domains (nip.io, sslip.io) outside a fallback.

### `in-app-router` — routing beyond one port lives in the app

**Check:** static · **Severity:** Major
**n-a:** every route is host → one service's port, with no path rules.

A route says only *which host goes to which port*. When one address is served by several
services (dispatch by path), or a request must be checked before it is proxied (an auth hook),
or a path must be rewritten, the app ships its own router: an nginx service that is the
route's service and does the rest itself. The platform then routes the app like any other,
and the listing stays independent of the platform's proxy. The references:
`Apps/Seafile` (path dispatch over three services), `Apps/ClaudeCode` (`auth_request` gate),
`Apps/Vaultwarden` (only `/admin` through the AppShield gate) and `Apps/qBittorrent` (a header
fix, behind the gate).

With an AppShield gate, the router goes where its job is:

- **in front of the gate** when the gate must see only some paths (Vaultwarden): the router
  is the route's service and sends those paths to the gate — see `appshield-wiring`;
- **behind the gate** when every request is gated anyway (qBittorrent): the gate stays the
  route's service, its `BACKEND_HOST` is the router, and the router is on the app's own
  network only.
  The gate forwards the client's headers verbatim, so the router sees what the browser sent.

- **Pass:** all of the following hold:
  - every route is plain host → port (`routes-wiring`): path dispatch, auth hooks, rewrites,
    redirects and header fixes are in the router;
  - the router is a pinned nginx image named `<app>-router`; it is the route's service and the
    one `x-casaos.main` names, unless it sits behind an AppShield gate, which then is both;
  - its config ships inline: top-level `configs: <app>-router: content: |`, with every nginx
    `$` written `$$`;
  - only the router is on the shared network, plus whatever needs it for another reason (a
    service other apps call, a gate that reaches the auth-registrar, a backend that sends mail
    through `smtp`); the services behind it are on the app's own network;
  - the config handles what nginx does differently from the platform's proxy (Caddy on a
    PCS), as far as the app needs it:
    `client_max_body_size 0` and `proxy_request_buffering off` / `proxy_buffering off` for
    uploads and downloads, raised `proxy_read_timeout`, websocket `Upgrade`/`Connection`,
    `X-Forwarded-Proto` passed through from the proxy in front (not `$scheme`), `Host
    $http_host`, upstreams as variables with `resolver 127.0.0.11` so nginx starts before
    they exist, and `absolute_redirect off`;
  - a `location` that sets any `proxy_set_header` restates `Host` and `X-Forwarded-*` — nginx
    drops every inherited header in that case;
  - when the app reads the client address (rate limiting, logs), the router in front sets it
    from the **last** `X-Forwarded-For` entry — the one the platform proxy appended — never the
    first, which the client controls. A router behind a gate passes on the gate's `X-Real-IP` /
    `X-Forwarded-For` unchanged.
- **Fail:** a proxy-specific label, or a router that breaks uploads, websockets or the
  forwarded scheme.

### `container-name` — services on the shared network have stable names

**Check:** static · **Severity:** Major

- **Pass:** every service on the shared network sets `container_name`: lowercase letters,
  digits and `-`, not starting with a digit, and prefixed with the app name (or equal to it).

### `network-isolation` — only what must be reachable is on the shared network

**Check:** static · **Severity:** Minor

- **Pass:** a service is on the shared network only if it is a route's service or another app
  must reach it. Databases, caches and workers reached only by their siblings are on an
  app-internal network.

### `no-published-web-port` — HTTP goes through the platform's router only

**Check:** static · **Severity:** Critical when the published port bypasses a login gate (e.g. an AppShield app's backend); Major otherwise

- **Pass:** no HTTP or web UI port is published with `ports:`. A published port carries only
  non-HTTP traffic (BitTorrent, WebRTC media, SMB, WireGuard, a game protocol), with a comment
  saying what it is for.

### `requires-public-ip` — apps that need inbound connections say so

**Check:** static (`maison lint`) · **Severity:** Minor
**n-a:** the app publishes no port on every address.

- **Pass:** an app whose published port must be dialled from the internet for the app to work
  declares `requires: [public-ip]` in `x-compose-app`, and keeps the `needs-public-ip` tag in
  `x-casaos.tags` for CasaOS. Maison hides it on a box behind NAT or the tunnel.
- `maison lint` fails any app that publishes a port on every address without it. A port bound
  to one named address (a VPN's) is exempt.
- Formerly `needs-public-ip-tag`.

---

## 3. Data and permissions

### `data-under-datadir` — data lives in the app folder

**Check:** static · **Severity:** Major · `rationale.md` can cover it

- **Pass:** every bind source is under `/DATA/AppData/<app>/` or one of the user folders
  (`/DATA/Documents`, `Downloads`, `Gallery`, `Media`).
- **Fail:** a bind source anywhere else (outside `/DATA`, another app's folder, `/DATA` whole)
  with no rationale. The Docker socket is held to this item as well.

### `permissions` — the container user fits what it touches

**Check:** static · **Severity:** as below · `rationale.md` can cover it

| Container user                       | Touches                                                      | Verdict                                                               |
| ------------------------------------ | ------------------------------------------------------------ | --------------------------------------------------------------------- |
| `$PUID:$PGID`                        | anything within `/DATA`                                      | pass                                                                  |
| root, or no `user:` and a root image | its own app folder only                                      | pass                                                                  |
| root, or no `user:` and a root image | a user folder, or anything outside `/DATA`                   | **fail, Major**, unless covered by a rationale                        |
| any                                  | `privileged: true`, `cap_add`, host network or PID namespace | **fail, Critical**, unless the rationale names those exact privileges |

### `state-persistence` — all state is on a mapped volume

**Check:** static · **Severity:** Critical

- **Pass:** every location where the image keeps state (config, database, user or ACL store, uploads, keys) is covered by a bind mount into the app folder.
- **Fail:** any stateful path left in the container or in an anonymous volume. It is lost on
  reinstall.

### `declared-folders` — directories the app needs exist before it starts

**Check:** static · **Severity:** Major for an app-folder directory; Minor for a user folder the app does not write on first boot
**n-a:** no service runs as a non-root user against a bind-mounted directory.

- **Pass:** a bind-mounted directory that a non-root service writes to is declared under
  `x-compose-app.folders`. `schema_version: 2` is set, `mode` is quoted, and paths are absolute,
  inside `/DATA`, and fully resolvable.

### `broad-mount-disclosure` — broad access is visible before install

**Check:** static · **Severity:** Major if writable or `/DATA` whole; Minor if a read-only slice
**n-a:** no such mount.

- **Pass:** a mount of `/DATA/Documents`, `/DATA/Downloads`, `/DATA/Media`, `/DATA/Gallery` or
  `/DATA` itself is named in the `description`, in `tips` or in `rationale.md`.

### `migrations-wellformed` — data migrations follow the contract

**Check:** static · **Severity:** Major
**n-a:** no `data_version` and no `migrations`.

- **Pass:** all of the following hold:
  - `data_version` is an integer of 2 or more;
  - `migrations` has exactly one step for every id from 2 to `data_version`;
  - each step is exactly one of a script entry (`script:`, or `file:` under the app's
    `scripts/` folder, with every image it runs pinned and listed in `images:`) or `blocked:`;
  - each script step checks the data's actual state, so it is safe on data that is already
    converted;
  - a `blocked:` step lands together with the image change that needs it.

---

## 4. First-run setup and steps

### `step-idempotency` — steps are safe to rerun

**Check:** static · **Severity:** Major
**n-a:** no steps (`x-compose-app.steps`, `pre-install-cmd`, `post-install-cmd`).

- **Pass:** every step can run again on a reinstall or update without failing or damaging
  data. A `run: always` step is idempotent; work that must follow the data is guarded on the
  data (`[ -e "$APP_DIR/…" ] && exit 0`), not on `run: once`, whose marker an
  uninstall-keep-data removes.
- **Fail:** for example, unguarded initialisers chained with `&&`. The first one that refuses
  to overwrite existing data leaves the app installed but stopped. Flaky work in a `setup`
  step (which runs before every start) also fails here.

### `step-security` — scripts are pinned and non-interactive

**Check:** static · **Severity:** Major · `rationale.md` can cover a host change
**n-a:** no script entry (no `steps`, no migration script, no `change.script`).

- **Pass:** in every script entry, every image it runs is pinned; `docker run` writing to a
  user folder or to a file the app owns uses `--user $PUID:$PGID`; values reach an inner
  script through `-e`, not by splicing them into its text; the script never prompts; any change to the host
  (`sysctl`, `/etc`, mounts, kernel modules) is named in `rationale.md`.

### `step-scope` — steps don't do declarative work

**Check:** static · **Severity:** Major
**n-a:** no steps.

- **Pass:** no step creates a directory the app bind-mounts (`folders` does), generates a
  credential a `secrets` generator could produce, writes a config file that `seed/` or
  `files` could carry, appends to `.env` other than through `$MAISON_ENV`, or writes to
  `/DATA/AppData/casaos/apps/`. A step that only re-owns a path already under `folders` is a
  Minor fail.

---

## 5. Security

### `auth-default` — a login is on by default

**Check:** static, confirmed by functional `auth-gate` · **Severity:** Critical · `rationale.md` can cover it

- **Pass:** the web UI is behind an enabled login as shipped: AppShield SSO, the app's own login
  with a generated credential, or basic auth. For a service app, the listener it publishes asks
  for a credential as shipped.
- **Fail:** a UI reachable with no login, or a login that is off until the user enables it. An
  app that creates its first account on first visit, or a deliberately public site, passes only
  with a rationale.

### `appshield-wiring` — the SSO sidecar is wired so it cannot be bypassed

**Check:** static · **Severity:** Critical if the backend is reachable without the sidecar; Major otherwise
**n-a:** the app does not use AppShield.

- **Pass:** all of the following hold:
  - the route's service is the sidecar, and `x-casaos.main` names it — except when the gate
    covers only some paths: then the route and `x-casaos.main` are on the app's router
    (`in-app-router`), which sends exactly those paths plus `/nhl-auth/` to the sidecar
    (`Apps/Vaultwarden`);
  - the backend is no route's service and publishes no HTTP port;
  - the sidecar's `container_name` equals the compose `name`, and `hostname:` equals `container_name`;
  - `BACKEND_HOST`, `BACKEND_PORT`, `LISTEN_PORT`, `OIDC_REGISTRAR_URL` and
    `REDIRECT_HOST_SUFFIXES` are set, the last as `"${APP_HOST_SUFFIXES:-${APP_DOMAIN}}"` —
    the primary domain only. The registrar decides every host the app is reached on; this
    names the canonical one, which the gate uses as its OAuth issuer and its fallback login
    host. Listing the platform's other zones (`nip.io`, `sslip.io`) is a guess that goes
    stale: a gate older than 2.0.10 registers exactly that list, and one host the registrar
    no longer allows fails the whole login;
  - the AppShield image is pinned;
  - no `AUTH_HASH`, `?hash=`, or `CREDENTIAL_VALIDATE_URL` appears;
  - a machine/API path is gated by `OAUTH_RESOURCE`, never opened by `ALLOWED_PATHS`.

### `no-hardcoded-credentials` — no secret is written in the listing

**Check:** static · **Severity:** Critical if it guards a reachable service; Major otherwise

- **Pass:** no password, token, key or hash appears as a literal in the compose, in `seed/`
  or in steps. Every one comes from `x-compose-app.secrets` or is entered by the user.

### `per-app-secrets` — credentials belong to the app

**Check:** static · **Severity:** Major if an internal secret equals the login password; Minor otherwise
**n-a:** the app has no credential.

- **Pass:** every credential is its own entry under `x-compose-app.secrets`, one per purpose. A
  seeded form `${APP_DEFAULT_PASSWORD}|<generator>` passes; it is the sanctioned conversion of
  an installed app.
- **Fail:** `$APP_DEFAULT_PASSWORD` used directly as a credential (environment, step,
  `bcrypt:${APP_DEFAULT_PASSWORD}`); or a JWT, session or encryption key set to the login
  password. A mention in tips text only is not a fail.

### `credentials-shown` — the user can find the first login

**Check:** static · **Severity:** Minor
**n-a:** SSO only, or the app creates its first account through onboarding.

- **Pass:** a generated login is declared under `x-compose-app.credentials`. If `change` is
  declared, `password` is exactly `${NAME}` for a key under `secrets`.

### `lifecycle-rationale` — an app the user can't manage is justified

**Check:** static · **Severity:** Major · `rationale.md` can cover it
**n-a:** no `lifecycle` key is `false`.

- **Pass:** every `lifecycle.stoppable`, `uninstallable` or `updatable: false` is explained in
  `rationale.md`. `view: system` on an ordinary app is a Minor fail.

---

## 6. Listing

### `app-metadata-coherence` — store info is in `x-compose-app` and mirrored

**Check:** static · **Severity:** Major if the app is missing or unreachable from the store or the tile; Minor otherwise

- **Pass:** all of the following hold:
  - `x-compose-app` carries `schema_version: 2` (never higher), `title`, `tagline`,
    `description`, `developer`, `category`, `icon`, `screenshots`, `architectures` and,
    for a web app, `routes` (`routes-wiring`);
  - `x-casaos` repeats the same values under its own names (mapping in
    [GUIDELINES › Store info](GUIDELINES.md#store-info));
  - the two blocks don't contradict each other;
  - the compose carries none of the keys Maison writes itself (`store-ref`, `store`,
    `store-app-id`, `generated-routes`).

### `description` — the app is explained in English

**Check:** static · **Severity:** Minor

- **Pass:** every user-facing string — `title`, `tagline`, `description`, `tips`,
  `credentials[].label` / `note`, `links[].name`, `migrations[].name` / `blocked` — is a
  locale map with a non-empty `en_us` entry (Maison drops a plain string), and the description
  says what the app does. `maison lint` checks the first half:
  `docker run --rm -v "$PWD:/s" -w /s ghcr.io/yundera/maison:<tag> maison lint Apps/<App>/docker-compose.yml`.

### `assets` — icon and screenshots are present

**Check:** static · **Severity:** Major for a missing or broken icon or screenshot; Minor otherwise

- **Pass:** `icon.png` and at least `screenshot-1.png` exist in the app folder and are referenced
  by relative path (`icon: icon.png`). An absolute URL must point to this repository.
  `thumbnail.png` is optional (the store falls back to `screenshot-1.png`); if present, it is
  not the icon rescaled and not copied from another app.

---

## 7. Runtime

Checked on a PCS by installing the app from the store and driving it in a browser. A service app
has nothing to open, so only `install` applies to it; its auth and data are judged statically by
`auth-default` and `state-persistence`.

### `install` — a fresh install completes

**Check:** functional · **Severity:** Major

- **Pass:** installing from the store on a clean PCS ends with every long-running service up,
  and every one-shot service (a step, a setup container) exited 0.

### `app-url` — the app opens from its tile

**Check:** functional · **Severity:** Major
**n-a:** a service app.

- **Pass:** the tile's open action reaches the app at its `<app>-<domain>` URL.

### `works-immediately` — no setup before use

**Check:** functional · **Severity:** Major
**n-a:** a service app.

- **Pass:** the app shows a working UI right after install. Nobody has to read logs, open a shell
  or run a command first.

### `auth-gate` — the login is really there

**Check:** functional · **Severity:** Critical · `rationale.md` can cover it
**n-a:** a service app.

- **Pass:** opening the app's URL in a fresh session lands on a login, and the protected UI is
  unreachable without it. An app with no login passes only when `rationale.md` documents it as
  deliberately public, the same exception `auth-default` accepts.

### `clean-boot` — no first-party errors on first load

**Check:** functional · **Severity:** Minor, or Major if it breaks a feature
**n-a:** a service app.

- **Pass:** no first-party 5xx response and no first-party console error on first load and
  first use.

### `zero-config` — usable from the browser alone

**Check:** functional · **Severity:** Major · `rationale.md` can cover a third-party sign-in
**n-a:** a service app.

- **Pass:** the app reaches a usable state through its UI with the defaults it shipped with.
  Following what the app documents (its `tips`, its description, its own first screen) counts;
  reading logs, opening a shell or editing a file does not. An app whose setup needs an account
  on an identity provider the user doesn't control (Plex against plex.tv) passes when
  `rationale.md` names that provider.

### `data-persistence` — data survives uninstall and reinstall

**Check:** functional · **Severity:** Critical
**n-a:** a service app (`state-persistence` covers it statically).

- **Pass:** data created in the app is still there after an uninstall (which archives) and a
  reinstall that restores the archive.

### `migration` — an update keeps data and function

**Check:** functional · **Severity:** Critical
**n-a:** in a store audit, which installs one version. It is checked on the PR that bumps the
version; `migrations-wellformed` covers the static half.

- **Pass:** updating from the previous store version over its data keeps the data, and the app
  keeps working.
