# OpenClaw — Rationale

## What deviation / exception is being requested

**OpenClaw's own authentication is switched off**, deliberately, in two places that
have to agree:

- `openclaw-backend` sets
  `OPENCLAW_GATEWAY_CONTROL_UI_ALLOW_INSECURE_AUTH: "true"` and
  `OPENCLAW_GATEWAY_CONTROL_UI_DANGEROUSLY_DISABLE_DEVICE_AUTH: "true"`.
- `seed/openclaw.json` — the live gateway config — carries the same two flags
  (`allowInsecureAuth`, `dangerouslyDisableDeviceAuth`) so the setting survives the
  gateway rewriting its own config file.

The gateway is additionally started with `--allow-unconfigured`, so it serves before
an AI provider key has been entered.

## Why it is necessary

Authentication is not removed, it is **relocated to the AppShield sidecar**, which is
the arrangement `CONTRIBUTING.md` recommends first. `openclaw` (the sidecar) is the
only service on the shared `pcs` network and the only one carrying Caddy labels; it
fronts the gateway with the PCS's built-in Authelia SSO over OIDC and self-registers
with `auth-registrar` on first login.

OpenClaw's native gate is a **device-pairing** flow: the browser is enrolled as a
paired device against the gateway. Left on behind an SSO proxy it produces two
unrelated login ceremonies for one app — the PCS sign-in the user already completed,
then a pairing step whose approval channel is the very UI the proxy is protecting.
Worse, the pairing token is per-device, so the SSO session and the device identity
drift apart on every new browser. Delegating to the sidecar leaves exactly one
credential — the user's PCS account — governing access.

`--allow-unconfigured` exists so the app is usable on first open: the API key is
entered through the Config section of the UI (as `tips.before_install` describes)
rather than requiring the user to edit the environment and redeploy before the app
will start at all.

## Security mitigations in place

- **The gateway has no route of its own.** `openclaw-backend` is on the app-private
  `openclaw-internal` bridge only — not on `pcs` — so it carries no Caddy labels, is
  not resolvable by any other app on the box, and publishes no host port. The single
  path to it is through the sidecar, which means every request has passed the SSO
  gate. This is what makes disabling device auth safe rather than reckless: the
  insecure-auth flags apply to a listener nothing unauthenticated can reach.
- **The sidecar's OIDC identity is pinned.** `container_name` and `hostname` both
  equal `openclaw`, which is what `auth-registrar` attests via the container's PTR
  record; a mismatch fails registration rather than falling open.
- **The gateway still holds a credential of its own.** `OPENCLAW_GATEWAY_TOKEN` is
  set to `$APP_DEFAULT_PASSWORD` — the per-install random value Maison injects, so it
  is distinct on every PCS and is never a shipped literal. It is *required*: from
  2026.6.x the image refuses to bind to a non-loopback interface without a token or
  password, and the two control-UI flags above do not satisfy that guard. So the
  arrangement is not "auth off" but "auth moved": the browser authenticates once
  against the PCS SSO at the sidecar, and the gateway keeps a second, non-interactive
  credential behind it.
- **Blast radius is the app's own AppData.** The gateway executes shell commands and
  reads and writes files *by design* — that is the product — but its only bind mount
  is `${DATA_ROOT:-/DATA}/AppData/openclaw`. No user directory (`/DATA/Documents`,
  `/DATA/Downloads`, `/DATA/Media`, `/DATA/Gallery`) and no Docker socket is mounted,
  so neither its shell nor its file tools reach beyond its own state.
- **`init: true`** on the backend reaps the processes its shell tool spawns, so a
  long-lived gateway does not accumulate zombies.
- **Memory ceilings and CPU shares** on both services (256M / 2048M; 50 / 90).
- **Pinned images**, no `:latest`: `ghcr.io/yundera/appshield:2.0.9` and
  `alpine/openclaw:2026.6.9`.

## Alternatives considered and rejected

1. **Leave OpenClaw's device auth enabled behind AppShield.** Rejected — two login
   ceremonies for one app, and the pairing-approval UI sits behind the proxy that is
   already authenticating the user. It also breaks on each new browser, since device
   identity and SSO session are independent.
2. **Drop the sidecar and rely on device auth alone.** Rejected — that publishes a
   shell-executing agent directly on a public hostname, gated only by a pairing flow
   the app's own documentation marks as insecure over plain HTTP. The sidecar is the
   stronger gate and the one the platform already provides.
3. **Require the API key as an install-time environment variable.** Rejected —
   Maison has no per-field install form, so the user would have to install, edit the
   app environment in the dashboard and redeploy before the app would run at all.
   `--allow-unconfigured` plus the in-UI Config section keeps first-run in the
   browser, which is what the Functionality checklist asks for.

## Data protection

- All state lives under `/DATA/AppData/openclaw/` and survives uninstall/reinstall.
- `openclaw.json` is declared under `x-compose-app.files` with `ensure: once`, which
  is create-if-absent on every up. A reinstall or a version upgrade therefore never
  overwrites the config the user — or the gateway itself — has since written, and
  Maison chowns it to `$PUID:$PGID` so the gateway can rewrite its own config.
- `/DATA/AppData/openclaw` is declared under `x-compose-app.folders` owned by
  `$PUID:$PGID`, created before any image is pulled, so the gateway can write its
  own state on first start without a hook.
- The AI provider key the user enters is stored in that config file. It leaves the
  server only in requests to the provider the user chose (Anthropic or OpenAI); no
  other outbound destination is configured.
