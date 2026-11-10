# MailHub — Rationale

## What exception is requested

1. The calendar & contacts route (`mailhubdav`, the built-in Baïkal) has no AppShield in front.
2. A host port is published: IMAPS `993`.

## Why it is necessary

1. That route exists for phone and desktop CalDAV / CardDAV clients (DAVx⁵, iOS / macOS,
   Thunderbird). They authenticate with HTTP Basic auth on every request and cannot follow an
   OIDC login, so the SSO gate would lock them all out. The webmail itself stays behind AppShield.
2. IMAP is not HTTP, so the proxy cannot carry it; phone and desktop mail apps need it to read
   the unified mailbox (`requires: [public-ip]`, `needs-public-ip`).

## Mitigations

- Both are gated by each mailbox's device login. The owner's (`admin`, the first account that
  opened MailHub) is a Maison-generated secret (`MAILHUB_PASSWORD`, `password:24`) shown under
  Credentials and changeable from the Security tab. Every other mailbox gets its own generated
  password (24 random characters), shown and replaceable in the webmail under *Settings → Phones &
  computers*; Dovecot and Baïkal only hold its hashes (`{SSHA512}`, Baïkal's digest).
- Dovecot's master login (`MAILHUB_MASTER_PASSWORD`, `alnum:32`), through which the webmail, the
  mirror and the MCP server open a user's mailbox, is accepted from private addresses only
  (`allow_nets` in `seed/dovecot/auth.conf`), never as a user's own password, and never leaves the
  app's containers.
- The DAV route serves `/dav.php` only (`seed/baikal/nginx.conf`): Baïkal's admin console and
  welcome page return 404. The admin account's hash is a separate random secret (`MAILHUB_DAV_ADMIN_HASH`)
  that no password matches, and nothing needs it — `baikal.yaml` (`files`) and the
  `baikal-init` step configure the server.
- IMAPS only (TLS on 993, with a certificate Maison provides for the best host of the `mailhub` route — `certificates`, needs a Maison with that feature); plain IMAP (143) and LMTP
  are not published.

## The webmail's login

The webmail has no login of its own: AppShield's sign-in is it. AppShield signs the identity on
every request (`X-AppShield-Assertion`, HS256, `MAILHUB_ASSERTION_SECRET`, audience `mailhub`) and
the webmail's `mailhub_sso` plugin logs that identity into its own mailbox. The plain `Remote-User`
header is never trusted, since the other containers on the app's network could send one; a request
without a valid assertion gets a page pointing to the sign-in, never Roundcube's login form. Each
identity (its `sub`) gets a mailbox the first time it opens MailHub: the first one ever the existing
`admin` mailbox, the next ones a name of their own. Who may sign in at all is AppShield's decision
(its required groups), not MailHub's.

Not covered yet, on purpose:
- The MCP server serves the owner's mailbox only: Beacon reaches it without a caller identity.
- Removing a user: AppShield sends no signal when an account goes. Delete `users/<name>.json`
  (the mirror stops; the mail stays in `mail/<name>/` until removed by hand).

## Alternatives considered

- Calendar & contacts only inside the webmail (no DAV route): loses phone sync, a core use case.
- A separate Baïkal app: tried on 2026-11-04 and dropped — a second app with its own admin-style
  console and login was too much to set up for one person's calendar. `Apps/Baikal` remains as a
  standalone store app for people who want a DAV server on its own.
- Removing AppShield and keeping Roundcube's own login: one login either way, but it would put
  Roundcube's login page and session handling in front of the internet, and lose the server's
  2FA and single sign-on.

## Data protection

Mail (`mail/`), the calendar & contacts DB (`baikal/data/`), Roundcube's DB and the users
(`users/`) are all in the app folder, so they are part of Maison's backup of the app.
`mail/<user>/live/` is a copy of each provider mailbox: the provider stays the source of truth. The
copy is pulled with mbsync in pull-only mode (nothing in that direction writes to the provider);
what the user does in those folders reaches the provider only as the same IMAP command, replayed
from Dovecot's record of it. Nothing is ever inferred from a difference between the two sides, so a
lost or emptied local copy never deletes anything at the provider: it is simply copied again.
Removing an account deletes only the local copy.

The providers' app passwords are in plain text in `mirror/accounts/<user>/` (mailhub-mirror reads
them from there), in a `0700` folder owned by the webmail's user, and encrypted with the app's DES key in
Roundcube's DB. mailhub-mirror runs as root to read them; mbsync itself runs as the mailbox's user. They are app passwords: each can be revoked at the provider without touching the
account's main password. Each user's accounts are in their own folder and mirrored into their own
mailbox only.

New-mail notifications (Settings → Notifications, off until a user turns them on for a device) go
out from mailhub-mirror to the browser vendor's push service (Google FCM, Mozilla, Apple): an outbound
HTTPS request, no port published and nothing exempted from AppShield. The payload (sender and subject,
or only a count if the user chooses so) is encrypted for that one device (RFC 8291), so the push service
relays it without being able to read it. The subscriptions (`mirror/accounts/<user>/.push.json`) sit in
the same `0700` folder as the accounts; the server key that signs the requests
(`mirror/state/.push/vapid.json`, `0600`) never leaves the app folder.
