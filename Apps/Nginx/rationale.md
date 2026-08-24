# Rationale for Nginx Configuration

This document explains deviations from standard AppStore guidelines for the nginx app.

## No Default Authentication

**Guideline**: Apps should have default authentication enabled.

**Exception Reason**: nginx is a static website hosting server designed to serve public websites. Authentication is intentionally not included because:

1. **Primary Use Case**: Hosting public-facing websites, portfolios, documentation, and landing pages that should be accessible without authentication
2. **Static Content Nature**: Serves read-only content (HTML, CSS, JavaScript, images) with no backend processing or sensitive data handling
3. **User Control**: Users have full control over their website content and can implement their own authentication mechanisms at the application level if needed (e.g., JavaScript-based auth, password-protected pages)
4. **Intended Audience**: Public websites, documentation sites, and portfolios are meant to be publicly accessible

**Security Considerations**:
- All files are served from `/DATA/AppData/nginx/www/`, which requires server access to modify
- The nginx configuration includes security headers (X-Frame-Options, X-Content-Type-Options, X-XSS-Protection)
- Hidden files (.*) are explicitly denied access in the nginx configuration
- Users can implement their own authentication layer if their use case requires it

## Running as Root (user: 0:0)

**Guideline**: Prefer PUID:PGID for better user access to configurations.

**Configuration**: This app runs as `user: 0:0` (root) with `PUID=0` and `PGID=0`.

**Reason**:
- nginx typically requires root privileges to bind to port 80 and manage its processes
- The app only accesses `/DATA/AppData/nginx/` (AppData directory only)
- According to CONTRIBUTING.md guidelines: "Root containers are acceptable when volumes map exclusively to AppData"
- No user directory access required (`/DATA/Documents/`, `/DATA/Downloads/`, etc.)

**Permission Strategy**:
- AppData-only access pattern
- `/DATA/AppData/nginx/` and `/DATA/AppData/nginx/www/` are declared under
  `x-compose-app.folders`, so Maison creates them and chowns them to `$PUID:$PGID`
  before every `up`. Users can edit `nginx.conf` and add website files through the
  built-in file manager or over SSH; nothing here is chmod'ed by the install hook.
- The shipped `nginx.conf` additionally sets `user root;`. The stock image drops
  its worker processes to uid 101, which cannot read a file created mode 0640 —
  the mode the platform's file manager writes with. nginx then answers a bare 403
  and the user's site silently never updates, which defeats the app's whole
  "drop your files in" premise. Since the container is already root and mounts
  nothing outside its own AppData folder, running the workers as root too widens
  no boundary and is what makes the advertised workflow actually work.

## Pre-Install Script Approach

**Implementation**: Style A (plain shell on the host). The hook runs two guarded
`wget` calls that seed `www/index.html` and `nginx.conf`; it creates no directories
and changes no permissions.

**Reason**:
- Seeding two static files doesn't require containerized tooling.
- Directories are declared under `x-compose-app.folders` instead, so Maison creates
  and chowns them before the hook runs — per CONTRIBUTING, a hook must not `mkdir`,
  because the hook executes inside the Maison container and would leave a
  root-owned directory on the host.
- Idempotent: each fetch is guarded by an existence check, so a reinstall or a
  version upgrade never overwrites the user's site or their edited `nginx.conf`.

**Downloads**: both assets are fetched from
`cdn.jsdelivr.net/gh/Yundera/AppStore/Apps/Nginx/pre-install/` — this repository
itself, over HTTPS, which is the pattern CONTRIBUTING documents for Style A. No
third-party host is contacted, no credential is baked in, and the hook is
non-interactive.
