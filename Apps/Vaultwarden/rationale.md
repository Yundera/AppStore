# Vaultwarden — Rationale

## What deviation / exception is being requested

Three, all documented below:

1. **`SIGNUPS_ALLOWED: "true"`** — until the owner turns signups off, any visitor who finds
   the address can create an account.
2. **`DISABLE_ADMIN_TOKEN: "true"`** — Vaultwarden's own `/admin` gate is turned off and
   the app ships with no `ADMIN_TOKEN` at all. An AppShield SSO sidecar gates `/admin`
   instead.
3. **Non-standard Caddy labels** — each site block splits by path into two `handle`
   branches instead of a single `reverse_proxy`, so that the sidecar sits in front of
   `/admin` **only**.

---

## 1. Open signup

### Why it is necessary

- **It is the only bootstrap path.** Vaultwarden has no seeded first user and no
  "create the owner account" flow outside of signup. With `SIGNUPS_ALLOWED: "false"` from
  the start, a freshly installed instance has zero accounts and no way to make one from
  the normal UI — the owner would have to go to `/admin` and invite themselves by email,
  which requires working outbound SMTP.
- **SMTP is not guaranteed to work.** The compose points `SMTP_HOST` at the platform
  `smtp` relay, but invitation mail depends on that relay being reachable and on the
  destination accepting it. Making first-run account creation depend on an email round
  trip would turn a zero-config install into a support case whenever mail is unavailable.
- **It is the upstream default.** `vaultwarden/server` ships `SIGNUPS_ALLOWED=true`;
  this app does not loosen anything relative to upstream.

### Security mitigations in place

- **Open signup does not expose any existing vault.** Every vault is encrypted client-side
  under its own master password, which the server never holds. A new account created by a
  stranger is an empty vault; it grants no read access to the owner's data, and the admin
  panel cannot decrypt a user vault either — stated in `tips.before_install`.
- **The owner is told to close it, in the install dialog, before they install.**
  `tips.before_install` step 3 is "Secure your instance: Disable new signups in admin
  panel once set up", alongside a direct link to the admin panel.

### Alternatives considered and rejected

1. **`SIGNUPS_ALLOWED: "false"` out of the box** — rejected: it leaves a new install with
   no accounts and no UI path to create one. Recovery requires the admin panel plus
   working SMTP, which is exactly the fragile dependency described above.
2. **`SIGNUP_DOMAINS_WHITELIST`** — rejected: it restricts *which* email domains may
   register, not *whether* an anonymous visitor may. On a personal server the owner's
   address is often at a large public provider, so whitelisting that domain would leave
   registration effectively open anyway.
3. **Auto-disabling signups after the first account** — rejected: Vaultwarden has no such
   setting, and a hook that rewrote the container's environment after first boot would be
   invisible to the user and would fight `restart: unless-stopped`.

---

## 2. No admin token — SSO in front of `/admin`

### Why it is necessary

**The admin token was a shared secret, not a secret.** The app previously set
`ADMIN_TOKEN` to the box-wide default app password and printed it in `tips.before_install`.
That password is a PCS-wide value injected into *every* app's environment, so the
password manager's admin panel was gated by a credential that every other container on the
box already holds, in plaintext, in its own `docker inspect` output.

