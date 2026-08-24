# Stirling PDF — Rationale

## What deviation / exception is being requested

Two, and they are linked:

1. The container runs as **`user: "0:0"`** (with `PUID: 0` / `PGID: 0`), instead of the
   default `$PUID:$PGID`.
2. It has **mixed access**: its own `/DATA/AppData/$AppID/` subdirectories *and* a
   read-write bind of the broad user slice **`/DATA/Downloads`** at `/downloads`.

Per CONTRIBUTING, either one alone requires this file; together they are the
"root container with mixed access" case.

## Why it is necessary

- **The upstream image is built to start as root.** `stirlingtools/stirling-pdf`
  runs an entrypoint that installs/refreshes language packs, unpacks OCR `tessdata`,
  writes `/configs/settings.yml` on first boot and provisions the LibreOffice and
  Ghostscript profile directories before it drops into the Java process. Those paths
  live inside the image, not in a mount, so an arbitrary UID cannot write them and the
  container exits during startup.
- **The PDF toolchain shells out.** OCRmyPDF/Tesseract, Ghostscript, qpdf, LibreOffice
  and unoconv are invoked as child processes and each wants its own scratch and profile
  dirs under `/tmp` and `$HOME`. Running as a UID with no passwd entry makes several of
  those tools fail at spawn time rather than at use time, which surfaces as random
  "conversion failed" errors instead of a clean startup failure.
- **`/downloads` must be writable** because it is the point of the mount: the user drops
  PDFs in their own `Downloads` folder, and the app's split / convert / compress /
  "auto pipeline" outputs are written back there so the results show up in the file
  manager without a second download step. A read-only mount would make the app
  read-only for the one folder users care about.

## Security mitigations in place

- **Authentication is on by default and not optional.** `DOCKER_ENABLE_SECURITY=true`
  and `SECURITY_ENABLELOGIN=true`; the initial account is `admin` with the per-PCS
  `$APP_DEFAULT_PASSWORD`, surfaced in `tips.before_install`. `index` / `webui-path`
  point at `/login`, so the first thing a visitor meets is the login gate.
- **No inbound port publishing.** The service uses `expose:` only and is reached through
  the shared `pcs` Caddy network over TLS; nothing is bound on the host.
- **Extra attack surface is switched off.** `DISABLE_ADDITIONAL_FEATURES=true` and
  `INSTALL_BOOK_AND_ADVANCED_HTML_OPS=false` keep the Calibre/advanced-HTML converters
  and the extra endpoints out of the running app.
- **Blast radius is one folder.** The only host path outside `/DATA/AppData/$AppID/`
  is `/DATA/Downloads`. `/DATA/Documents`, `/DATA/Media`, `/DATA/Gallery` and `/DATA`
  itself are **not** mounted, so root inside the container cannot reach them.
- **Resource limits are enforced** (`5G` memory limit / `2G` reservation, `1.0` CPU,
  `cpu_shares: 50`) and `JAVA_TOOL_OPTIONS` caps the JVM at 70 % of the container
  memory, so a malicious or malformed PDF cannot starve the rest of the PCS.
- **Scratch space is contained.** `TMPDIR=/tmp` and `-Djava.io.tmpdir=/tmp` point every
  temporary artefact at a dedicated `/DATA/AppData/$AppID/tmp` bind, not at a shared
  host tmp.

## Alternatives considered and rejected

1. **`user: $PUID:$PGID`** — rejected: the entrypoint cannot write the in-image
   `tessdata`, config and LibreOffice profile paths and the container fails to boot.
2. **Root plus a read-only `/downloads`** — rejected: it breaks the feature the mount
   exists for. Users would be able to open their saved PDFs but not save the result
   next to them.
3. **Dropping the `/downloads` mount entirely** — rejected: every file would then have
   to go through browser upload/download, which defeats the point of running a PDF
   toolkit on the machine that already holds the files.
4. **Split into two containers (root worker + `$PUID` file-access sidecar)** — rejected:
   Stirling PDF is a single Spring Boot process that both serves the UI and runs the
   conversions; there is no supported way to separate them, and a sidecar that only
   copies files in and out would double disk usage for large PDFs.

## Data protection

- All app state — `configs`, `logs`, `customFiles`, `pipeline`, `tessdata`, `tmp` — is
  bound under `/DATA/AppData/$AppID/` and declared in `x-compose-app.folders`, so it is
  created and chowned by Maison and survives uninstall / reinstall and upgrades.
- User files stay in the user's own `/DATA/Downloads`; the app never copies them into
  AppData, so removing the app removes nothing the user put there.
- Nothing leaves the PCS: Stirling PDF does no outbound calls for conversion, so
  documents are processed entirely on the user's own server.
- The broad `/DATA/Downloads` mount is disclosed to the user before install, in the
  `tips.before_install` "Folder access" section in all five supported locales.
