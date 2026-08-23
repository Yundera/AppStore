# DocusaurusMCP — Rationale

## Bind mounts into another app's directory (`/DATA/AppData/docusaurus/`)

DocusaurusMCP is a companion to the **Docusaurus** app: its whole purpose is
to let an AI assistant read, write and search the documentation of the
Docusaurus instance running on the same server, and to trigger a rebuild of
that site. That means it has to operate on the *same files* the Docusaurus
app serves, so it bind-mounts that app's directories rather than a private
one:

| Mount | Why |
| --- | --- |
| `/DATA/AppData/docusaurus/src` → `/app/docusaurus-src` | The Docusaurus project source. `list_docs`, `read_doc`, `write_doc`, `search_docs`, `list_files`, `read_file` and `write_file` all operate here. |
| `/DATA/AppData/docusaurus/build` → `/app/docusaurus-build` | The build output the Docusaurus nginx backend serves. `rebuild` writes here so the live site picks the change up. |

Both paths stay inside `/DATA/AppData/`; no broad slice of `/DATA`
(`/DATA/Documents`, `/DATA/Media`, `/DATA/Downloads`, or `/DATA` itself) is
exposed. The dependency is disclosed to the user before install:
`tips.before_install` states that the Docusaurus app must be installed first
and that "this MCP reads and writes files in its data directory".

Both mounts are read-write because the app's advertised tools (`write_doc`,
`write_file`, `rebuild`) are writes by definition — a read-only mount would
reduce the app to its four read tools.

Access to those write tools is gated: the `/mcp` endpoint is behind
AppShield's OAuth 2.1 broker (`OAUTH_RESOURCE`), so a caller needs a Bearer
token issued after a Yundera SSO login. Everything else on the public host is
behind the SSO gate. The unauthenticated path is the in-network address
`http://docusaurusmcp-backend:9750/mcp`, which is not published outside the
`pcs` Docker network.

## `user: "0:0"` on the `docusaurusmcp-backend` service

The MCP server writes Markdown/MDX and project files into the Docusaurus
source tree and runs the Docusaurus build, which creates and replaces files
under `build/`. Those directories are owned by whatever uid the Docusaurus
app itself runs as, so a fixed non-root uid here would break writes for any
user whose Docusaurus install differs. Running as `0:0` avoids making the
user fix ownership by hand across two apps before the first write succeeds.
The container has no access outside the two bind mounts above.

## `worph/beaconify` sidecar pinned by digest

The Beacon sidecar (`ghcr.io/worph/beaconify`) currently only publishes
moving tags (`:latest` and `:main`). To satisfy the "no `:latest`" guideline
the sidecar is referenced via an immutable `@sha256:…` digest. To upgrade:
`docker pull ghcr.io/worph/beaconify:latest`, read the new digest with
`docker inspect --format '{{index .RepoDigests 0}}' ghcr.io/worph/beaconify:latest`,
and bump the digest in `docker-compose.yml`.

The sidecar exists so that — if Beacon is installed on the same server —
Docusaurus MCP auto-registers there under the `docusaurus-mcp__*` tool
namespace with zero user configuration. It's a small process (~5 MB RSS) and
harmless when Beacon isn't installed.
