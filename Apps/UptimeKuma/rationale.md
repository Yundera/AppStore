# UptimeKuma — Rationale

## What exception is requested

`auth-default`: the first visitor creates the admin account (first-visit onboarding), rather
than signing in with a generated credential or through AppShield.

## Why it is necessary

Uptime Kuma has its own login, and it is always on: every page but the one-time setup screen
requires it. It is single-user — there is one admin account and no self-registration — and the
setup screen that creates that account exists only until it has been used. The app offers no
way to seed that account from the environment, so a generated credential cannot be declared.

## Mitigations

- The window is the time between install and the owner's first visit. The tips tell the owner
  to create the account on first visit, which closes it.
- Once the account exists, the setup screen is gone and the app's own login gates everything,
  including the status pages' admin side.

## Alternatives considered

- **AppShield in front.** It would gate the setup window, but put a second login in front of
  an app that already has a mandatory one, and status pages meant to be public would need
  path exemptions.
- **A seeded admin.** Not supported upstream.

## Data protection

Monitors, notifications and history are in `/DATA/AppData/uptimekuma/`, readable only through
the admin account once it exists.
