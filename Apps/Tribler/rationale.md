# Tribler — Rationale

## What deviation / exception is being requested

1. **`architectures: [amd64]` only** — the app is not published for `arm64`.
2. **Tribler's own REST API key is disabled** (`CORE_API_KEY=""`), i.e. the *backend* application ships without its built-in auth gate.
3. **A `socat` shim container** shares the backend's network namespace to expose Tribler on the `pcs` network.

## Why it is necessary

1. **amd64 only:** Upstream publishes `ghcr.io/tribler/tribler` for `linux/amd64` exclusively — there is no arm64 manifest (verified against `v8.4.2`). Listing arm64 would advertise an image that cannot be pulled.

2. **Disabled internal key:** Tribler's only built-in auth is a static `api/key` passed as a `?key=…` URL query parameter or `X-Api-Key` header. That model is incompatible with a clean SSO experience (the secret would have to live in the URL). Instead the app is fronted by the **`nginx-hash-lock` OIDC sidecar**, which gates *all* access through the PCS's built-in Authelia single sign-on — the recommended Yundera auth method. The Tribler backend is therefore **not the auth boundary** and runs with its key emptied so the UI works seamlessly behind SSO.

3. **socat shim:** Tribler v8.4.2 hard-binds its REST/Web UI to `127.0.0.1` inside the container. This was verified empirically to be **non-overridable**: there is no working environment variable (`CORE_API_BIND_ADDRESS` is ignored), and any `api/http_host` written to `configuration.json` is reset to `127.0.0.1` on every boot. A separate container therefore cannot reach it. The `tribler-fwd` container runs `socat` with `network_mode: service:tribler-backend` (shared network namespace) and republishes `127.0.0.1:8085` on `0.0.0.0:8086`, making the UI reachable as `tribler-backend:8086` on the `pcs` network for the sidecar — without exposing it publicly.

   Relatedly, Tribler resets its default save path to `$HOME/Downloads` on every boot, so rather than fight it, `HOME=/state` and the user folder is bind-mounted at `/DATA/Downloads → /state/Downloads`. Downloads land in the user-visible `/DATA/Downloads` with correct `PUID:PGID` ownership (verified on a live PCS).

## Security mitigations in place

- **Authentication is enforced** for every request by the OIDC sidecar (Authelia SSO). Only the sidecar (`container_name: tribler`) carries Caddy labels and is publicly reachable; the backend has no `ports:` and no public labels — it is reachable only on the internal `pcs` network. Verified on a live PCS: the public URL `302`-redirects unauthenticated requests to the Authelia OIDC login.
- The `socat` shim listens only on the backend's internal namespace; it has no Caddy labels and is not published to the host.
- The backend runs as **`$PUID:$PGID`** (not root), so files written to the user-visible `/DATA/Downloads` carry correct ownership.
- Memory limits and `cpu_shares` set on every service.
- Per-service JSON log rotation.

## Alternatives considered and rejected

- **Expose Tribler directly with its `?key=` URL auth.** Rejected: weak, leaks the secret in the URL/history, and does not integrate with the PCS SSO that the store mandates.
- **Override the bind host via env var or seeded `configuration.json`.** Rejected: empirically proven non-functional in v8.4.2 (env ignored; config reset every boot). The `socat` shim is the only reliable approach.
- **Run the backend as root to use the image's default `/root/.Tribler`.** Rejected: downloads in `/DATA/Downloads` would be root-owned, violating the dual-permission model. `HOME`/`TSTATEDIR=/state` lets it run as `$PUID:$PGID` instead.

## Data protection

- All state (identity keys, databases, settings) lives under `/DATA/AppData/tribler/state`; downloaded files live under `/DATA/Downloads`. Both persist across uninstall/reinstall.
- The `pre-install-cmd` only creates the state directory and fixes ownership; it never writes or overwrites application data, so user preferences and the node identity are preserved on reinstall and version upgrades.
