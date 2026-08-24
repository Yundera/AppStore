# Netdata — Rationale

## What deviation / exception is being requested

Three deviations, all in `netdata-backend` (the monitoring agent). The
`netdata-proxy` AppShield sidecar deviates in nothing — it is the stock OIDC
sidecar, unprivileged, with no capabilities and no host mounts.

1. **`user: 0:0`** — the agent runs as root rather than `$PUID:$PGID`.
2. **Two added capabilities** — `SYS_PTRACE` and `SYS_ADMIN`, plus
   `security_opt: apparmor:unconfined`.
3. **Eight bind mounts outside `/DATA`**, all read-only:

   | Host path | Mounted at | What it is read for |
   | --- | --- | --- |
   | `/proc/` | `/host/proc/` | The primary metrics source: CPU, load, memory, swap, interrupts, per-interface network counters, per-disk I/O, per-process stats. Without it the agent reports on its own container and nothing else. |
   | `/sys/` | `/host/sys/` | cgroup accounting (this is how per-container CPU/memory charts exist), block-device queues, thermal zones, power supplies, hardware sensors. |
   | `/var/log/` | `/host/var/log/` | System and web-server log collectors (`systemd-journal`, `web_log`). |
   | `/etc/passwd` | `/host/etc/passwd` | Resolve numeric UIDs seen in `/host/proc` to usernames on the users/processes charts. |
   | `/etc/group` | `/host/etc/group` | Same, for GIDs. |
   | `/etc/os-release` | `/host/etc/os-release` | Identify the host distribution and version on the dashboard header. |
   | `/etc/localtime` | `/etc/localtime` | Render chart timestamps in the server's timezone. |
   | `/var/run/docker.sock` | `/var/run/docker.sock` | Resolve cgroup ids to human-readable container names. |

The app state itself is *not* an exception: `config/`, `lib/` and `cache/` all sit
under `${DATA_ROOT:-/DATA}/AppData/$AppID/` and are the only writable mounts in the
app.

## Why it is necessary

Netdata is a whole-machine monitor. Every one of the mounts above is a place the
kernel publishes a statistic; a container that cannot read them can only report on
itself, which is not the app the user installed. The `/host/...` prefix is upstream
Netdata's own convention (`NETDATA_HOST_PREFIX`) for exactly this arrangement, and
the mount list here is upstream's documented Docker deployment, not a widened
version of it.

- **Root.** `/proc/<pid>/` entries for processes owned by other users, and several
  `/sys` nodes, are readable only by root. The per-application and per-user
  breakdowns — the reason to run Netdata rather than read `top` — depend on them.
  Running as `$PUID:$PGID` yields a dashboard with the system-wide charts populated
  and every per-process chart empty.
- **`SYS_PTRACE`.** `apps.plugin` reads `/proc/<pid>/io`, `/proc/<pid>/fd` and
  `/proc/<pid>/status` for processes outside its own PID namespace. That is a
  ptrace-class read and is refused without the capability even as root.
- **`SYS_ADMIN`.** Required by the eBPF and `perf` collectors, and by
  `go.d`'s access to some `/proc` and `/sys` entries. It is the capability upstream
  names in its Docker instructions.
- **`apparmor:unconfined`.** On Ubuntu/Debian hosts — which is what a PCS runs — the
  default Docker AppArmor profile denies reads under `/proc/<pid>/` regardless of
  capabilities, so the profile has to be lifted for `SYS_PTRACE` to mean anything.
- **The Docker socket.** Netdata reads container cgroups from `/host/sys` whether or
  not the socket is present; the socket only supplies the *names*. Without it, the
  per-container charts are labelled with 64-character cgroup hashes, which makes the
  Docker section of the dashboard unusable in practice.

## Security mitigations in place

- **Not privileged.** `privileged: true` was removed from both services. The agent
  holds exactly two capabilities, named explicitly and listed above; it does not get
  the full capability set, unrestricted device access, or a writable `/sys`.
- **Every host mount is read-only.** All eight carry `:ro`. The agent cannot write to
  `/proc`, `/sys`, `/var/log`, or any `/etc` file, and it has no mount anywhere else
  on the host — no `/DATA/Documents`, `/DATA/Downloads`, `/DATA/Media`, `/DATA/Gallery`,
  and no other app's `AppData` directory.
