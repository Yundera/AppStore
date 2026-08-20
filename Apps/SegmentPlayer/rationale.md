# SegmentPlayer — Rationale

## What deviation / exception is being requested
The `segmentplayer-backend` service runs as `user: 0:0` (root) while mounting two user
directories, `/DATA/Downloads` and `/DATA/Media`. CONTRIBUTING requires `user: $PUID:$PGID`
for containers that access `/DATA/Documents|Downloads|Gallery|Media`.

The `segment` service (the AppShield sidecar) also runs as `user: "0:0"`, matching the
AppShield reference deployment. It mounts no volumes.

## Why it is necessary
`ghcr.io/worph/segmentplayer` is a supervisord-managed nginx-vod-module + FFmpeg stack.
Three separate things in the image require uid 0 at startup:

- `/entrypoint.sh` runs `envsubst … > /usr/local/nginx/conf/nginx.conf` on every boot,
  writing into the root-owned `/usr/local/nginx/conf/` directory.
- `/etc/supervisord.conf` declares `user=root` and writes
  `/var/log/supervisor/supervisord.log` and `/var/run/supervisord.pid`.
- nginx binds port 80, a privileged port.

Any one of these fails the container start under a non-root uid.

## Security mitigations in place
- **Both user-directory mounts are read-only** (`:ro`). The container cannot create,
  modify or delete anything under `/DATA/Downloads` or `/DATA/Media`.
- **The backend is not publicly reachable.** It sits only on the internal
  `segment-internal` bridge network. Only the AppShield sidecar joins `pcs`, so every
  request reaches the backend through AppShield's OIDC gate.
- No Caddy labels on the backend — it has no public route of its own.
- No privileged mode, no host networking, no Docker socket, no capability grants.
- Memory limit of 2G and `cpu_shares: 70` on the backend.
- The transcoder resolves every requested path with `os.path.realpath()` and rejects
  anything that escapes the media root, so the read-only mounts cannot be traversed out of.

## Alternatives considered and rejected
- **`user: $PUID:$PGID`** — breaks the container at startup for the three reasons above.
  Verified against `ghcr.io/worph/segmentplayer:1.4.2`.
- **Moving nginx to an unprivileged port via `NGINX_PORT`** — removes only the port-binding
  obstacle; the `envsubst` write into `/usr/local/nginx/conf/` and supervisord's `user=root`
  still fail. It would also desynchronise AppShield's `BACKEND_PORT`.
- **Rebuilding the image to run rootless** (nginx on 8080, writable conf dir, supervisord
  as a non-root user) — the correct long-term fix, but it is an upstream image change and
  cannot be made from the app store.
- **Read-write mounts with `$PUID:$PGID`** — rejected regardless; the app only ever reads
  media, so read-only root is a smaller exposure than read-write non-root.

## Data protection
- The app stores no user data. It has no `/DATA/AppData/` volume; the transcode cache lives
  at `/data/cache` inside the container and is intentionally ephemeral — it is regenerated
  on demand and holds nothing that needs to survive a restart.
- User media in `/DATA/Downloads` and `/DATA/Media` is mounted read-only, so an
  uninstall/reinstall cycle cannot touch it.
