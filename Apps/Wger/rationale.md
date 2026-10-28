# wger — Rationale

## What deviation / exception is being requested

1. The app authenticates with its own Django login rather than being fronted by the
   AppShield SSO sidecar.
2. Two services run as `user: 0:0` — the nginx front-end and PostgreSQL.
3. PostgreSQL is started with `wal_level=logical` so the PowerSync service can
   replicate from it.

## Why it is necessary

**1. The app's own login.** wger is a per-user training log: every routine, workout
log, body-weight entry and meal belongs to a Django user, and the app has no concept
of an anonymous session that a proxy could stand in for. So a user account is created
either way, and putting AppShield in front adds a *second* credential in front of a
login the user still has to pass. The store's checklist accepts "the app's own
built-in auth (e.g. Jellyfin, Immich onboarding)" as an alternative, which is what
this is: the login gate is on by default, on every route, and the shipped credential
is the app's own generated `WGER_ADMIN_PASSWORD` secret, not a published default.

Two settings that would weaken that gate are turned off explicitly, because upstream's
own defaults enable them:
- `ALLOW_REGISTRATION=False` — the app's default is `True`, which would put an open
  sign-up form on a public URL.
- `ALLOW_GUEST_USERS=False` — the app's default is `True`, which hands an
  unauthenticated visitor a working session and a temporary account.

Brute-force protection (`django-axes`, 10 failures then a 30-minute cool-off) is left
enabled, as upstream ships it.

**2. `user: 0:0` on two services.**
- `wger-router` (nginx): the master process writes `/var/run/nginx.pid` and `/var/cache/nginx`,
  neither writable by an unprivileged uid in `nginx:alpine`; the workers drop to the
  `nginx` user by themselves. This is the same arrangement as `Apps/Nginx` and
  `Apps/Plex`'s front-end in this store.
- `wger-db` (postgres): the official entrypoint starts as root only to `chown` `PGDATA`
  and then re-executes as the `postgres` user. Same as `Apps/Spliit`.

The application containers (`wger-web`, `wger-worker`, `wger-beat`) run unprivileged as
`$PUID:$PGID`, which is also the uid the image's own `wger` user has.

**3. `wal_level=logical` on the database.** The `wger-powersync` service is what the
phone app syncs through, and it reads the database over a logical replication slot. The
image default, `wal_level=replica`, cannot feed one, and the setting only takes effect
on a restart, so it is a `command:` override on the postgres service rather than
something a running app can turn on.

This service is not optional, though an earlier revision of this app shipped without it
on the belief that the phone app falls back to the REST API. It does not: the Flutter
client has been offline-first on PowerSync since 2.0.3, and this server's
`MIN_APP_VERSION` is 2.1.0, so *every* app version it will talk to needs it. Without the
service the app logs in and then sits on "Sync Service Unreachable", because
`/api/v2/powersync-token` hands it `SITE_URL` + `/ps/` and nothing answers there. The web
UI is unaffected either way — it contains no reference to PowerSync at all.

The cost is one more container (118 MB image, a 512M limit) and a second database role.
Most of what made it look expensive is now done by the app itself: the replication
publication is created by wger's own core migration 0027, and the storage role and
schema by its `setup-powersync-storage` management command, which the
`setup-powersync-storage` step runs.

The one genuinely new operational risk is the replication slot: an inactive slot pins
WAL, and on a personal server where a container can sit stopped for a week that fills
`/DATA`. `max_slot_wal_keep_size=1GB` caps it — past that postgres invalidates the slot
and PowerSync takes a fresh snapshot, which costs the phone a resync rather than any
data. Upstream's compose sets no such cap.

The slot also makes the flag load-bearing for *startup*, which is worth knowing before
anyone edits this service. Postgres will not boot against a data directory holding a
logical slot if `wal_level` is lower than `logical` — it logs `FATAL: logical
replication slot ... exists, but wal_level < logical` and aborts. Removing the flag, or
rolling the app back to a revision from before PowerSync, therefore takes the whole app
down rather than only its sync: the database restart-loops and every service gated on
its healthcheck stays in `Created`. Recovery is to restore the flag, at which point the
slot resumes from where it stopped; deleting the slot is both lossier and needs
`wal_level=logical` to start postgres in the first place. Observed on a test server on
2026-09-08, from a store render that predated the PowerSync revision.

## Security mitigations in place

- Only the nginx front-end (`wger-router`) is on the shared `pcs` network. The application, database,
  cache and both celery processes are on an app-private bridge and are not addressable
  from any other app on the box.
