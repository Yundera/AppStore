# Cypht — Rationale

One of three mail apps compared on a test box in November 2026 (MailHub, Cypht, SnappyMail).
Cypht works on each provider's mailbox live over IMAP, so nothing is fetched or copied; MailHub's
own modules add what Cypht lacks (invitations, a CalDAV calendar page).

## What exception is requested

1. The calendar & contacts route (`cyphtdav`, the built-in Baïkal) has no AppShield in front.
2. The images come from a personal registry (`ghcr.io/worph`), not the upstream projects:
   - `mailhub-cypht`: the official `cypht/cypht` image plus our modules (github.com/worph/mailhub, `cypht/`);
   - `cypht-gateway`: an unchanged build of github.com/ashanzzz/cypht-gateway at its tag, which
     publishes no image.
3. The app login cannot be changed from Maison (no `change` on the credential).

## Why it is necessary

1. Phone and desktop CalDAV / CardDAV clients (DAVx⁵, iOS / macOS, Thunderbird) send HTTP Basic
   auth on every request and cannot follow an OIDC login. The webmail itself stays behind AppShield.
2. The modules are not upstream (yet); the gateway has no image to pin.
3. Cypht encrypts each user's settings, including the mail accounts' passwords, with the login
   password. Changing it outside Cypht would leave those settings unreadable.

## Mitigations

- The DAV route is gated by the app login, a Maison-generated secret (`CYPHT_PASSWORD`,
  `password:24`), and serves `/dav.php` only (`seed/baikal/nginx.conf`): Baïkal's console returns 404.
- The image build is public and reproducible (Dockerfile and CI in the mailhub repo): upstream
  Cypht plus our modules, sabre/vobject and FullCalendar fetched by version and checksum. It also
  removes the Xdebug extension the upstream image loads, and turns on TLS certificate checks for
  every mail server with a public host name (upstream Cypht checks none).
- The gateway and its MCP server are not routed: only the app's own containers reach them. The
  token the `bootstrap` step creates is read-only (no send, move or delete scopes), and the MCP
  server hides its write tools unless `CYPHT_MCP_ALLOW_WRITE=true`. Beacon gets the token through
  the beaconify sidecar, never in plain sight.
- cypht-gateway is young (a few weeks old in November 2026): it is pinned to a tag and optional in
  practice — without Beacon, nothing calls it.

## How it is set up

- The app login is the local archive's IMAP login (`AUTH_TYPE: IMAP` against the app's Dovecot),
  so Cypht adds that mailbox as an account on its own; no setup script touches Cypht's database.
- `baikal-init` (setup step) writes Baïkal's config and its one user, as in MailHub.
- `bootstrap` (started step) logs into the gateway once and creates the MCP token, kept in `.env`.
  The gateway refuses accounts on private addresses, so it cannot add the local archive itself.

## Data protection

The local archive (`mail/`), calendar & contacts (`baikal/data/`), Cypht's settings (`cypht/db/`),
the gateway's DB (`gateway/`) and `.env` are in the app folder, so all are in Maison's backup of
the app. Mail on the providers stays there: Cypht keeps no copy.