This is the configuration upstream documents for exactly this case. From the
[Disable admin token](https://github.com/dani-garcia/vaultwarden/wiki/Disable-admin-token)
wiki page:

> If you have another method you would like to use for authentication to the `/admin` page
> then you can set the `DISABLE_ADMIN_TOKEN` variable to true. This will disable the built
> in `ADMIN_TOKEN` used for authentication while also enabling the admin panel. […]
> Anyone with access to the URL will be able to access the admin panel. You will need to
> take extra steps to secure it. This includes externally and locally.

and from `.env.template`:

> `## Enable this to bypass the admin panel security. This option is only`
> `## meant to be used with the use of a separate auth layer in front`

AppShield is that layer, and the router's path split below is what confines it to `/admin`.

### Alternatives considered and rejected

- **Argon2 PHC hash for `ADMIN_TOKEN`** (upstream's `vaultwarden hash`). Keeps the
  plaintext out of `docker inspect`, but the plaintext *is* the box-wide default password, which
  stays readable in every other app's environment. Hides the copy, not the secret.
- **Dropping the admin panel entirely** (leaving `ADMIN_TOKEN` unset disables it). Loses
  signup control, user management and diagnostics.

---

## 3. Path split in the app's own router

### Why it is necessary

AppShield protects a whole origin: everything is authenticated except what
`ALLOWED_PATHS` exempts, and it has **no inverse setting** — no way to say "protect only
this path" (verified against `appshield:3.0.2`). Putting it in front of the whole app
therefore costs a second login on the vault itself: the PCS SSO first, then the Vaultwarden
master password. That is a real cost paid by every user on every visit, to protect a page
the owner opens twice a year.

So the split is done in front of the gate, in the app's own router — `vaultwarden-router`,
an nginx service whose config ships inline in this listing (`configs: vaultwarden-router`).
It is the only service with Caddy labels; the platform routes `vaultwarden-<domain>` to its
port 80 and knows nothing of the paths behind it:

```
location = /admin   { proxy_pass http://vaultwarden:80; }          # the SSO sidecar
location /admin/    { proxy_pass http://vaultwarden:80; }
location /nhl-auth/ { proxy_pass http://vaultwarden:80; }
location /          { proxy_pass http://vaultwarden-backend:80; }  # everything else, direct
```

(Until 2026-10-21 this split was a Caddy `handle` tree in the labels, which tied the listing
to the platform's proxy. The behaviour is the same.)

`/nhl-auth/*` is AppShield 3.x's own reserved endpoint prefix (login, OIDC callback,
logout) and must reach the sidecar for the login round trip to complete. Everything else —
the web vault and the entire Bitwarden client protocol (`/api`, `/identity`,
`/notifications`, `/events`, `/icons`, `/attachments`, `/app-id.json`, `/.well-known`) —
is proxied straight to Vaultwarden exactly as before this change, so no client, app or
extension sees any difference.

This is the same shape the Vaultwarden community uses with Authelia (`forward_auth`
scoped to an `/admin` matcher).

The router also carries what the backend needs and nginx does not do by default: no
request-body cap and no buffering (attachments and Sends), long timeouts, and the websocket
upgrade for `/notifications/hub`. It sets `X-Real-IP` — the header Vaultwarden reads the
client address from for its login rate limiting and logs — to the last `X-Forwarded-For`
entry, the one the proxy in front appended, which a client cannot forge. Before the router
Vaultwarden saw every client as the platform proxy's container address, so all clients
shared one rate-limit bucket; now it sees the real client on a direct route (sslip.io) and
the Cloudflare edge on the gateway route.

Checked on a test PCS on 2026-10-21 against the previous, label-routed listing, on all
three published hosts: web vault, `/alive`, `/api/config`, prelogin, a rejected login, a
3 MiB request body, both notification websockets, `/admin` and `/admin/users` redirected to
the SSO login, `/nhl-auth/oidc/login` handing off to the PCS login, and `/adminx` still
reaching Vaultwarden — identical results; the SSO login to `/admin` and the web vault were
then checked in a browser.

### Security mitigations in place

- **The vault's own auth is untouched.** Master password, 2FA and Vaultwarden's brute-force
  protection still guard every account; the sidecar only adds a second, independent gate in
  front of the admin page.
- Neither the backend nor the sidecar carries Caddy labels — the routing decision exists in
  exactly one place, the router.
- Resource limits on both services; AppShield runs with Docker's default capability set.
- **`DOMAIN` is pinned** to `https://vaultwarden-$APP_DOMAIN`, so Vaultwarden issues its
  own links and WebAuthn origins against the gateway hostname rather than an
  attacker-supplied `Host` header.
- `OIDC_REQUIRED_GROUPS: "admins"` is present as a commented-out one-liner on the sidecar
  for deployments that want the panel restricted to the `admins` group.

### Alternatives considered and rejected

- **AppShield in front of the whole app, with `ALLOWED_PATHS` exempting the client
  protocol.** Tested and working (24/24), and it fails *closed* — no mistake in the
  exemption list can expose `/admin`. Rejected because it puts an SSO login in front of the
  web vault, i.e. two logins to read a password. Deliberate trade, made with eyes open:
  see the residual risk below.
- **A separate `vaultwardenadmin-` hostname for the sidecar.** Would need a second
  AppShield container whose name is not the app name, which `auth-registrar` attests by
  PTR lookup; and it still requires blocking `/admin` on the main hostname, so it carries
  the same failure mode as the split with more moving parts.

---

## Data protection

- All state lives in `${DATA_ROOT:-/DATA}/AppData/vaultwarden/data/` and survives uninstall
  / reinstall and image upgrades. This is a front-door change only: no migration, no change
  to the SQLite database or the RSA key. Existing installs keep the same hostname and URLs,
  and every configured client keeps its connection.
- Vault contents are end-to-end encrypted under each user's master password. The server
  stores ciphertext only; neither the admin panel nor filesystem access to the PCS yields
  plaintext.
- `tips.before_install` opens by warning that a lost master password makes the vault
  permanently unrecoverable, so the user is told before install that recovery is not
  something the server operator can perform.

### Accepted residual risks (deliberate)

1. **The split fails open.** With `DISABLE_ADMIN_TOKEN`, the admin panel's only protection
   is the `@sso` branch. If those labels are dropped or reordered, `/admin` reaches
   Vaultwarden with no credential at all. Note that a *broken* matcher is a Caddy config
   error rather than a silent bypass — the site block fails to load — but a *deleted* one
   is not. Anyone editing this compose must treat the label block as security-critical.
2. **Any PCS SSO account can open the admin panel**, not only the owner — verified: a user
   outside `admins` gets in. `OIDC_REQUIRED_GROUPS: "admins"` closes this (also verified:
   a non-admin is then bounced to the PCS dashboard) and is left commented out on purpose.
3. **A container on the shared `pcs` network can reach `http://vaultwarden-backend/admin`
   with no credential** — this is the "and locally" upstream warns about. The backend stays
   on `pcs` because it has to resolve the `smtp` mail gateway. It is not a regression: the
   shipped `ADMIN_TOKEN` was the box-wide default password, which those same containers already
   hold.

## Verification

Tested on wisera (`vaultwarden-wisera.inojob.com`) on 2026-09-07 against
`appshield:3.0.2` + `vaultwarden/server:1.37.0`. **27/27 checks.**

- Gated (302 → `/nhl-auth/oidc/login`): `/admin`, `/admin/`, `/admin/users`,
  `/admin/diagnostics`, `/admin/organizations/overview`, `POST /admin`,
  `POST /admin/users/<id>/deauth`, `POST /admin/config`, `/admin/logout`.
- Not gated, served straight from Vaultwarden: `/` (the web vault SPA loads at `#/login`
  with no SSO prompt), `/index.html`, `/vw_static/*`, `/css/vaultwarden.css`, `/alive`,
  `/app-id.json`, `/.well-known/apple-app-site-association`, `/icons/…`, `/api/config`,
  `/identity/accounts/prelogin`.
- Full client flow, all direct: register → `identity/connect/token` → `/api/sync` →
  create cipher → attachment upload → unauthenticated attachment download by URL token →
  `/events/collect`; push websocket upgraded to `101 Switching Protocols`.
- After SSO the admin panel renders with its `/vw_static/` assets, and an authenticated
  write (`POST /admin/users/<id>/deauth`) returns 200.
