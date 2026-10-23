# Rationale

## First account is created on first visit (`auth-default`)

The web UI (Open WebUI) has its own login and it is on (`WEBUI_AUTH` is not disabled): nothing
past the sign-in page is reachable without an account. **The first account created becomes the
administrator.** Open WebUI cannot seed that account from the environment, so no generated
credential can be declared, and the app's own login is the gate rather than AppShield — a
second login in front of a mandatory one would add nothing but friction.

**The window** is the time between install and the owner's first visit, and the tips tell the
owner to sign up first thing. After that, a new sign-up gets the `pending` role (Open WebUI's
default) and can do nothing until the administrator approves it, so the public sign-up page
cannot be used to get in. The inference API (`ollama-api`) is on the app's internal network
only and publishes no port.

## No memory limit on `ollama-api`

The store guidelines require a memory limit on every service. The `ollama-api`
(inference) container intentionally has **no `deploy.resources.limits.memory`**.

**Why:**
- The RAM footprint is determined entirely by the model the user pulls at
  runtime (a 1B model needs ~1.5 GB, a 7B/8B model needs ~5–6 GB), so no single
  static limit fits all cases.
- A limit smaller than the loaded model forces the model into swap, which on a
  CPU-only PCS makes every generated token do disk I/O — inference becomes
  effectively unusable (observed: a 5.2 GB model under a 4 GB cap pinned the
  container at 99.99% and drove the host into 2+ GB of swap).
- Ollama only loads a model on demand and unloads it after `OLLAMA_KEEP_ALIVE`,
  so idle memory use stays low; it does not hold the cap's worth of RAM
  continuously.

The web UI container (`ollama`) keeps its 1 GB limit — only the inference
engine is uncapped.

**User guidance:** choose a model that fits the server's RAM. On a typical
~8 GB CPU-only PCS, stick to 1B–3B models for responsive performance.
