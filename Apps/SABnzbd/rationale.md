# SABnzbd — Rationale

## What deviation / exception is being requested

The app is the standard AppShield split — an `appshield:3.0.2` gate in OIDC mode
holding the Caddy labels, and `sabnzbd-backend` (the web UI + download engine)
with no labels of its own. Three things about it need justifying:

**1. SABnzbd's own login is left off** (`username`/`password` empty in the seeded
`sabnzbd.ini`), so the SSO gate is the only login.

**2. `inet_exposure = 4`** is seeded, opening the web UI and the API to callers
SABnzbd judges "external". Stock is `0`, which allows nothing.

**3. `host_whitelist` is seeded and then re-asserted on every up** by the
`refresh-host-whitelist` init step, rather than being left to the user.

The app also mounts `/DATA/Downloads` read-write, which is a shared user
directory rather than the app's own AppData. That is disclosed in the app
`description` and in `tips.before_install`.

## Why 2 is necessary

`secured_expose` in `sabnzbd/interface.py` gates every page and API route on
`check_access(access_type=4)`, which returns early only when
`access_type <= cfg.inet_exposure()`. Otherwise it judges the caller by address:
the socket peer must be loopback or a LAN address, and — because
`verify_xff_header` defaults to `1` — **every** address in `X-Forwarded-For` must
be local too.

Behind the gateway that never holds. The chain is Caddy → AppShield → SABnzbd, and
both proxies append to `X-Forwarded-For`, so the header carries the visitor's real
public address. Verified against `lscr.io/linuxserver/sabnzbd:5.1.3` with
`inet_exposure = 0`:

| request | result |
|---|---|
| `GET /`, no `X-Forwarded-For` | `303` → `/wizard/` |
| `GET /`, `X-Forwarded-For: 8.8.8.8, 172.18.0.5` | `403 External internet access denied` |

So stock `0` does not mean "locked down but usable"; it means the app answers 403
to every real visitor. `4` is the lowest value that opens the web UI. `5` ("web UI,
but external visitors must log in") is not used — see the alternatives below.

Two properties make this safe to seed rather than leave to the user. It is
`protect=True` upstream (`sabnzbd/cfg.py`), so it can only ever be set in this
file — never through the web UI or the API, and never by a request that got
through the gate. And the thing it opens is reachable only through the gate: the
backend has no Caddy labels and publishes no port to the host.

## Why 3 is necessary

`check_hostname()` in `sabnzbd/interface.py` is a DNS-rebinding guard, added for
the same class of issue as CVE-2019-5702. It refuses any request whose `Host`
header is not an IP address, not `localhost`, not `*.local`, and not in
`host_whitelist` — with `403 Access denied - Hostname verification failed`.

Every request that arrives through the gateway carries `Host: sabnzbd-<domain>`,
which is none of those. So without a whitelist entry the app is unreachable, and
the whitelist has to name **every** hostname the app answers on. Verified on the
same image, through a real AppShield sidecar:

| `Host` | result |
|---|---|
| `sabnzbd-me.nsl.sh` (whitelisted) | `303` → `/wizard/` |
| `sabnzbd-1-2-3-4.sslip.io` (whitelisted) | `303` → `/wizard/` |
| `sabnzbd-other.nsl.sh` (not whitelisted) | `403` hostname verification failed |

AppShield was confirmed to forward the original `Host` verbatim (it sets
`X-Forwarded-Host` to the same value and appends its own hop to
`X-Forwarded-For`), so the names that have to be whitelisted are exactly the three
`caddy_N` route hostnames.

**`sabnzbd-backend` has to be in the list too.** Radarr, Sonarr, Lidarr and
Prowlarr reach the API directly over the shared network as
`http://sabnzbd-backend:8080/api?...`, which sends `Host: sabnzbd-backend:8080`;
the port is stripped and the bare name checked. Verified: without the entry, that
call answers `403 Access denied - Hostname verification failed` while a browser on
the published domain works perfectly — a failure that would look like a broken
download-client integration and point nowhere near the real cause.

**Why an init step and not just the seed.** `seed/` is create-if-absent by design
(SABnzbd rewrites `sabnzbd.ini` from its first start onward, and a re-rendered file
would fight that). So the names rendered at install go stale the moment the
deployment's domain changes, and the app starts answering 403 to everyone with
nothing in its log to explain why. The init step re-adds the current names before
every `docker compose up`.

## Security mitigations in place

- **The gate is the only way in.** `sabnzbd-backend` carries no Caddy labels and
  publishes no host port; only the `appshield` sidecar is routable. Both
  exceptions above widen what SABnzbd itself will answer, not who can reach it.
- **The whitelist is still a whitelist.** It names four hosts, and a request for
  anything else is still refused — the DNS-rebinding guard keeps working for every
  name the app was not deployed under. The exception is that the list is
  maintained by the app rather than by the user.
- **The init step only ever adds.** It greps the `host_whitelist` line for each
  name and prepends it only when absent, so it is idempotent across restarts, and
  a host the user added by hand (a custom domain, another proxy) is never removed.
  It also tolerates the file being absent, which is the state on a first install —
  `init` runs at `pre_up`, one step *before* the seed is written. The grep is
  scoped to that one line rather than the whole file on purpose: configobj keeps
  this file's comments verbatim across every rewrite SABnzbd makes, and the seed's
  own comment block names `sabnzbd-backend`, so a whole-file grep matched its own
  documentation and skipped the entry. Caught on holyhorse by simulating a domain
  change: the three route hosts came back and `sabnzbd-backend` did not, which
  surfaces only as the *arr download-client integrations getting 403 from an app
  whose web UI works perfectly.
- **No credentials are shipped.** `api_key` and `nzb_key` are left out of the seed
  entirely, so SABnzbd generates a fresh pair per install. There is no
  `ALLOWED_PATHS` on the gate: nothing in this app is reachable without a session.
- **Resource limits and ownership.** The backend runs as `$PUID:$PGID`, memory is
  capped at 2G (128M for the gate), `cpu_shares` are set on both, and the article
  cache is lowered from SABnzbd's stock 1G to 512M so the par2/unrar children fit
  inside the cap.

## Alternatives considered and rejected

- **`inet_exposure = 5` plus SABnzbd's own login** (`admin` /
  `$APP_DEFAULT_PASSWORD`, seeded the way `Apps/Sonarr` seeds `config.xml`). This
  is genuinely tempting, because `check_hostname()` returns `True` immediately when
  a username *and* password are configured — so it would make exception 3 and the
  whole init step unnecessary, and would be immune to a domain change. Rejected
  because it means a second password on top of the server login, the same double
  login that was rejected for Vaultwarden and qBittorrent. The whitelist is the
  price of a single sign-on here.
