# WordPress Security Exception Rationale

## Root User Execution (user: 0:0)

### WordPress Service
**Exception**: WordPress container runs as root (`user: 0:0`) instead of `$PUID:$PGID`

**Justification**:
1. **File Copy Issues**: WordPress requires root permissions to properly copy and install core files, themes, and plugins to `/var/www/html`
2. **Permission Management**: WordPress needs to create and modify files within its web directory structure
3. **Plugin/Theme Installation**: Many WordPress plugins and themes require write permissions that are difficult to achieve with non-root users
4. **AppData Isolation**: All WordPress data is contained within `/DATA/AppData/$AppID/html`, maintaining security isolation
5. **No User Directory Access**: WordPress does not access user directories like `/DATA/Documents/` or `/DATA/Media/`

**Tested Configuration**: 
- Without `user: 0:0`: File permission errors prevent WordPress installation and plugin management
- With `user: 0:0`: WordPress functions correctly with proper file operations

### MariaDB Service
**Exception**: MariaDB container runs as root (`user: 0:0`)

**Justification**:
1. **Database Initialization**: MariaDB requires root privileges for database initialization and user creation
2. **File System Permissions**: Database files in `/var/lib/mysql` require specific ownership for proper operation
3. **AppData Exclusive**: Database files are exclusively stored in `/DATA/AppData/$AppID/db`
4. **Standard Practice**: Running database containers as root is standard practice for MySQL/MariaDB containers

## Security Mitigations

1. **Volume Isolation**: Both services only access `/DATA/AppData/$AppID/` directories
2. **No Privileged Mode**: Containers do not run in privileged mode
3. **Resource Limits**: Memory limits prevent resource exhaustion
4. **Network Isolation**: Services communicate only through Docker internal network
5. **Default Authentication**: WordPress requires admin account creation during setup

## Alternative Solutions Considered

1. **PUID/PGID with Init Container**: Tested but caused file ownership conflicts
2. **Custom Entrypoint Scripts**: Added complexity without resolving core permission issues
3. **Volume Permissions in pre-install**: Insufficient for WordPress's dynamic file operations

This configuration follows the principle that root containers are acceptable when volumes map exclusively to AppData directories, as stated in the contributing guidelines.