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