- **The sidecar carries none of this.** `netdata-proxy` — the only container Caddy can
  reach — is unprivileged, has no capabilities, no host mounts, and cannot see the
  Docker socket. An attacker at the public edge has to get through AppShield's OIDC
  gate *and* then through the app-internal network before any of the above is in
  reach.
- **No public route to the agent.** `netdata-backend` sits only on the app-private
  `netdata-internal` bridge, carries no Caddy labels and publishes no host port. The
  agent's own API and dashboard are reachable only via the authenticated sidecar.
- **Authentication is on by default**, via the platform's Authelia SSO (AppShield
  OIDC). There is no unauthenticated read path to the metrics.
- **Netdata Cloud is not configured.** The agent claims nothing and streams nowhere;
  all metrics stay in `/DATA/AppData/netdata/lib/` on the machine being monitored.
- **Resource limits** bound both containers (`cpu_shares: 90`, `memory: 512M`,
  `cpus: 1.0` on the agent; `cpu_shares: 80`, `memory: 256M` on the sidecar), so a
  runaway collector cannot starve the rest of the PCS.

### The Docker socket is the residual risk, and it is real

`- /var/run/docker.sock:/var/run/docker.sock:ro` makes the *socket file* read-only.
It does **not** make the Docker API read-only: a process that can talk to that socket
can create a container, and a container it creates can be privileged and can mount
the host root. So this mount is, on its own, equivalent to host root for anything
that achieves code execution inside `netdata-backend`.

What bounds it here is that nothing reaches `netdata-backend` from outside: it has no
published port, no Caddy label, and no route from the shared `pcs` network — only the
sidecar, behind SSO, can address it, and the sidecar proxies to port 19999 only.

The hardening that would remove the risk rather than bound it is a read-only Docker
API proxy (`tecnativa/docker-socket-proxy` with `CONTAINERS=1` and everything else
off) in place of the direct mount. It is recorded here as the known next step for
this app rather than done silently, because it adds a third container to an app whose
current shape has been deployed and tested.

## Alternatives considered and rejected

- **Run as `$PUID:$PGID` and drop the capabilities.** Rejected: the per-process,
  per-user and per-container charts go empty. What remains is roughly what the PCS
  dashboard already shows, so the app stops being worth installing.
- **Keep `privileged: true` instead of enumerating capabilities.** Rejected, and this
  is what changed: `privileged` grants the whole capability set plus device access, of
  which the agent uses two capabilities. Enumerating them is strictly smaller and is
  what upstream documents.
- **Keep `NET_ADMIN`.** Rejected and removed. It was on both services; nothing in
  Netdata's documented Docker deployment asks for it, and network counters are read
  from `/host/proc/net/`, which needs no capability at all.
- **Mount `/proc` and `/sys` writable.** Never needed — the agent only reads them.
- **Drop the `/var/log` mount.** Considered. It is the narrowest of the eight in value
  (it feeds the log collectors, which are optional), but it is read-only, and removing
  it silently disables `systemd-journal` and `web_log` for users who expect them.
  Retained and disclosed rather than removed.
- **Drop the Docker socket entirely.** Considered; see above. It degrades the Docker
  section of the dashboard to cgroup hashes, which is the feature the app's
  `before_install` tip advertises. The socket proxy is the better answer and is the
  recorded next step.

## Data protection

Netdata stores no user documents. What it holds is telemetry about the machine —
metric history in `/DATA/AppData/netdata/lib/`, its dbengine cache in
`.../cache/`, and configuration in `.../config/` — and all three are ordinary
AppData binds, so they survive uninstall/reinstall with the rest of the app folder
and are removed with it.

That telemetry is still sensitive: process names, usernames and container names
describe what the owner runs. It is protected the same way the rest of the app is —
the agent is unreachable except through the SSO-gated sidecar, nothing is sent off
the machine, and no third-party account is involved. The read-only host mounts mean
the app can observe the system but cannot alter it; the one exception to that
statement is the Docker socket, which is documented above.
