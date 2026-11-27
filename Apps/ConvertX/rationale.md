# ConvertX Security Exception Rationale

## Root User Requirement

### Why Root Access is Needed

ConvertX requires root user (`user: "root"`) for the following technical reasons:

1. **SQLite Database Permissions**
   - The application uses SQLite for user authentication and session management
   - SQLite requires specific file ownership and permissions to create and modify database files
   - The application's internal architecture expects to write to `/app/data` with unrestricted permissions

2. **Temporary File Processing**
   - File conversion operations create temporary files during processing
   - Multiple conversion tools (FFmpeg, ImageMagick, Pandoc) require write access to temp directories
   - Root access ensures all conversion tools can write temporary files without permission conflicts

3. **Multi-tool Integration**
   - ConvertX integrates multiple conversion libraries that may have different permission requirements
   - Running as root ensures compatibility across all integrated tools

### Security Mitigations

While running as root, the following security measures are in place:

1. **Authentication Required**
   - The **AppShield** OIDC sidecar (`ghcr.io/nsl-sh/appshield`) is the authentication
     boundary: it fronts the app, authenticates every request against the PCS's built-in
     Authelia SSO. Every path except the PWA manifest (see below) reaches the app only
     through it
   - The ConvertX backend is not published. It sits on the app-private
     `convertx-internal` network and is reachable only through the sidecar
   - `ALLOW_UNAUTHENTICATED=true` is set on the backend deliberately — ConvertX's own
     login screen would be a second, redundant credential in front of a user the SSO gate
     has already authenticated. It does **not** mean the app is publicly reachable
   - `ACCOUNT_REGISTRATION=false` prevents unauthorized account creation

2. **JWT Secret Protection**
   - Uses its own `CONVERTX_JWT_SECRET` (an `x-compose-app` secret, generated once per install) as the JWT secret
   - Session tokens are cryptographically secure

3. **Auto-cleanup**
   - `AUTO_DELETE_EVERY_N_HOURS=24` automatically removes processed files
   - Reduces attack surface by limiting stored data

4. **Read-only Volume Mounts**
   - User directories (`/downloads`, `/documents`) are mounted as read-only (`:ro`)
   - Application can only read source files, not modify user data

5. **Isolated AppData**
   - All writable data confined to `/DATA/AppData/$AppID/`
   - No direct access to system-critical directories

6. **`/site.webmanifest` is served outside the gate, by the app's own router**
   - ConvertX's pages link `<link rel="manifest" href="/site.webmanifest">` with no
     `crossorigin` attribute, so browsers fetch it without credentials and the SSO cookie
     never reaches the gate: it answered with a redirect to the login host, and the browser
     logged a CORS error on a user's first visit
   - The manifest is static PWA metadata (app name, theme colour, icon paths), identical for
     every visitor, and carries nothing about the user
   - The gate carries **no** `ALLOWED_PATHS` (AppShield matches an exempt path as a raw
     prefix and forwards it un-normalised). Instead `convertx-router` (nginx, in front of
     the gate, as in `Apps/Linkwarden` and `Apps/ChangeDetection`) has one exact-match
     `location = /site.webmanifest`, GET only, proxied to the backend with that fixed URI.
     nginx resolves dot segments and percent-escapes before matching, so a path such as
     `/site.webmanifest/../history` normalises to `/history` and goes to the gate like
     every other path. This is not a machine-client path, so `OAUTH_RESOURCE` does not apply

### Alternative Approaches Considered

1. **Running as PUID:PGID** - Rejected due to SQLite permission conflicts and conversion tool requirements
2. **Separate containers** - Not feasible as conversion happens in single integrated process
3. **Volume permission pre-configuration** - Insufficient for dynamic file creation during conversion

### Conclusion

Root access is necessary for ConvertX to function properly due to its SQLite database architecture and multi-tool integration requirements. Security is maintained through the AppShield SSO gate in front of the app, read-only user directory access, and data isolation to AppData directories.