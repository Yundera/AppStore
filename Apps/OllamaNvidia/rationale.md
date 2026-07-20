# Rationale

## No memory limit on `ollama-api`

The store guidelines require a memory limit on every service. The `ollama-api`
(inference) container intentionally has **no `deploy.resources.limits.memory`**.

**Why:**
- The RAM/VRAM footprint is determined entirely by the model the user pulls at
  runtime (a 1B model needs ~1.5 GB, a 7B/8B model needs ~5–6 GB), so no single
  static limit fits all cases.
- The model is loaded into GPU VRAM; the host-side memory limit can still force
  swap during load/offload, so an arbitrary cap only hurts.
- Ollama only loads a model on demand and unloads it after `OLLAMA_KEEP_ALIVE`,
  so idle memory use stays low; it does not hold the cap's worth of RAM
  continuously.

The web UI container (`ollama`) keeps its 1 GB limit — only the inference
engine is uncapped.

## GPU edition — host prerequisite

This edition reserves an Nvidia device:

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]
```

Docker can only satisfy that reservation when the host has an Nvidia GPU **and**
the **NVIDIA Container Toolkit** installed and registered as a Docker runtime
(`nvidia-ctk runtime configure --runtime=docker` followed by a Docker restart).
We deliberately do **not** install the toolkit from a `pre-install-cmd`:
configuring the runtime requires restarting the Docker daemon, which would kill
the very install step performing it. The toolkit is therefore expected to be
provisioned on the host image (Radiant / Contabo GPU instances, or
user-supplied hardware via nsl.sh). On a host without it the container fails to
start; CPU-only users should install **Ollama (CPU)** instead.

**User guidance:** pick a model that fits the GPU's VRAM for full acceleration;
models larger than VRAM spill to system RAM/CPU and run much slower.
