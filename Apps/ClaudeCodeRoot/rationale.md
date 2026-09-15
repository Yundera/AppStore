# Claude Code (root) — Rationale

## What deviation / exception is being requested

This is the **privileged** variant of the Claude Code app. It asks for four
deviations at once, and they only make sense together:

1. **Runs as `user: 0:0`** — the container's supervisor manages ttyd and the
   auth/MCP process, and the app's job is host administration.
2. **Mounts `/var/run/docker.sock`** read-write, giving the container full
   control of the host Docker daemon (and therefore, via a privileged helper
   container, of the host filesystem).
3. **Mounts the host directory `/home/claude/.ssh/`** onto `/host_ssh/`, outside
   `/DATA` entirely — the key material for SSH-ing into the host VM.
4. **Mounts `/DATA` itself, read-write** — not just
   `/DATA/AppData/clauderoot/`, so it reaches `/DATA/Documents`,
   `/DATA/Downloads`, `/DATA/Media`, `/DATA/Gallery` **and** every other app's
   data under `/DATA/AppData`.

Its `pre-install-cmd` also provisions a dedicated **`claude` user on the host**
with `NOPASSWD:ALL` sudo and a writable `~/.ssh`, by breaking out of the
CasaOS container namespace through the Docker socket
(`docker run -v /:/host alpine:3.20 chroot /host …`).

The net effect is deliberate and total: **this app can do anything on the PCS
that its owner could do over SSH as root.**

## Why it is necessary

The app exists to be the owner's administration and debugging console for their
own PCS. The tasks it is installed for — inspect why a container will not start,
edit a compose file, pull a new image, recover a broken app's data directory,
run a system update — are exactly the tasks that require the Docker socket, a
whole-`/DATA` view and a shell on the host. An administration tool confined to
its own AppData directory can administer nothing.

The host `claude` account exists so that host access is a *named, revocable*
identity rather than reuse of the server owner's own account: the operator can
see it in `/etc/passwd`, audit its `authorized_keys`, and delete it.

The sandboxed sibling app, **`ClaudeCode`**, is the answer for anyone who does
not want this. It ships the same image with `MCP_ENABLED=true` and none of the
four mounts above — no Docker socket, no host SSH, no `/DATA` — and is the app
to install for programmatic automation (e.g. n8n driving Claude over MCP).
Splitting the two apps *is* the mitigation: the privileged capability is opt-in
by choosing this app rather than that one.

## Security mitigations in place

- **Disclosed before install.** `x-casaos.description` and
  `x-casaos.tips.before_install` both state, in English and Chinese, that this
  is the privileged variant with Docker-socket and host-SSH/sudo access to the
  VM, and both name the sandboxed `ClaudeCode` app as the alternative.
- **Authentication is on by default and never hardcoded.** Every route is behind
  the auth layer on port 9090: `/login` and `/logout` are served by it directly,
  and everything else goes through Caddy `forward_auth` to `/auth`, redirecting
  to `/login` on 401. The password comes from `$APP_DEFAULT_PASSWORD`, which is
  generated per server at install time.
- **MCP automation is turned off** (`MCP_ENABLED=false`). The programmatic
  endpoint that lets another service drive Claude Code is deliberately not
  available on the privileged app, so the only way to reach this shell is an
  interactive, authenticated browser session. `MCP_ENABLED=true` belongs to the
  sandboxed sibling, which has no host access.
- **No `privileged: true` and no `cap_add`.** The escalation is exactly the four
  mounts listed above and nothing more; the container gains no kernel
  capabilities beyond the Docker default set.
- **No published host ports.** `expose:` only, on the external `pcs` network, so
  8080 and 9090 are reachable solely through the gateway-terminated Caddy
  routes.
- **Pinned image**, `ghcr.io/worph/claude-code-container:1.0.26`, and a pinned
  `alpine:3.20` in the pre-install hook — no `:latest` anywhere.
- **Resource limits**: `cpu_shares: 70`, `memory: 2048M`.
- **The host provisioning hook is idempotent and non-fatal.** Each step is
  guarded (`id claude`, `[ ! -f /etc/sudoers.d/claude ]`) and the script always
  exits 0, so a host where the break-out is unavailable still installs the app —
  it simply has no host-SSH feature. The `claude` account is created with `*` as
  its password field, i.e. no password: it is reachable by key only, never by
  password login.
- **Nothing is copied into the SSH mount.** `/home/claude/.ssh/` is mounted so
  the user can place their *own* key there; the hook only ensures the directory
  and an empty `authorized_keys` exist with `0700`/`0600`. The app ships no key
  material.

## Alternatives considered and rejected

- **Drop `user: 0:0` and run as `$PUID:$PGID`.** Rejected: the container's
  supervisor needs to start ttyd and the auth process, and a non-root user
  cannot use a root-owned `/var/run/docker.sock` nor write outside its own
  files. It would also be security theatre — a container with the Docker socket
  is root-equivalent on the host whatever UID it runs as.
- **Mount only `/DATA/AppData/clauderoot/` and drop the whole-`/DATA` mount.**
  Rejected: it removes the recovery and inspection use case (reading another
  app's data directory to work out why it is broken) which is the single most
  common reason this app is installed.
- **Mount `/DATA` read-only.** Rejected: repairing a config file or a stuck
  database is a write.
- **Drop the Docker socket and rely on host SSH alone.** Rejected: SSH is the
  *optional* half — it needs a key the user has to install — while the socket is
  what makes the app useful out of the box. Dropping the socket would also break
  the host-user provisioning that makes the SSH path possible in the first
  place.
- **Reuse the server owner's account instead of creating a `claude` host user.**
  Rejected: a dedicated account is auditable and can be removed with
  `userdel claude` and `rm /etc/sudoers.d/claude`, without touching the owner's
  own credentials.
- **Merge this app with the sandboxed `ClaudeCode` app and gate the access
  behind an environment variable.** Rejected: a checkbox that silently turns a
  confined app into a root shell is worse than two apps whose names and
  descriptions say what they are. Keeping them separate is what lets the
  automation-facing app stay unprivileged.

## Data protection

The app's own state lives under `/DATA/AppData/clauderoot/` —
`workspace/` and `config/`, both declared in `x-compose-app.folders` and owned
by `$PUID:$PGID` — and survives uninstall/reinstall.

Beyond that, there is no technical boundary between this app and the rest of the
PCS: the protection is the authentication in front of it and the owner's
decision to install it. Practically that means:

- Change the generated password from the app settings, and treat it as a root
  password for the whole server, because that is what it is.
- Install this app only on a PCS you administer yourself. If what you want is
  Claude Code for coding or for automation, install **`ClaudeCode`** instead —
  same tool, no host access.
- To revoke host access after uninstalling: delete the host account and its sudo
  rule (`userdel -r claude`, `rm /etc/sudoers.d/claude`). Uninstalling the app
  removes the container, not the account the pre-install hook created.

## Source repository

The Docker image is built from <https://github.com/yundera/claude-code-container>
and published as `ghcr.io/worph/claude-code-container`.