- No host port is published by any service.
- Every credential is generated per deployment: `WGER_SECRET_KEY` and
  `WGER_DB_PASSWORD` and `WGER_PS_STORAGE_PASSWORD` through `x-compose-app.secrets`, the
  JWT signing keypair through the `jwt-keys` step, and the admin password from the
  per-app `WGER_ADMIN_PASSWORD` secret (shown by Maison as the app's credentials).
- `PS_STORAGE_PG_URI` is set explicitly rather than left to the app's default, which is
  the literal `postgres://powersync_storage:powersync_password@db:5432/wger` — inheriting
  it would give the deployment a database role whose password is published upstream.
  PowerSync's role owns only its own sync-bucket schema; it is not the app's database
  user.
- wger seeds its first admin from a fixture as `admin` / `adminadmin` — a published
  upstream default — with no environment variable to change it. The
  `rotate-admin-password` step replaces it once the app is up, and only when the
  password is still that default, so it cannot overwrite a password the owner has
  since chosen. It compares the stored hash directly rather than attempting a login,
  so it never contributes to a `django-axes` lockout.
- Both nginx mounts (`static`, `media`) are read-only, and nothing outside
  `/DATA/AppData/wger` is mounted into any container.
- Resource limits are set on all seven services (64M … 1G, ~3.1G in total).
- `wger-powersync` is on the app-private bridge only. The phone reaches it through
  nginx's `/ps/` route, on the same host and certificate as the app, and it accepts only
  tokens signed by the app's own JWT key (`client_auth.audience: powersync`).

## Alternatives considered and rejected

- **Keeping the app PowerSync-free and documenting the gap.** Rejected: it is not a
  missing extra but the phone app's only sync path, and the failure is a red banner
  immediately after login rather than a feature quietly absent.
- **A dedicated PostgreSQL instance for PowerSync's bucket storage**, as some PowerSync
  deployments run. Rejected: it stores sync state, not user data, and upstream keeps it
  in a schema of the same database — a second postgres container would cost more memory
  than the service it serves.
- **Splitting PowerSync into separate `api` and `sync` containers**, which upstream
  documents. Rejected: that split is for scaling out, and one person's training log does
  not need it; `-r unified` runs both in one process.
- **AppShield in front of the whole app.** Rejected: two logins for one person, for
  the reason above. AppShield 3.x no longer collides with an app's own `/login`, so
  this is a usability call rather than a technical block.
- **AppShield plus wger's `AUTH_PROXY_HEADER`**, which exists precisely to accept an
  identity from an authenticating reverse proxy and would give real single sign-on.
  Rejected for now: it is only safe when `AUTH_PROXY_TRUSTED_IPS` pins the proxy, and
  on a Docker bridge the sidecar's address is assigned from the subnet at start, so the
  pin would have to name the whole subnet — which on a shared network means any
  container could assert any identity. Worth revisiting if AppShield gains a signed
  identity assertion the app can verify (3.x has `IDENTITY_ASSERTION_SECRET`, which
  wger cannot currently consume).
- **Dropping nginx and letting gunicorn serve the app alone.** Rejected: Django with
  `DEBUG=False` serves neither `/static/` nor `/media/`, and wger does not bundle
  whitenoise, so the app renders unstyled and every exercise image 404s. Upstream's
  compose carries the same warning.
- **Dropping celery** (`USE_CELERY=False`). Rejected: it is what runs the weekly
  exercise-database refresh, the exercise-image downloads and the barcode scanner's
  on-demand ingredient fetch — the last of which upstream documents as requiring
  celery.
- **Upstream's bulk sync defaults.** `SYNC_INGREDIENTS_CELERY` and
  `SYNC_EXERCISE_VIDEOS_CELERY` are `True` upstream; both are off here. The ingredient
  dump is a multi-hundred-megabyte import and the videos are larger again, which is not
  a reasonable default for a personal server. Both are named in `tips.before_install`
  so the choice is visible, and the barcode scanner still fetches products one at a
  time via `DOWNLOAD_INGREDIENTS_FROM`.
- **`SYNC_EXERCISES_ON_STARTUP=True`**, the app's own way of populating the exercise
  database. Rejected after measuring it: it runs inside the app container's entrypoint,
  ahead of gunicorn, and re-walks every exercise on *every* start -- 5 minutes of
  downtime per restart, not a one-off first-boot cost. With it off, a restart is about
  80 seconds. The same work is queued onto celery once, at install, by the
  `seed-exercise-database` step, which leaves the app answering while it runs.
- **Letting the exercise refresh arrive only via the weekly celery job.** Rejected as
  the sole mechanism: `add_periodic_task` picks a random day-of-week and time when beat
  starts (`wger/exercises/tasks.py`), so the pictures would be up to a week away on a
  fresh install. The step queues both jobs immediately; the weekly schedule then
  keeps them current. Measured on a fresh install: the metadata sync finished in ~3.5
  minutes and the images in ~2 more (about 900 exercises, ~210 MB), with the app
  answering throughout. The image download is queued with an explicit
  `time_limit`/`soft_time_limit` as a guard rather than a routine need: upstream's
  fetches set no HTTP timeout, and a hand-run `download-exercise-images` was seen
  wedged on one request for over ten minutes. Unbounded, that would hold the only
  worker process — and every job behind it — until the app was restarted.

## Data protection

All state is under `/DATA/AppData/wger/` — `pgdata` (the database), `media` (uploaded
and downloaded exercise images and videos), `static` (regenerated on every start),
`redis` (cache and queue), `beat` (the celery schedule) and `config-powersync` (the sync
service's config) — so it survives uninstall
with "keep user data" and reinstall. The database password and Django secret key are
generated once into the app's `.env` and never regenerated, so an existing database
keeps opening and existing sessions keep working across restarts, updates and restores.
The JWT keypair is likewise generated only when absent: regenerating it would log out
every phone already paired with the server.

Version upgrades are handled by the app's own Django migrations, which run in
`wger-web` on start; the two celery containers are pinned to the same image but have
`DJANGO_PERFORM_MIGRATIONS=False` so that only one process ever applies a migration.
