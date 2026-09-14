# qBittorrent — Rationale

## What deviation / exception is being requested

The app is the standard AppShield split — an `appshield:3.0.2` gate in OIDC mode
holding the Caddy labels, and `qbittorrent-backend` (the WebUI + engine) with no
labels of its own. Two things about it are not standard:

**1. The three Caddy site blocks do not proxy with a single `reverse_proxy`.**
Each one defines a named matcher and two `handle` branches:

```
@tilenav {
  method GET
  path /
  header Sec-Fetch-Mode navigate
}
handle @tilenav {
  reverse_proxy qbittorrent:80 {
    header_up -Referer
    header_up -Origin
  }
}
handle {
  reverse_proxy qbittorrent:80
}
```

So the `Referer` and `Origin` request headers are removed — **only** on a
top-level browser navigation to `/`. Every other request reaches the gate, and
through it qBittorrent, with its headers untouched.

**2. The WebUI's own login is bypassed** for the Docker private ranges, by the
`bypass-webui-login` init step writing
`WebUI\AuthSubnetWhitelistEnabled=true` and
`WebUI\AuthSubnetWhitelist=172.16.0.0/12, 10.0.0.0/8, 192.168.0.0/16`.

## Why 1 is necessary

qBittorrent's WebUI has a built-in cross-site check
(`WebApplication::isCrossSiteRequest`, called from `processRequest`). With
`WebUI\CSRFProtection=true` it answers `401 Unauthorized` — `text/plain`, 12
bytes, no HTML — to any request whose `Referer`/`Origin` host differs from the
host it was served on (it compares against `X-Forwarded-Host` when present, and
compares host and port only; scheme is explicitly not compared).

**That check runs before authentication and is not conditional on it.** In
`processRequest` the cross-site test throws `UnauthorizedHTTPError` *above* the
`sessionInitialize()` / `doProcessRequest()` call, so bypassing the login (point 2)
does not exempt it. Verified on the running 5.1.4 backend: with the subnet
whitelist active, `GET /` with a foreign `Referer` still returns
`401 Unauthorized`, while the same request with no `Referer` returns `200`.

Every way a user arrives at this app is such a cross-site navigation:

- the Maison dashboard tile (`https://<user>.<domain>/` →
  `https://qbittorrent-<user>.<domain>/`), and
- the redirect back from the SSO round trip, whose referrer is the auth origin
  (`https://auth-<user>.<domain>/`).

Without the exception the user clicks the tile, completes the server login, and
lands on the bare string `Unauthorized`. Reloading does not help — Chrome replays
the original referrer — so the only way in is to retype the URL by hand. The tile
is the app's primary entry path (Touchstone `works-immediately`, MAJOR).

The request that has to be unpicked is fully identified:

| | entry navigation | everything else |
|---|---|---|
| method | `GET` | `POST`/`GET`/… |
| path | `/` | `/api/v2/…`, assets, `/nhl-auth/…` |
| `Sec-Fetch-Mode` | `navigate` | `cors` (XHR), `no-cors`/`same-origin` (assets) |

Matching all three and stripping the two headers there makes the tile land on the
app, and changes nothing else. The SSO round trip is unaffected: `/nhl-auth/*` is
not path `/`, so it keeps its headers.

## Why 2 is necessary

AppShield protects a whole origin and is the platform's single sign-on. Left as
it was, a user would sign in to the server, then be asked for a second password
(`admin` / `$APP_DEFAULT_PASSWORD`) by qBittorrent itself — the same double login
that was rejected for Vaultwarden. The whitelist covers the Docker private ranges,
which is the only place the backend can be reached from at all: it has no Caddy
labels and publishes no HTTP port to the host, so the gate is the only route in
from the internet.

`WebUI\Username` and `WebUI\Password_PBKDF2` are still seeded, so a user who sets
`AuthSubnetWhitelistEnabled` back to `false` has a known password to log in with,
and the Radarr/Sonarr/Lidarr download-client integrations work whether they send
credentials or not.

## Security mitigations in place — why CSRF protection is still intact

The attack the `enable-csrf-protection` init step exists to stop is a cross-site
`POST /api/v2/app/setPreferences` setting `autorun_program`, i.e. arbitrary
command execution. Neither exception affects it:

- **The matcher requires `method GET`.** No mutating request can match it. Every
  qBittorrent API call that changes state is a `POST` and falls to the second
  `handle`, which forwards `Origin`/`Referer` verbatim; qBittorrent's own check
  sees them and rejects the cross-site ones. Verified through the deployed chain:
  a cross-site `POST /api/v2/app/setPreferences` with `Origin: https://evil.example`
  is answered `401 Unauthorized` by the backend, with the whitelist active.
