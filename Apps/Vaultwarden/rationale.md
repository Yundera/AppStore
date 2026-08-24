# Vaultwarden — Rationale

## What deviation / exception is being requested

The app ships with **`SIGNUPS_ALLOWED: "true"`** while being published on three public
hostnames (`vaultwarden-${APP_DOMAIN}`, plus the `nip.io` and `sslip.io` routes) with no
AppShield / SSO sidecar in front of it. Until the owner turns signups off, any visitor
who finds the address can create an account.

Per CONTRIBUTING this is the "relies on the app's own first-launch onboarding instead of
an enabled default" case, so it is documented here rather than left implicit.

## Why it is necessary

- **It is the only bootstrap path.** Vaultwarden has no seeded first user and no
  "create the owner account" flow outside of signup. With `SIGNUPS_ALLOWED: "false"` from
  the start, a freshly installed instance has zero accounts and no way to make one from
  the normal UI — the owner would have to go to `/admin`, authenticate with the admin
  token, and invite themselves by email, which requires working outbound SMTP.
- **SMTP is not guaranteed to work.** The compose points `SMTP_HOST` at the platform
  `smtp` relay, but invitation mail depends on that relay being reachable and on the
  destination accepting it. Making first-run account creation depend on an email round
  trip would turn a zero-config install into a support case whenever mail is unavailable.
- **It is the upstream default.** `vaultwarden/server` ships `SIGNUPS_ALLOWED=true`;
  this app does not loosen anything relative to upstream.

## Security mitigations in place

- **Open signup does not expose any existing vault.** Every vault is encrypted client-side
  under its own master password, which the server never holds. A new account created by a
  stranger is an empty vault; it grants no read access to the owner's data, and the admin
  token itself cannot decrypt a user vault either — stated in `tips.before_install`.
- **The owner is told to close it, in the install dialog, before they install.**
  `tips.before_install` step 3 is "Secure your instance: Disable new signups in admin
  panel once set up", alongside a direct link to the admin panel and the admin token.
- **The admin panel is protected** by `ADMIN_TOKEN`, set to the per-PCS
  `$APP_DEFAULT_PASSWORD` rather than a value baked into the store.
- **No inbound port publishing.** The service uses `expose:` only and is reached through
  the shared `pcs` Caddy network with TLS terminated at the Yundera gateway.
- **`DOMAIN` is pinned** to `https://vaultwarden-$APP_DOMAIN`, so Vaultwarden issues its
  own links and WebAuthn origins against the gateway hostname rather than an attacker-
  supplied `Host` header.
- **Resource limits are enforced**, and all state is confined to
  `/DATA/AppData/vaultwarden/data/`.

## Alternatives considered and rejected

1. **`SIGNUPS_ALLOWED: "false"` out of the box** — rejected: it leaves a new install with
   no accounts and no UI path to create one. Recovery requires the admin panel plus
   working SMTP, which is exactly the fragile dependency described above. It would also
   change the documented first-run flow that the audit's functional section currently
   passes end to end.
2. **`SIGNUP_DOMAINS_WHITELIST`** — rejected: it restricts *which* email domains may
   register, not *whether* an anonymous visitor may. On a personal server the owner's
   address is often at a large public provider, so whitelisting that domain would leave
   registration effectively open anyway.
3. **Putting AppShield / OIDC in front of Vaultwarden** — rejected for this app: the
   Bitwarden mobile and desktop clients and the browser extension talk to the Vaultwarden
   API directly and cannot complete an interactive OIDC login, so an SSO sidecar would
   break every client except the web vault. This is the same reason the app carries no
   AppShield sidecar today.
4. **Auto-disabling signups after the first account** — rejected: Vaultwarden has no such
   setting, and a hook that rewrote the container's environment after first boot would be
   invisible to the user and would fight `restart: unless-stopped`.

## Data protection

- All state lives in `${DATA_ROOT:-/DATA}/AppData/vaultwarden/data/` and survives uninstall
  / reinstall and image upgrades.
- Vault contents are end-to-end encrypted under each user's master password. The server
  stores ciphertext only; neither the admin token nor filesystem access to the PCS yields
  plaintext.
- `tips.before_install` opens by warning that a lost master password makes the vault
  permanently unrecoverable, so the user is told before install that recovery is not
  something the server operator can perform.

## Note for reviewers

The audit tiered `open-self-registration` **Minor** and explicitly invited a human to
re-tier it. If the store decides the exposure window is not acceptable, the change is a
one-liner (`SIGNUPS_ALLOWED: "false"`) plus a rewrite of `tips.before_install` steps 1–3
to describe the admin-panel invite flow — and it should be validated against the
functional phases, which currently pass 9 of 9 on the existing flow.
