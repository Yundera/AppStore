# Foundry Virtual Tabletop — Rationale

## What deviation / exception is being requested

1. **No AppShield SSO sidecar.** Access control is Foundry's own: an administrator
   password on the setup screen and per-user passwords inside each world.
2. **Does not work immediately after install.** The app needs the user's
   foundryvtt.com account before it can start.

## Why it is necessary

**No SSO.** The point of a virtual tabletop is that the game master's friends join the
game. Those players have no account on the PCS, so a gate in front of the whole app
would lock them out. Foundry enforces its own login on every route: the setup screen
(worlds, systems, modules, server settings) requires the administrator key, which is
set to the app's `FOUNDRYVTT_ADMIN_PASSWORD` secret on every start, and a world can only be joined as one of
its users. The guide accepts the app's own login as the authentication method.

**Account required.** Foundry VTT is commercial software and may not be redistributed,
so no image ships it. The community image (`felddy/foundryvtt`) downloads the release
and fetches the license on first start using the user's foundryvtt.com credentials. The
store cannot supply those. The compose declares `FOUNDRY_USERNAME`, `FOUNDRY_PASSWORD`
and `FOUNDRY_LICENSE_KEY` as empty `.env` variables so they show up in the app's
**Env** tab, and `tips.before_install` walks the user through filling them in. Until
then the container logs the missing credentials and retries with exponential back-off
(up to 16 minutes between tries), so it does not spin.

## Security mitigations in place

- Only port 30000 is `expose`d, to Caddy on the `pcs` network. Nothing is published on
  the host.
- The administrator password is the app's own `FOUNDRYVTT_ADMIN_PASSWORD` secret, not a
  literal, and the image re-applies it at every start. Maison shows it via `credentials`.
- Foundry's default world users have no password. `tips.before_install` tells the game
  master to set one per user before sharing the link.
- The foundryvtt.com password sits in the app's `.env`, in plain text, like every other
  `.env` value on the box. It is only used to download a release and fetch the license.
- Container runs as `$PUID:$PGID`. Memory capped at 2 GB.

## Alternatives considered and rejected

- **AppShield in front of the app:** locks out players, which defeats the app.
- **AppShield on the setup screen only (path split):** Foundry's setup and game UIs
  share routes (`/setup`, `/join`, `/game`, one websocket), so a path split cannot
  separate them cleanly, and the admin key already guards setup.
- **Pre-placing a downloaded zip in `container_cache/`:** supported by the image as a
  fallback, but it needs file access to `AppData` and an exact `foundryvtt-<version>.zip`
  name. The Env tab is the simpler path for most users.

## Data protection

Worlds, systems, modules, uploads, config and logs live in
`/DATA/AppData/foundryvtt/data/`. The image only regenerates `Config/options.json`
and `Config/admin.txt` at start. Before a major-version migration, Foundry backs up
each world it migrates.
