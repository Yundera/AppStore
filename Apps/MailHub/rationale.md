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

- Both are gated by the mailbox login, a Maison-generated secret (`MAILHUB_PASSWORD`,
  `password:24`) shown under Credentials and changeable from the Security tab.
- The DAV route serves `/dav.php` only (`seed/baikal/nginx.conf`): Baïkal's admin console and
  welcome page return 404. The admin account's password is a separate random secret that is never
  shown, and nothing needs it — the `baikal-init` step configures the server.
- IMAPS only (TLS on 993, with a certificate Maison provides for the best host of the `mailhub` route — `certificates`, needs a Maison with that feature); plain IMAP (143) and LMTP
  are not published.

## Alternatives considered

- Calendar & contacts only inside the webmail (no DAV route): loses phone sync, a core use case.
- A separate Baïkal app: tried on 2026-11-04 and dropped — a second app with its own admin-style
  console and login was too much to set up for one person's calendar. `Apps/Baikal` remains as a
  standalone store app for people who want a DAV server on its own.

## Data protection

Mail (`mail/`), the calendar & contacts DB (`baikal/data/`) and Roundcube's DB are all in the app
folder, so they are part of Maison's backup of the app. `mail/live/` is a copy of each provider
mailbox: the provider stays the source of truth. The copy is pulled with mbsync in pull-only mode
(nothing in that direction writes to the provider); what the user does in those folders reaches
the provider only as the same IMAP command, replayed from Dovecot's record of it. Nothing is ever
inferred from a difference between the two sides, so a lost or emptied local copy never deletes
anything at the provider: it is simply copied again. Removing an account deletes only the local copy.

The providers' app passwords are in plain text in `mirror/accounts/` (mailhub-mirror reads them
from there), in a `0700` folder owned by the webmail's user, and encrypted with the app's DES key in
Roundcube's DB. mailhub-mirror runs as root to read them; mbsync itself runs as the mailbox's user. They are app passwords: each can be revoked at the provider without touching the
account's main password.
