# Lamplighter — Rationale

## What exception is requested

One service, `lamplighter-docker` (`tecnativa/docker-socket-proxy`, pinned by tag and digest),
takes two deviations, and they are the same thing:

1. It **mounts the host's `/var/run/docker.sock`**, which is outside `/DATA`.
2. It **runs as root** (no `user:`), as the image does, because the socket is root's.

Every other service is unchanged: the backend runs as `$PUID:$PGID` on its own app folder, the
gate and the MCP sidecar touch no files.

## Why it is necessary

Since 0.7.0, Lamplighter runs each LLM session in a **sandbox**: a fresh, credential-free
container where the model can run the repository's tests and package manager. Each fix is then
judged by the repository's own tests on the base and on the proposal, and the scanners
(osv-scanner, Gitleaks) re-run on it, each in a new container. Creating those containers needs
the Docker daemon. Without it, nothing of a repository runs: the app goes back to the 0.4
behaviour, where a fix is reviewed by a second model and never built or tested.

## Mitigations

- **The backend never gets the socket.** Only the proxy mounts it. The backend reaches the proxy
  at `tcp://lamplighter-docker:2375` on `lamplighter-docker`, an `internal: true` network with
  no route out, which only the backend and the proxy are on. Nothing on `pcs`, and nothing
  outside the box, can reach the proxy.
- **The proxy passes only what a sandbox needs**: containers (create, start, restart, exec,
  archives), images, volumes and networks. Swarm, secrets, configs, plugins, system and
  everything else are refused.
- **The proxy filters by endpoint, not by request body.** So "named volumes only, never a host
  bind, every capability dropped, a fixed non-root uid (10001), CPU, memory and PID limits" is
  Lamplighter's own rule, in `server/src/sandbox/spec.ts` upstream, with a test. The sandboxes
  sit on their own network (`lamplighter-sandbox`), not on `pcs`, so they cannot reach Beacon,
  the admin MCP or the other apps. They get no forge token: pushing stays in the backend.
- `audience: technical` keeps the app out of sight unless the owner shows technical apps, and
  the description states the socket requirement before install.
- The sandbox can be turned off in **Settings → Sandbox**. Stopping `lamplighter-docker` has
  the same effect.

## Alternatives considered

- **Shipping 0.7.2 without the proxy** (sandbox off). It works, but it drops the feature the
  0.7 release is for, and upstream's own listing ships the proxy.
- **Mounting the socket into the backend**, which upstream supports in development
  (`unix:///var/run/docker.sock`). Rejected: it would hand the full Docker API to the process
  that runs model sessions.
- **Rootless Docker or a remote daemon.** Neither exists on a PCS.

## Data protection

The proxy has no bind mount but the socket, and no data. The sandboxes use only named Docker
volumes: a per-session work volume, removed with the session (and swept at boot), plus two shared
caches, `lamplighter-mise` (toolchains) and `lamplighter-cache` (packages), capped by
`sandbox.cache_max_gb` (20 GB by default). Lamplighter creates these, the `lamplighter-sandbox`
network and the images it runs (the base image, mise, and the scanners osv-scanner and Gitleaks) on first use, **outside the compose project**. An uninstall
does not remove them. They hold no user data, and an owner who wants the space back removes
them with `docker volume rm lamplighter-mise lamplighter-cache` and
`docker network rm lamplighter-sandbox`.
