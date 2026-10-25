# Factorio — Rationale

## What exception is requested

The `factorio` service has no memory limit (`deploy.resources.limits.memory`), which
[GUIDELINES › Resources](../../GUIDELINES.md#resources) recommends on every service.

## Why it is necessary

A Factorio server keeps the whole map in memory, and the map only grows: every planet
visited, every factory built and every space platform adds to it. No fixed limit fits
both ends:

- a new map runs in about 300 MB;
- a late-game Space Age save (32.6M ticks, about 150 hours of play, 55 MB zipped) takes about 2 GB
  once loaded, measured on holyhorse in 2026-10;
- larger megabases go well beyond that.

When the server hits the limit, the kernel kills it. Everything since the last autosave
(10 minutes by default) is lost, and the server then crash-loops because loading the
map needs the same memory. A limit low enough to protect the box would break the
largest maps, and one high enough for them protects nothing.

## Mitigations

- `cpu_shares: 50`, the default weight, so the server does not starve other apps under
  CPU load.
- `auto_pause` is on in the seeded `server-settings.json`: with nobody connected, the
  simulation stops, so an idle server costs memory but no CPU.
- The description and tips state the hardware needs (one fast core, several GB of RAM
  for large maps) before install.
- The owner can still set a limit from the app's settings (Config → Compose).

## Alternatives considered

- **A high fixed limit (e.g. 4 GB):** larger than most PCS have free next to the
  platform, so it would not protect the box, and still too low for the largest maps.
- **A limit read from `.env`:** the owner can already set one in the app's settings; a
  variable adds a second way to do the same thing.

## Data protection

- Saves, mods and settings are in `/DATA/AppData/factorio/data`, mounted at `/factorio`.
- The server saves the map on a clean stop (`stop_grace_period: 60s` gives a large map
  time to write it) and autosaves every 10 minutes in 5 rotating slots.
- The entrypoint deletes half-written `*.tmp.zip` saves left by a crash, so the newest
  complete save is the one loaded.
