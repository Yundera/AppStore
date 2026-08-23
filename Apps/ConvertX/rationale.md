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
   - The **AppShield** OIDC sidecar (`ghcr.io/yundera/appshield`) is the authentication
     boundary: it fronts the app, authenticates every request against the PCS's built-in
     Authelia SSO, and is the only service carrying Caddy labels
   - The ConvertX backend is not published. It sits on the app-private
     `convertx-internal` network and is reachable only through the sidecar
   - `ALLOW_UNAUTHENTICATED=true` is set on the backend deliberately — ConvertX's own
     login screen would be a second, redundant credential in front of a user the SSO gate
     has already authenticated. It does **not** mean the app is publicly reachable
   - `ACCOUNT_REGISTRATION=false` prevents unauthorized account creation

2. **JWT Secret Protection**
   - Uses `$APP_DEFAULT_PASSWORD` for JWT secret generation
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

### Alternative Approaches Considered

1. **Running as PUID:PGID** - Rejected due to SQLite permission conflicts and conversion tool requirements
2. **Separate containers** - Not feasible as conversion happens in single integrated process
3. **Volume permission pre-configuration** - Insufficient for dynamic file creation during conversion

### Conclusion

Root access is necessary for ConvertX to function properly due to its SQLite database architecture and multi-tool integration requirements. Security is maintained through the AppShield SSO gate in front of the app, read-only user directory access, and data isolation to AppData directories.