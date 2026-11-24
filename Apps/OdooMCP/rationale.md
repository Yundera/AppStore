# Rationale: Odoo MCP

## `auth-default` — no login gate of its own

Odoo MCP is a **service app**. It declares no `routes` and publishes no port, so
nothing about it is reachable from outside the box. Both of its containers sit on
the shared `pcs` network only, and only two kinds of neighbour can talk to them:

- **Beacon**, through the bundled `beaconify` sidecar, which Beacon finds by
  discovery on UDP 9099.
- A client already running on that same Docker network, which is to say a
  container the owner installed themselves.

The login gate therefore lives one hop out, on Beacon, whose public endpoint is
protected by the box's single sign-on and an OAuth 2.1 broker. Putting an
AppShield sidecar in front of this app as well would publish an address that
nobody needs, widen the attack surface rather than narrow it, and still leave
Beacon as the door every client actually uses.

This is the same shape as any database or backend service in the store: it is not
exposed, so it is not gated. The difference is only that its sibling is an
aggregator rather than a web UI.

## Why `ODOO_YOLO` is set to `true`

The upstream connector offers two security models.

1. Odoo's own `mcp_server` module, which enforces per-model read, write, create
   and delete rules inside Odoo. It is the right answer for an Odoo the owner
   fully administers, and anyone who installs it can drop the `ODOO_YOLO` line.
2. `ODOO_YOLO`, which skips the connector's own checks and relies on Odoo's
   native permissions instead.

This listing ships option 2 because the module is a separate install the owner
may not be able to perform, for instance on Odoo Online or on an Odoo
administered by someone else, and because the app would otherwise fail to do
anything at all on a standard Odoo.

The access limit is real either way: every call is made as the Odoo user whose
API key the owner supplied, and Odoo applies that user's own access rights and
record rules. The listing's `inputs` label and its `tips` both tell the owner to
create a dedicated user with the narrowest rights that fit the job, and warn that
the connector can reach everything that user can. `ODOO_YOLO` widens what the
connector permits, never what Odoo permits.

## `works-immediately`, `zero-config`, `clean-boot`, `app-url`, `auth-gate`

Not applicable: these are functional checks on a web UI, and a service app has
none. The values the app cannot start without are declared under `inputs`, so
Maison asks for them in the install dialog and marks the tile **Setup needed**
while a required one is empty.
