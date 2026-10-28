# Crafty Controller Rationale

## What deviation / exception is being requested

This app deviates from the default AppStore requirements in two ways:

1. The container runs as root (`user: "0:0"`).
2. It does not use the recommended `nginx-hash-lock` OIDC sidecar. Access control is provided by Crafty Controller's own built-in login, enabled by default.

## Why it is necessary

**Root.** Crafty Controller creates, launches, and supervises Minecraft (Java and Bedrock) server processes under `/crafty/servers`, writing JVM working directories and managing child processes. It expects to run as root and does not reliably start or spawn server processes under a non-root UID. Upstream ships and supports the image as a root container.

**No sidecar.** The Crafty panel speaks HTTPS on `8443` with a self-signed certificate and depends on a persistent WebSocket (WSS) connection for the live console and server status. Fronting it with the `nginx-hash-lock` sidecar would add a second TLS hop in front of the self-signed upstream plus a websocket upgrade path the sidecar is not configured to pass through, which breaks the live console. Crafty enforces authentication on every panel route (no anonymous access), which the guide accepts as a valid built-in login gate. The admin password is the per-app `CRAFTY_ADMIN_PASSWORD` secret (plus a trailing `!`), written at install time, so authentication is enabled by default with no manual step.

**Router.** The panel is reached through `crafty-router`, an nginx service that is the route's service (port `80`, so `x-casaos.webui_port: 80`). It passes `Host` through as the browser sent it and forwards the websocket `Upgrade`/`Connection` headers, which Crafty needs: its websocket handler rejects any handshake whose `Origin` does not match the `Host` it sees (403 "Cross origin websockets not allowed"), and that breaks the live console and server status. The router makes the self-signed HTTPS hop to `8443` on the app's own network (`crafty-net`); the Crafty container itself is not on `pcs`.

## Security mitigations in place

- The panel backend is reachable only through `crafty-router` on the app's own network. `expose: 8443` is not a host port binding, so the panel is never published directly to the host.
- Authentication is enabled by default. The admin account is created at install with the per-app `CRAFTY_ADMIN_PASSWORD` secret (plus a trailing `!`), and Maison shows it under the app's Credentials; the user should change it after first login.
- No credentials are hardcoded in the compose file. The password comes from the `CRAFTY_ADMIN_PASSWORD` secret, generated once per install (seeded from the former shared password on boxes that already had the app).
- Resource limits cap the container at 2048M of memory, and `cpu_shares: 50` prevents it from starving other apps under load.
- The published game ports (`25500-25600/tcp`, `19132/udp`) are required for Minecraft clients to reach the servers from the internet. They carry the Minecraft protocol only; no HTTP port is published, and the management panel stays behind authentication.

## Alternatives considered and rejected

- **Running as `$PUID:$PGID`:** Crafty fails to manage server processes and write its working directories without root. Rejected on functional grounds.
- **`nginx-hash-lock` sidecar in front of the panel:** breaks the live console, because the self-signed HTTPS upstream plus the required WSS upgrade do not pass cleanly through the sidecar. Rejected because it makes the core feature unusable. Crafty's own login is an accepted alternative under the guide.

## Data protection

- All persistent state is mapped under `/DATA/AppData/$AppID/` (`backups`, `logs`, `servers`, `config`, `import`), so user worlds, server configs, and backups survive uninstall and reinstall.
- The app's data directories are declared under `x-compose-app.folders` and are created and owned as `$PUID:$PGID` by Maison before every `up`, so the user can manage or remove them from the Files app.
- First-run credential seeding is guarded on `$APP_DIR/config/credits.json` in the `seed-config` step, so reinstalling over existing data never overwrites an existing admin account or configuration. It is keyed on a config file rather than on `once` deliberately: the `once` marker lives with the compose, which an uninstall-keep-data removes, so `once` would re-run on reinstall and reset a password the user had changed.
