# Rationale

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
