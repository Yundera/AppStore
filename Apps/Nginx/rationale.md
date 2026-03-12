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
- Pre-install script sets `chmod -R 755` on AppData directory for accessibility
- Users can still edit files via file managers or SSH if needed

## Pre-Install Script Approach

**Implementation**: Uses shell commands (`mkdir`, `cat`) directly rather than Docker containers.

**Reason**:
- Simple file creation doesn't require containerized tooling
- More efficient for basic directory and file setup
- Idempotent: Checks if files exist before creating them
- No security risk as no external resources are downloaded
- Follows patterns seen in other AppStore apps for basic initialization

All operations are idempotent and safe to run multiple times during reinstallation.