- **Rewrite the `Host` header at the proxy** to an IP or `localhost`, which
  `check_hostname()` accepts unconditionally. Rejected: AppShield builds its OIDC
  redirect URIs from the incoming host, so Caddy must forward the real one, and
  AppShield exposes no setting for what it sends onward.
- **Replace the whole `host_whitelist` line on every up** instead of adding to it.
  Simpler to write, and it would drop a stale name after a domain change. Rejected
  because it would also silently delete any host the user added themselves; a stale
  entry is a name the deployment no longer answers on and is harmless behind the
  gate, whereas a deleted entry breaks a working setup.
- **Let the user fix it.** The failure mode is a bare `403 Access denied -
  Hostname verification failed` on the tile, with the fix buried in a setting the
  user cannot reach because the settings page 403s too. Rejected.
- **Put the backend on an app-private network.** Rejected: Radarr, Sonarr, Lidarr
  and Prowlarr add SABnzbd as a download client by container name, which needs it
  on `pcs`. Same trade as qBittorrent and Prowlarr.
- **Give the backend the bare name `sabnzbd`.** Not possible: AppShield builds its
  OIDC redirect URIs from `os.hostname()` and `auth-registrar` attests the app via
  the container's PTR record, so the gate must own the app name. Docker registers
  both the service key and the `container_name` in its embedded DNS, so two
  containers claiming `sabnzbd` would round-robin. Hence `sabnzbd-backend`, which
  is the host the tips name for the *arr integrations.

## Data protection

All settings and in-flight jobs stay under `/DATA/AppData/sabnzbd/` — `config/`
for `sabnzbd.ini` and the job database, `incomplete/` for partial articles and
unpack scratch space — both declared under `x-compose-app.folders` and owned by
`$PUID:$PGID`. Only finished jobs are moved into `/DATA/Downloads/`, the shared
folder the rest of the user's apps read; that mount is read-write and is disclosed
in the app `description` and in `tips.before_install`.

The seed is create-if-absent and the app carries no `files: ensure: always`, so
nothing the user changes in the web UI is ever overwritten. The one thing that is
re-asserted on every up is the `host_whitelist` line, and it is re-asserted by
addition only.