- **The matcher requires `path /`** — an exact match, not a prefix. Nothing under
  `/api/v2/` can reach the stripping branch even as a `GET`.
- **The matcher requires `Sec-Fetch-Mode: navigate`.** The WebUI drives the API
  over `fetch`/XHR, which browsers label `cors` or `same-origin`; only a
  top-level document navigation is labelled `navigate`, and a browser sets this
  header itself — page JavaScript cannot forge it (it is a forbidden header
  name). An attacker's page therefore cannot make its API call look like an entry
  navigation.
- **What the exception actually grants an attacker is nothing.** The only thing
  it lets a cross-site context do is fetch `/` with the referrer hidden — and it
  cannot even do that, because the SSO gate answers an unauthenticated `GET /`
  with `302 /nhl-auth/oidc/login`. `GET /` has no side effect and the response is
  opaque to the attacker under the same-origin policy.
- **The gate does not replace qBittorrent's own check, it layers on top of it.**
  The gate is a session cookie; a cross-site write that arrives with that cookie
  attached would be proxied through, and qBittorrent's `Origin` comparison is what
  rejects it. That is why `CSRFProtection` is turned back on even though the app
  now sits behind SSO.

The header-strip behaviour was verified through the real deployed chain (gateway
Caddy → AppShield → backend) on wisera by substituting an echoing backend:

| request | `Referer`/`Origin` seen by the backend |
|---|---|
| `GET /`, `Sec-Fetch-Mode: navigate` | **absent** (both stripped) |
| `GET /api/v2/app/version`, `Sec-Fetch-Mode: cors` | both present, verbatim |
| `POST /`, `Sec-Fetch-Mode: navigate` | both present, verbatim |

## Alternatives considered and rejected

- **Strip `Referer`/`Origin` unconditionally on the whole site** (a plain
  `header_up -Referer; header_up -Origin` on the single `reverse_proxy`). This is
  the obvious fix and it is wrong: qBittorrent's check passes a request that
  carries no `Origin`/`Referer` at all, so stripping them everywhere is
  functionally identical to setting `WebUI\CSRFProtection=false` — it reopens the
  `setPreferences`/`autorun_program` RCE. Rejected.
- **Turn `WebUI\CSRFProtection` off now that the app is behind SSO.** That makes
  the whole `@tilenav` construction unnecessary, which is tempting. Rejected
  because it puts the entire weight of that defence on the gate's session cookie
  being `SameSite=Lax`/`Strict`; the app's own check is unconditional and costs
  one precisely-scoped matcher.
- **Leave the WebUI login in place and accept a second password.** Coherent, and
  it is what the app did before the gate. Rejected on the same grounds as
  Vaultwarden: the platform login is meant to be the only one, and
  `$APP_DEFAULT_PASSWORD` is a PCS-wide value present in every app's environment,
  so it is not much of a second factor anyway.
- **Give the backend the bare name `qbittorrent` and the gate a different one.**
  Not possible: AppShield builds its OIDC redirect URIs from `os.hostname()` and
  the auth-registrar attests the app via the container's PTR record, so the gate
  must own the app name. Docker registers both the service key and the
  `container_name` in its embedded DNS, so two containers claiming `qbittorrent`
  would round-robin and sibling apps would reach the gate at random. The backend
  is therefore `qbittorrent-backend`, and the Radarr/Sonarr/Lidarr/Prowlarr tips
  name that host.
- **Put the backend on an app-private network.** Rejected: Radarr, Sonarr and
  Lidarr add qBittorrent as a download client by container name, which needs it on
  `pcs`. Same trade as Prowlarr.
- **Point the tile somewhere else** (a `webui-path` qBittorrent treats
  differently). There is no such path: the cross-site check is on headers, not on
  the URL, so every entry point behaves identically.

## Data protection

Unchanged by these exceptions. All state stays in
`/DATA/AppData/qbittorrent/config/` (declared under `x-compose-app.folders`),
downloads in `/DATA/Downloads/` (disclosed in `tips.before_install`), the backend
runs as `$PUID:$PGID`, memory is capped at 512M (128M for the gate) and
`cpu_shares` are set on both. All three init steps are guarded on marker files
inside the config volume, not on `once`, so a reinstall never resets the WebUI
password or the user's preferences. `bypass-webui-login` deletes any existing
`WebUI\AuthSubnetWhitelist*` lines before inserting its own and anchors the insert
on the `[Preferences]` header, so it is idempotent and safe against the multi-
section file qBittorrent rewrites after its first run.
