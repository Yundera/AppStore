# SnappyMail — Rationale

One of three mail apps compared on a test box in November 2026 (MailHub, Cypht, SnappyMail): the
lightest, used as shipped, with no code of ours.

## What exception is requested

The image comes from a personal registry: `ghcr.io/worph/snappymail:3.0.0`, an unchanged build of
github.com/the-djmaze/snappymail at tag `v3.0.0` with its own `.docker/release/Dockerfile`
(github.com/worph/mailhub, `.github/workflows/upstream.yml`).

## Why it is necessary

SnappyMail 3.0.0 (5 Nov 2026) fixes nine security advisories, two of them server-side request
forgery reachable without logging in. The newest image on Docker Hub (`djmaze/snappymail:v2.38.2.1`)
and on GHCR predates them. Switch back to `djmaze/snappymail:v3.0.0` once it is published.

## Mitigations

- The webmail and its admin panel (same address, `/?admin`) sit behind AppShield.
- The admin password is a Maison secret (`SNAPPYMAIL_ADMIN_PASSWORD`), shown under Credentials,
  applied by the `snappymail-config` step on every up; SnappyMail's own generated password file
  is removed.
- SnappyMail checks no TLS certificate by default. The setup writes the provider domains it
  enables (Gmail, Yahoo, iCloud, Fastmail) with certificate checks on, and switches off the
  catch-all `*` domain, so a login can only reach a server an admin has named.

## How it is set up

`scripts/snappymail-setup.sh` runs in the SnappyMail image before the server starts. On the first
up it writes the default config the way the image's entrypoint does, then the defaults (contacts in
SQLite with CardDAV sync, threads, "remember me", the `view-ics` invitation viewer). On every up it
turns `force_https` off (Caddy terminates TLS, and since 3.0 that setting loops behind a proxy) and
re-applies the admin password. The `view-ics` plugin (MIT, from the same tag) is shipped in `seed/`.

## Data protection

`data/` holds the config, the domains, contacts and each user's settings and extra accounts
(passwords encrypted). It is in Maison's backup of the app. Mail stays at the providers.
