# Jirafeau — Rationale

## What exception is requested

1. **A deliberately public part.** The download page and what it loads are reachable
   without a login. Everything else (upload page, upload API, admin page, installer) is
   behind the AppShield gate.
2. **The backend runs as the image's root entrypoint**, with no `user:`.
3. **`lib/config.local.php` is not bind-mounted.** It is rebuilt from the environment
   every time the container is created.

## Why it is necessary

1. Jirafeau's whole purpose is to hand a link to someone who has no account on this
   server. Behind the gate, every link would send the recipient to a Yundera login they
   cannot pass. The link itself is the credential: an 8-character random reference
   (`link_name_length`), optionally with a download password, a one-time flag and an
   expiry chosen by the uploader.
2. The image's `run.sh` writes `lib/config.local.php` and chowns `/data` to
   `lighttpd:www-data` (100:82) before starting lighttpd and php-fpm, which then drop
   to those users. Running it as `$PUID:$PGID` would break both steps.
3. The image's `docker_config.php` rebuilds the whole config from the environment on
   start: the admin password hash, `web_root`, `var_root`, the upload size. Nothing in it
   is created by the app at runtime. Persisting it would freeze the first admin password,
   because the script keeps an existing hash, and a password change from Maison would
   silently do nothing.

## Mitigations

- **Exactly four public locations**, in `jirafeau-router`:
  `= /f.php` (download page, direct download, preview, delete-with-code),
  `= /lib/functions.js.php` (the page's script: language strings and `web_root`),
  `= /tos.php` (terms of service, linked from the page) and `/media/` (theme CSS and
  icons). These are what `f.php` and `lib/template/header.php` / `footer.php` load in
  4.8.0. Everything else goes to the gate: `/`, `index.php`, `script.php` (all upload
  calls), `admin.php`, `install.php`.
- The three exact locations pass a fixed path, never the client's URI, so
  `/index.php/..%2Ff.php` and similar cannot make lighttpd run another script through
  PATH_INFO.
- `/media/` refuses (400) any request whose raw URI contains `%` or `..` (theme files
  have plain names), and forwards the raw URI unchanged. It must not forward nginx's
  decoded `$uri`: lighttpd decodes again, so a double-encoded `/media/%252e%252e/script.php`
  would reach the upload script without the gate.
- Deleting a file through `f.php` needs the delete code, which only the uploader is shown.
- `jirafeau-backend` is on the app-internal network only: no route, no published port,
  not on `pcs`. The router and the gate are the only ways in.
- The admin page has two locks: the gate, then Jirafeau's own admin password
  (`JIRAFEAU_ADMIN_PASSWORD: password:24`, shown under Credentials, changeable with
  `apply: env`).
- The root container only touches its own app folder (`/DATA/AppData/jirafeau/data`).
  Resource limits: router 64M, gate 128M, backend 256M.

## Alternatives considered

- **Jirafeau's own `UPLOAD_PASSWORD` instead of AppShield.** It works (`index.php` and
  `script.php` both check it), but it is one shared password with no SSO, and the
  owner would type it on every new browser. The gate gives the owner the server's own
  sign-in.
- **AppShield as the route's service with `ALLOWED_PATHS`.** Download traffic would then
  go through the gate's proxy, and the exemption would match on the gate's path rules
  instead of exact nginx locations. The router keeps the public list exact and readable.
- **Bind-mounting `config.local.php`** — see point 3.

## Data protection

Uploaded files, links, download counters and unfinished uploads are all under `/data`,
bind-mounted to `/DATA/AppData/jirafeau/data`, which survives uninstall and reinstall.
The config is derived from `.env`, which Maison keeps with the app. On a platform that
ignores `x-compose-app` (no generated secret), `ADMIN_PASSWORD` is empty and Jirafeau's
own admin login accepts an empty password, but `admin.php` is still behind the gate,
which then uses its own generated password.
