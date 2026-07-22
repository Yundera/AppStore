# Immich Rationale

## Authentication

Authentication is directly managed by Immich itself. The application provides its own built-in user management system with secure login functionality, including:

- User registration and login system
- Password-based authentication
- Multi-user support with individual libraries
- Admin panel for user management

No additional authentication layer is required as Immich handles all security aspects internally through its web interface.

## Timezone (`TZ: Etc/UTC` instead of `$TZ`)

The `TZ` environment variable is hardcoded to `Etc/UTC` for the `immich`, `immich-machine-learning`, and `redis` services rather than using the `$TZ` system variable.

Starting with Immich v3.0.0, the server schedules background jobs with a stricter cron library (`cron@4.4.0`) that **rejects an empty or malformed timezone**, crash-looping the API worker with `CronError: ERROR: You specified an invalid date.` The value substituted into `$TZ` by the platform cannot be relied upon to be a valid IANA timezone name (observed values include `/UTC` and `TZ=UTC`), so passing it through would break the app on affected servers.

Immich already operates entirely in UTC — the `database` service hardcodes `TZ: UTC`, and photo timestamps are stored with their original offsets — so pinning `Etc/UTC` matches existing behavior and eliminates the crash risk. `Etc/UTC` is also Immich's own recommended default (see the upstream `example.env`). This does not affect how photo/video capture times are displayed; those come from each file's own metadata.

## Database healthcheck (inline `$$(...)` instead of a named `$$Chksum` variable)

The `database` healthcheck uses inline command substitution — `[ "$$(psql … SUM(checksum_failures) …)" = '0' ]` — rather than assigning the result to a `Chksum` shell variable and testing `$$Chksum`.

Immich's upstream healthcheck stores the count in a `$$Chksum` variable. On Yundera, CasaOS re-serializes the compose file when it imports the app and collapses `$$Chksum` down to `$Chksum`. Docker Compose then treats `$Chksum` as an (unset) interpolation variable and substitutes an empty string, so the test becomes `[ "" = '0' ]`, which always fails — the Postgres container is reported **unhealthy** even though the database is fine (and CasaOS surfaces the whole app as unhealthy). Command substitution `$$(...)` contains no bare `$VAR`, so it survives the collapse and the check evaluates correctly. Functionally identical to upstream: healthy when `checksum_failures = 0`, unhealthy otherwise.