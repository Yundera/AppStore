# SearXNG — Rationale

## What exception is requested

`permissions`: the backend (`searxng-backend`) adds five capabilities after dropping all of
them — `cap_drop: [ALL]`, then `cap_add: CHOWN, FOWNER, SETGID, SETUID, DAC_OVERRIDE`.

## Why it is necessary

The upstream image (`searxng/searxng`) starts as root and its entrypoint prepares the two
mounts before it drops to its own unprivileged `searxng` user:

- **CHOWN** — it chowns `/etc/searxng` and `/var/cache/searxng` (the bind mounts under
  `/DATA/AppData/searxng/`) to the `searxng` user.
- **FOWNER** — it copies `settings.yml` from the image's template with `cp -p`, which sets
  ownership and mode on a file in a directory it does not own.
- **DAC_OVERRIDE** — it reads and writes those mounts while still root, whatever their owner
  (Maison creates them as `$PUID:$PGID`).
- **SETUID / SETGID** — it then switches to the `searxng` user to run the server. Without
  them the switch fails and the container exits.

Upstream's own compose uses the same shape (`cap_drop: ALL`, then `CHOWN`, `SETGID`,
`SETUID`). `FOWNER` and `DAC_OVERRIDE` are added here because the mounts are created by
Maison as `$PUID:$PGID` before the container first starts, rather than by the container.

## Mitigations

- Every other capability is dropped. No `privileged`, no host network, no host PID namespace,
  no device access.
- The only mounts are the app's own `config/` and `cache/` folders. No user folder and nothing
  outside `/DATA/AppData/searxng/`.
- The server process itself runs as the unprivileged `searxng` user once the entrypoint has
  finished.
- The backend is on the app's internal network only and publishes no port. It is reached
  solely through its AppShield sidecar, which adds no capabilities.

## Alternatives considered

- **`user: $PUID:$PGID`.** The entrypoint's chown and user switch then fail, and the
  container does not start.
- **No added capabilities.** Same failure: the entrypoint cannot prepare its mounts.

## Data protection

The mounts hold only SearXNG's settings and its cache. No user data is reachable from the
container.
