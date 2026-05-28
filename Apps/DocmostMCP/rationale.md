# DocmostMCP — Rationale

## `user: "0:0"` on the `docmostmcp` service

The bundled image (`ghcr.io/yundera/docmost-mcp`) starts a small FastAPI
config-UI process and `mcp-proxy` as siblings, both reading and writing
`/data/config.json` and `/data/token.json` on the bind-mounted
`/DATA/AppData/docmostmcp/` directory. The cached JWT is rewritten on
every Docmost re-auth and the config file may be regenerated from env
vars on first start, so the container needs write access to that
directory without requiring the user to fix ownership before first
launch. Running as `0:0` avoids that prerequisite. All data stays under
`/DATA/AppData/docmostmcp/`.

## `worph/beaconify` sidecar pinned by digest

The Beacon sidecar (`ghcr.io/worph/beaconify`) currently only publishes
moving tags (`:latest` and `:main`). To satisfy the "no `:latest`"
guideline the sidecar is referenced via an immutable
`@sha256:…` digest. To upgrade: `docker pull ghcr.io/worph/beaconify:latest`,
read the new digest with
`docker inspect --format '{{index .RepoDigests 0}}' ghcr.io/worph/beaconify:latest`,
and bump the digest in `docker-compose.yml`.

The sidecar exists so that — if Beacon is installed on the same server —
Docmost MCP auto-registers there under the `docmost-mcp__*` tool
namespace with zero user configuration. It's a small process (~5 MB
RSS) and harmless when Beacon isn't installed.
