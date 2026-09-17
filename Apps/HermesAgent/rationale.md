# Hermes Agent — Rationale

## What deviations are being requested

Five, all forced by how the upstream image is built, plus one security choice.

### 1. No `user:` field

`CONTRIBUTING.md` requires every service to pin `user:`. This image refuses to start
with one. `docker/main-wrapper.sh` guards it explicitly:

```
[hermes] ERROR: container started with --user 1000 (an arbitrary, non-hermes UID) — not supported.
To make container-written files match your HOST user, don't use --user.
Start as root (the default) and pass your host UID/GID instead.
```

The reason is its supervision tree: the container boots as root, s6 remaps its internal
`hermes` user to `PUID`/`PGID`, chowns the data volume, and only then drops privileges
with `s6-setuidgid`. Pinning an arbitrary UID skips the bootstrap, leaves the baked
image directories unwritable, and the process dies on `cd`.

`PUID`/`PGID` are set instead, which is the supported path and which the image documents
for exactly this case. **The outcome is the one the rule asks for** — verified on
holyhorse: every file under `/DATA/AppData/hermes` is owned by the PCS user, not root.

### 2. No `init: true`

The image's entrypoint is a dispatcher that hands off to s6-overlay's `/init`, and it
only does so when it is PID 1:

```
[hermes] WARNING: container entrypoint is not PID 1; skipping s6-overlay /init …
Supervised services are unavailable in this runtime
```

`init: true` inserts Docker's own init as PID 1, which takes that branch — and the web
dashboard is one of the supervised services, so the app would come up with no web UI at
all. Zombie reaping is s6's job here, which is what an init process would have been for.

### 3. `post-install-cmd` registers an OIDC client and restarts the app

The dashboard's auth gate is mandatory on a non-loopback bind and **fails closed** with
no provider configured. Unlike the other agent app in this store, its native gate cannot
be delegated to an AppShield sidecar: `HERMES_DASHBOARD_INSECURE` was neutered in a June
2026 hardening (the run script accepts it, warns, and ignores it), so fronting the app
with SSO would leave the user with two consecutive sign-ins for one app.

Instead the app becomes an OIDC client of the server's own identity provider. The hook
asks `auth-registrar` for a client, writes the answer into the agent's config, and
restarts it so the dashboard registers the provider:

```
POST http://auth-registrar:9092/register {"callback_path":"/auth/callback"}
→ {"client_id":"hermes","client_secret":"…","issuer_url":"https://auth-<user>.<server>",
   "redirect_uris":["https://hermes-<user>.<server>/auth/callback", …nip.io, …sslip.io]}
```

Three properties make this safe to run from a hook:

- **The client id is attested, not claimed.** The registrar resolves the caller's PTR
  record and uses the first label as the client id, so the call has to come from a
  container named `hermes` — which is why the hook is `docker exec hermes …` rather than
  a standalone init step, whose container would attest under its own name.
- **It is idempotent.** Re-registering the same client returns the *identical* secret
  (verified), so the hook is safe on reinstall and on update.
- **It cannot brick the app.** The chain ends in `|| true`, and the basic-auth fallback
  below is configured regardless, so a registrar that is slow or absent costs the user
  the single-sign-on convenience and nothing else.

The restart is what makes the provider live: `hermes config set` writes the file, but the
dashboard resolves its providers once, at start.

### 4. A second sign-in method with a shipped password

`HERMES_DASHBOARD_BASIC_AUTH_USERNAME`/`_PASSWORD` are set to `admin` /
`$APP_DEFAULT_PASSWORD`. This is deliberate belt-and-braces, and it is a real if narrow
widening of the attack surface: whoever knows that value reaches the dashboard without
passing the server's SSO.

