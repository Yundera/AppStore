# Gitea — Rationale

## What deviation / exception is being requested

1. `gitea-runner` runs with `privileged: true`.
2. Gitea is configured with `[migrations] ALLOW_LOCALNETWORKS = true`.
3. The admin account is called `gitea_admin`, not the deployment's usual `admin`.

## Why it is necessary

**1. The privileged runner.** The point of shipping a runner at all is that a
workflow can build a container image. That needs a Docker daemon, and there are
only two ways to give a CI job one:

- mount the host's `/var/run/docker.sock` into the runner, which hands every
  workflow — including one that arrives from a mirrored third-party repository —
  full control of the host's daemon, i.e. root on the PCS; or
- give the runner a daemon of its own inside the container (`dind`), which
  requires `privileged`.

The second is the smaller exposure: the blast radius is the runner's own
container and its own image store, not the host's containers, volumes and
socket. It is also what upstream ships the `-dind` tag for.

The rootless dind variant (`0.6.1-dind-rootless`) would have avoided
`privileged` altogether, and was tried first. It does not start on this
platform: Ubuntu sets `kernel.apparmor_restrict_unprivileged_userns=1`, and
rootlesskit dies with `fork/exec /proc/self/exe: operation not permitted`.
Making it work means turning that protection off for the container
(`security_opt: apparmor=unconfined`), which weakens the host more than
`privileged` on a single container does. Revisit if the platform ever ships
that sysctl relaxed, or if upstream's runner learns to use the host's
user-namespace remapping.

**2. `ALLOW_LOCALNETWORKS`.** Gitea refuses by default to migrate or mirror
from an address on a private network. The app's most useful configuration —
mirroring a repository from another app on the same server, e.g. a Radicle
node's git endpoint at `http://radicle-api:8080/<rid>.git` — is exactly that
case. Without the flag the URL is rejected before any fetch is attempted.

**3. The admin username.** `admin` is on Gitea's reserved-name list (it
collides with the `/admin` route) and account creation fails with it.

## Security mitigations in place

- The runner is not on the shared `pcs` network. It sits on an app-internal
  bridge with Gitea and nothing else, so no other app can reach it, and it
  publishes no port.
- The runner's daemon is nested: its image store is a directory under the
  app's own AppData, and the containers it creates are invisible to, and
  cannot see, the host's daemon.
- `capacity: 1` in the runner config and a 2G memory limit bound what a
  runaway build can consume.
- Self-registration is disabled (`DISABLE_REGISTRATION`) and anonymous
  browsing is off (`REQUIRE_SIGNIN_VIEW`), so the forge starts closed with a
  single account whose password is the deployment's default app password.
- `ALLOW_LOCALNETWORKS` is reachable only by an authenticated user of this
  Gitea — with registration disabled, that is the owner. It widens what the
  owner can point a mirror at; it does not expose anything to an anonymous
  caller.
- The runner is severable: stopping the `gitea-runner` container leaves a
  fully working forge and removes the privileged container from the box. This
  is called out in `tips.before_install`.

## Alternatives considered and rejected

| Alternative | Why not |
|---|---|
| Host Docker socket in the runner | Any workflow, including one from a mirrored repo, gets root on the host. Strictly worse than a privileged container. |
| `0.6.1-dind-rootless` | Does not start under Ubuntu's unprivileged-userns restriction (see above); the workaround disables AppArmor for the container. |
| Ship no runner | Gitea Actions is the reason to choose Gitea over a plain git server here, and a runner cannot be added later without the same `privileged` decision. |
| Mirror over the public HTTPS address instead of `ALLOW_LOCALNETWORKS` | Works, but routes a same-box fetch out to the gateway and back, and breaks if the deployment has no public address. |

## Data protection

Everything that survives a restart is under `/DATA/AppData/gitea/`:
repositories and the SQLite database in `data/`, the rendered `app.ini` in
`config/`, the runner's registration in `runner/`, and the nested daemon's
image store in `runner-docker/`. Nothing is written outside that tree, and no
user directory (`/DATA/Documents`, `/DATA/Media`, …) is mounted into any
container.

The only credential the app generates is the runner registration token, which
is rewritten on every start and is worthless without network access to Gitea.
The admin password is the deployment's own `APP_DEFAULT_PASSWORD`; it is never
written to disk by this app beyond Gitea's own salted hash.
