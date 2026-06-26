# Crafty Controller Rationale

## What deviation / exception is being requested

This app deviates from the default AppStore requirements in three ways:

1. The container runs as root (`user: "0:0"`).
2. It does not use the recommended `nginx-hash-lock` OIDC sidecar. Access control is provided by Crafty Controller's own built-in login, enabled by default.
3. `x-casaos.webui_port` is set to `80` even though the container's panel is exposed on `8443`.

## Why it is necessary

**Root.** Crafty Controller creates, launches, and supervises Minecraft (Java and Bedrock) server processes under `/crafty/servers`, writing JVM working directories and managing child processes. It expects to run as root and does not reliably start or spawn server processes under a non-root UID. Upstream ships and supports the image as a root container.

**No sidecar.** The Crafty panel speaks HTTPS on `8443` with a self-signed certificate and depends on a persistent WebSocket (WSS) connection for the live console and server status. Fronting it with the `nginx-hash-lock` sidecar would add a second TLS hop in front of the self-signed upstream plus a websocket upgrade path the sidecar is not configured to pass through, which breaks the live console. Crafty enforces authentication on every panel route (no anonymous access), which the guide accepts as a valid built-in login gate. The admin password is seeded from `$APP_DEFAULT_PASSWORD` at install time, so authentication is enabled by default with no manual step.

**webui_port.** The Caddy labels publish the clean subdomain `crafty-<domain>` over public HTTPS (port 443) and proxy it to the container's `8443`. CasaOS builds the dashboard "open" link from `webui_port`. Setting `webui_port: 8443` makes the dashboard construct a broken link of the form `8443-crafty-<domain>:8443` instead of the working clean subdomain. `webui_port: 80` yields the correct public URL. The value therefore reflects the public gateway port, not the container's internal panel port.

## Security mitigations in place

- The panel backend is reachable only through Caddy on the `pcs` network. `expose: 8443` is not a host port binding, so the panel is never published directly to the host.
- Authentication is enabled by default. The admin account is created at install with the per-instance `$APP_DEFAULT_PASSWORD`, and the before-install tip instructs the user to change it immediately after first login.
- No credentials are hardcoded in the compose file. The password comes from the injected `$APP_DEFAULT_PASSWORD`.
- Resource limits cap the container at 2048M of memory, and `cpu_shares: 50` prevents it from starving other apps under load.
- The published game ports (`25500-25600/tcp`, `19132/udp`) and the optional Dynmap port (`8123`) are required for Minecraft clients and the live map to reach the servers from the internet. These are game-server endpoints, not panel routes; the management panel itself stays behind authentication.

## Alternatives considered and rejected

- **Running as `$PUID:$PGID`:** Crafty fails to manage server processes and write its working directories without root. Rejected on functional grounds.
- **`nginx-hash-lock` sidecar in front of the panel:** breaks the live console, because the self-signed HTTPS upstream plus the required WSS upgrade do not pass cleanly through the sidecar. Rejected because it makes the core feature unusable. Crafty's own login is an accepted alternative under the guide.
- **`webui_port: 8443`:** produces a broken dashboard open-link. Rejected in favor of `80`, which routes to the working public HTTPS subdomain.

## Data protection

- All persistent state is mapped under `/DATA/AppData/$AppID/` (`backups`, `logs`, `servers`, `config`, `import`), so user worlds, server configs, and backups survive uninstall and reinstall.
- The app folder is owned by `$PUID:$PGID` (set in the pre-install command) so the user can manage or remove it from the Files app.
- First-run credential seeding is guarded by a `.initialized` sentinel, so reinstalling over existing data never overwrites an existing admin account or configuration.