It is accepted because the alternative is worse. The gate fails closed; if the OIDC
registration cannot complete — registrar down at install time, a PCS whose identity
provider is not yet up — a dashboard with no provider serves nothing to anybody, and the
app is unreachable with no way in short of editing files on the host. `$APP_DEFAULT_PASSWORD`
is a per-install random value, never a shipped literal.

No `HERMES_DASHBOARD_BASIC_AUTH_SECRET` is set. The image then generates a random signing
key per process, which means fallback sessions are dropped on every restart. That is the
preferred behaviour for a fallback: it keeps a long-lived session from quietly becoming
the way the app is used.

### 5. Resource and runtime notes

- **`shm_size: 1gb`** — the agent's browser tool is Playwright, which crashes on the
  64 MB Docker gives a container by default. Upstream documents this figure.
- **`memory: 3G`** — above what the app needs at rest (~390 MB observed on holyhorse) and
  chosen for what it does under load: upstream asks for 2–4 GB, and at least 2 GB once
  browser automation is in play. An agent OOM-killed mid-task loses the task.
- **`stop_grace_period: 30s`** — the gateway does not finish its shutdown path inside the
  default 10 s, and the next start then reports the previous life as having exited
  uncleanly (`no exit path ran — SIGKILL / OOM / VM death`).
- **Port 8642 is exposed to nothing.** It is the agent's OpenAI-compatible API — a second,
  separately-credentialled way into the same agent. It stays on the app's own network with
  no Caddy label; nothing else on the box needs it, and the user can still reach it from
  inside the app.

## Security posture

- **One mount, and it is the app's own.** `/DATA/AppData/hermes` is all the container
  sees. The agent runs shell commands and reads and writes files by design — that is the
  product — but `/DATA/Documents`, `/DATA/Media` and `/DATA/Downloads` are not mounted,
  and there is no docker socket and no host path.
- **The web UI is gated before anything else.** The dashboard exposes a config editor, an
  API-key manager that reads and writes `.env`, a file browser and a cron scheduler; it is
  never reachable unauthenticated. Only `/api/health`, `/api/status` and a small
  allowlist of pre-login endpoints bypass the gate, and `/api/cron/fire`, which is on that
  list, carries its own fire token (`401 invalid fire token` without it).
- **Secret redaction is on** by default in the runtime: tool output, logs and chat
  responses are scrubbed before delivery.
- **The image fetches dependencies at runtime.** First boot lazily pip-installs optional
  provider and speech extras into `/opt/data/lazy-packages` and downloads a `tirith` binary
  into `/opt/data/bin` (SHA-256 verified; the image notes cosign is absent so signature
  verification is not performed). This is upstream behaviour, not something the compose
  turns on, and it is the main reason the data directory reaches ~500 MB before the user
  has done anything. It is called out in `tips.before_install`.

## Known rough edges (upstream, not packaging)

- **A prompt sent before a model is configured spins indefinitely** — no error in the UI
  and none in the logs. `tips.before_install` tells the user to set a provider first.
- **The gateway can sit in `starting` for many minutes** after first boot before it reports
  `running`; the sidebar reads as half-broken in the meantime. It does get there.
- **The in-browser TUI reports `Available Skills (0)`** on its splash while the dashboard's
  own Skills page lists all 53 as enabled. The dashboard figure is the accurate one.

## Testing

Built and validated on holyhorse (test PCS, prod configuration), 2026-09-17:

- Installed through a store source, not by hand: container healthy, `post-install-cmd`
  registered the OIDC client and restarted the app unattended.
- Signed in at `https://hermes-<user>.<server>/` with the server account — `login_success`
  1.1 s after `login_start`, no visible second prompt, because the identity provider
  already had the session.
- The in-browser terminal streams over its websocket through the reverse proxy on the
  public origin, with the PTY gated by a minted ticket.
- File ownership, restart persistence, the health endpoint and the idempotence of
  re-registration all checked on the box.
- **Not verified: a model answering.** No provider credential was configured during
  testing, so every path from the first token onwards is untested.
