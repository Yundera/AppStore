# Terminal — Rationale

## What deviation / exception is being requested

Four deviations, and they only make sense together:

1. **`terminal-ttyd` runs `privileged: true` with `pid: host`, as `user: root`.**
   Together these let it enter the host's namespaces (`nsenter --target=1`).
2. **The app writes outside its own data folder, on the host.** At every
   container start it adds one line to `/home/admin/.ssh/authorized_keys`: its
   own public key, marked with the comment `yundera-terminal`.
3. **Each terminal session is an SSH login as `admin`**, the PCS account with
   passwordless `sudo`. The net effect is deliberate and total: **this app can
   do anything on the PCS that its owner could do over SSH as root**, including
   everything under `/DATA` (Documents, Downloads, Media, Gallery, every other
   app's data) and the system files outside it.
4. **`/DATA/AppData/terminal/ssh/` is written from the host's namespace, not
   through a bind mount.** The setup runs after `nsenter --mount`, so it works on
   host paths directly. The path still starts with `${DATA_ROOT:-/DATA}`.

## How it works

Two steps, both in the `terminal-ttyd` container:

1. **At container start**, the `TERMINAL_SETUP` script runs in the host's mount
   namespace, using the host's own `/bin/sh`, `ssh-keygen` and `getent`. It:
   - generates `${DATA_ROOT:-/DATA}/AppData/terminal/ssh/id_ed25519` once
     (root-only);
   - makes sure `admin`'s `authorized_keys` holds exactly one `yundera-terminal`
     line for that key. It rewrites the file with every other line kept as it
     was, via a temporary file renamed into place;
   - writes `known_hosts` from the host's own `/etc/ssh/ssh_host_*_key.pub`.

   It is idempotent: a restart that finds everything in place changes nothing.
2. **For each browser session**, ttyd runs
   `nsenter --target=1 --mount --uts --ipc --net --pid -- ssh … admin@localhost`.
   That is the host's own `ssh` client dialling the host's own loopback. sshd
   then provides a real login session.

The app provisions itself. There is no `pre-install-cmd` and nothing to run on
the host beforehand. The same compose file works as a store install or as a
platform stack.

## Why it is necessary

The app exists to be the owner's shell on their own PCS. The tasks it is
installed for are exactly the ones that need the real host. For example:
inspect why a container will not start, edit a compose file or a system
config, fix permissions on a user directory, recover a broken app's data, run
a package update.

The previous version ran `chroot /host bash` over a read-write bind of `/`. That
borrowed only the host's **files**. Everything else stayed the container's:

| | chroot (before) | SSH session (now) |
|---|---|---|
| Hostname, `ip a`, `ss`, `localhost` | the container's | the host's |
| `ps` / `kill` | host `/proc`, but the container's PID namespace, so they disagree | the host's |
| tty | container `/dev/pts` | a host pty from sshd |
| Shell | non-login root `bash`, no profile | `admin`'s login shell, with profile and `sudo` |
| Memory and lifetime | every command capped by the container's limits, and killed when it restarts | the host's sshd session |

The SSH session is also what the PCS admin console's own Terminal panel opens
(`ssh admin@<host>`), so both terminals now behave the same.

Why each privilege is needed:

- **`privileged` + `pid: host`**: entering PID 1's mount, UTS, IPC, network and
  PID namespaces needs both.
- **An `authorized_keys` entry**: without a credential, sshd will not open the
  session. Password authentication is disabled on a PCS.

## Security mitigations in place

- **Authentication is on by default and is the PCS's own.** The published
  service is the AppShield gate (`ghcr.io/yundera/appshield`). It registers with
  the PCS OIDC provider (`auth-registrar`) and refuses every request that does
  not carry a valid Yundera session. There is no app-local password.
- **The shell is never published directly.** `terminal-ttyd` has no `ports:` and
  is not on the `pcs` network. It sits on the app-private `terminal-internal`
  bridge and is reachable only from the gate. Only the gate carries the
  `caddy_0/1/2` labels.
- **The key only works from the server itself.** Its `authorized_keys` line
  carries `from="127.0.0.1,::1"` plus `no-agent-forwarding`,
  `no-port-forwarding` and `no-X11-forwarding`. A copy of the private key taken
  off the box opens nothing. The private key is `0600 root` in a `0700 root`
  folder.
- **Strict host-key checking.** `known_hosts` is built from the host's own host
  keys (`StrictHostKeyChecking=yes`), not trust-on-first-use.
- **Scoped edits to `authorized_keys`.** The app only ever adds or replaces its
  own `yundera-terminal` line. The support key and the admin console's key are
  left untouched.
- **No host filesystem mount.** The chroot version's read-write bind of `/` is
  gone.
- **The privilege is confined to the one service that needs it.** The
  internet-facing gate has no `privileged` flag, no `cap_add` and no host
  namespaces.
- **Disclosed before install.** `x-casaos.description` and
  `x-casaos.tips.before_install` state that sessions are `admin` with `sudo`,
  that everything on the server is reachable, and that the app adds its own key
  to `authorized_keys`.
- **Pinned images**, `ghcr.io/yundera/appshield` and `tsl0922/ttyd:1.7.7`. The
  ttyd image is upstream and unmodified: `nsenter` ships in it, and `ssh` is the
  host's own binary.
- **Resource limits**: `cpu_shares` on both services, and `mem_limit: 128m` on
  the shell container. That limit covers only ttyd and the ssh client; the
  session itself belongs to sshd.
- **Terminal-side features that widen the attack surface are off**: `enableSixel`
  and `enableTrzsz` are disabled; only Zmodem transfer is left on.

## Uninstall

Uninstalling removes `/DATA/AppData/terminal/`, which deletes the private key.
The app has no uninstall hook, so its `yundera-terminal` line stays in `admin`'s
`authorized_keys`. That line is inert: it matches a key that no longer exists,
and it only accepts connections from the server itself. To remove it by hand:

```sh
sudo sed -i '/ yundera-terminal$/d' /home/admin/.ssh/authorized_keys
```

A reinstall generates a new key and replaces the line.

## Alternatives considered and rejected

- **Keep `chroot /host bash`.** Rejected: see the table above. It is a shell with
  the host's files but the container's everything else.
- **`nsenter` straight into a shell (`nsenter -a -- bash` or `su - admin`).** No
  key needed, but the process keeps the container's pty. In the host's mount
  namespace that pty's `/dev/pts/N` name points at a different device, so
  `tty`, `sudo`, `login` and friends see no terminal or the wrong one. There is
  also no PAM session, and the shell stays inside the container's cgroup.
- **Add an `openssh-client` to a custom ttyd image.** Rejected: an image to
  build and maintain for no gain. `nsenter` puts the host's own client in reach.
- **Provision the key from a `pre-install-cmd`.** Rejected: it runs once. The
  in-container setup reconverges on every start, which also repairs a key or
  `known_hosts` that was edited or rotated since.
- **Front it with an app-local password instead of the PCS SSO.** Rejected:
  ttyd's own basic-auth is a single shared credential with no session
  management, and AppShield gives the same identity the rest of the PCS uses.
- **Ship no terminal app at all and tell users to SSH.** Rejected: SSH into a
  Yundera PCS needs key material and a reachable port, which is exactly what a
  user locked out of their own server does not have. A browser shell behind the
  PCS login is the recovery path.

## Data protection

The app's only data is its SSH key and `known_hosts` under
`/DATA/AppData/terminal/ssh/`. Both are regenerated if missing, so
uninstall and reinstall lose nothing.

Beyond that, there is no technical boundary between this app and the rest of the
PCS: the protection is the SSO gate in front of it and the owner's decision to
install it. Practically:

- Treat access to this app as equivalent to root SSH access to the server.
  Anyone who can log into your Yundera account can read and change every file
  on it.
- Install it only on a PCS you administer yourself.
- If what you need is to browse, upload or edit files, install **FileBrowser**
  instead: same job, confined to the directories you point it at.
