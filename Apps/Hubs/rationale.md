# Hubs — Rationale

## What deviation / exception is being requested

Six of the eight services in the Hubs stack run as `user: "0:0"`:

- `db` (`postgres:14-alpine`)
- `hubs` (`hubsfoundation/reticulum:stable-855`) — Phoenix backend, the user-facing service
- `postgrest` (`mozillareality/postgrest:8`)
- `hubs-client` (`hubsfoundation/hubs:stable-3111`) — static asset server
- `spoke` (`hubsfoundation/spoke:stable-95`) — scene editor
- `dialog` (`hubsfoundation/dialog:stable-331`) — Mediasoup WebRTC SFU

The remaining two (`nearspark`, `photomnemonic`) inherit the default `PUID:PGID`.

## Why it is necessary

Every container running as root does so because its **upstream entrypoint expects to start as root and drop privileges itself**:

- `postgres:14-alpine` requires root to `chown -R postgres:postgres "$PGDATA"` before `gosu postgres` re-execs the postmaster as uid 70. Running it as a non-root user up front bypasses that chown and produces the `Permission denied: global/pg_filenode.map` failure mode (which is exactly what triggered the original outage on staging).
- The Hubs Foundation images (`reticulum`, `hubs`, `spoke`, `dialog`) ship with an entrypoint that templates `/home/ret/config.toml` from env vars at startup, writes it under `/home/ret`, and then exec's the application. The template-render step needs write access to a path created at image build time as root.
- `mozillareality/postgrest` has the same upstream-defined entrypoint pattern.

Forcing these images to run unprivileged would require maintaining a downstream rebuild for each — a maintenance burden disproportionate to the security improvement, given the AppData-only volume topology described below.

## Security mitigations in place

- **All bind mounts stay inside `/DATA/AppData/hubs/`.** No service mounts `/DATA/Documents`, `/DATA/Downloads`, `/DATA/Media`, or `/DATA/Gallery`. A root-process escape from any Hubs container can only reach the app's own AppData tree, not user-owned content.
- **No `ports:` on the user-facing services.** Only `dialog` exposes host ports (UDP/TCP 40000-40050), required by the Mediasoup SFU for WebRTC media. Everything else is reachable solely via the internal `hubs-net` network and the `pcs` network through Caddy reverse-proxy labels.
- **Caddy gateway termination.** All HTTP/HTTPS traffic is terminated by the PCS's `mesh-router-caddy`, not the Hubs containers themselves. Public Caddy labels point at internal `expose:` ports on the `pcs` network, so direct host-port exposure is limited to the SFU media range.
- **Per-service `cpu_shares`** prevent a runaway service (e.g. compromised `nearspark` thumbnail proxy) from starving the host.
- **Bootstrap secrets are mode `0600`**, owned by `PUID:PGID`. The compose `.env`, `perms.key.pem`, and `perms.pub.pem` are not world-readable.
- **Postgres data dir is owned by uid 70** (the in-image postgres user), enforced on every install by an `chown -R 70:70` in `pre-install-cmd` so a stray framework-level chown can't relock it and crashloop the database.

## Alternatives considered and rejected

1. **Rebuild upstream images with `USER 1000`.** Rejected — would require maintaining seven downstream forks (`reticulum`, `hubs`, `spoke`, `dialog`, `nearspark`, `photomnemonic`, plus `postgres` if we wanted full coverage) and continuously rebasing on Hubs Foundation's stable tags. The maintenance cost outweighs the marginal security benefit given the AppData-only mount topology.
2. **Run Postgres as `user: "70:70"` directly.** Rejected — the Postgres image's chown step inside the entrypoint requires root. Skipping it leaves `pgdata` owned by uid 1000 (host PUID) and the postgres process (uid 70) cannot read its own data files. We hit exactly this failure mode on the initial Hubs rollout on staging.
3. **Wrap each upstream image with a sidecar that does the chown then signals the main service.** Rejected as over-engineered for the threat model.

## Data protection

- All persistent state lives under `/DATA/AppData/hubs/` and survives uninstall/reinstall. The compose's `pre-install-cmd` calls `hubs-seed bootstrap` which is **idempotent** — on re-run it preserves existing secrets in `.env` (DB password, NODE_COOKIE, GUARDIAN_KEY, PHX_KEY, DASHBOARD_ACCESS_KEY, POSTGREST_PASSWORD, PERMS_KEY) and reuses the existing RSA keypair. Regenerating the keypair would invalidate every minted Guardian admin token.
- Framework-passthrough env vars (`APP_DOMAIN`, `APP_PUBLIC_IP_DASH`, `APP_PUBLIC_IPV4`, `APP_EMAIL`, `PUID`, `PGID`) **are** refreshed on every install — that is intentional, so a redeploy fixes drifted Caddy labels (the original outage's root cause).
- The compose's `.env` file is mode `0600`. The RSA private key (`perms.key.pem`) is mode `0600`. Both are owned by `PUID:PGID`.
- No user-owned content (Documents/Downloads/Media/Gallery) is touched by any Hubs container; the blast radius of a root container escape is bounded to `/DATA/AppData/hubs/`.
