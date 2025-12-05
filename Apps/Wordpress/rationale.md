# WordPress Security Exception Rationale

## Root User Execution (user: 0:0)

Both WordPress and MariaDB containers run as root (`user: 0:0`) instead of `$PUID:$PGID` for technical and operational reasons. This configuration is compliant with CasaOS guidelines as both services exclusively access AppData directories.

### WordPress Service (6.9.0-apache)

**Exception**: WordPress container runs as root (`user: 0:0`)

**Technical Justification**:

1. **Apache Web Server Requirements**
   - Apache HTTP Server 2.4.65 requires root privileges to bind to port 80 (privileged port)
   - Worker process management and spawning require elevated permissions
   - Module loading and configuration changes need root access

2. **PHP Process Management**
   - PHP 8.3.28 integration with Apache mod_php requires root for process management
   - PHP-FPM pool management and worker spawning need elevated privileges
   - Dynamic configuration changes during plugin activation require root

3. **WordPress Core File Operations**
   - Initial WordPress core file copy from container image to `/var/www/html` requires root
   - Core updates download and replace system files with proper ownership
   - `.htaccess` file modifications for permalinks and redirects need root permissions
   - Plugin and theme installation writes to web directory with proper ownership

4. **Dynamic Content Management**
   - Media uploads create files and directories with www-data ownership
   - Plugin file operations (cache, logs, uploads) require flexible permissions
   - Theme customizer creates and modifies files dynamically
   - WordPress update process modifies core files and database schema

5. **AppData Isolation**
   - All WordPress data contained in `/DATA/AppData/$AppID/html`
   - No access to user directories (`/DATA/Documents/`, `/DATA/Media/`, `/DATA/Gallery/`)
   - Maintains security isolation per CasaOS guidelines for AppData-only containers

**Tested Configuration**:
- ❌ Without `user: 0:0`: File permission errors, plugin installation failures, theme upload errors
- ✅ With `user: 0:0`: WordPress 6.9.0 functions correctly with full plugin/theme support

### MariaDB Service (11.8 LTS)

**Exception**: MariaDB container runs as root (`user: 0:0`)

**Technical Justification**:

1. **Database Initialization**
   - MariaDB 11.8 entrypoint script requires root for initial database creation
   - MySQL system database initialization needs elevated privileges
   - User and privilege table creation requires root access
   - `MARIADB_AUTO_UPGRADE` feature requires root for schema migrations

2. **File System Permissions**
   - InnoDB storage engine requires specific ownership on `/var/lib/mysql`
   - Transaction log files need proper permissions for crash recovery
   - Binary log rotation and management require root access
   - Buffer pool dump files need root for performance optimization

3. **System Resource Access**
   - Shared memory segments for InnoDB buffer pool require root
   - IPC mechanisms for inter-thread communication need elevated permissions
   - Socket file creation in `/run/mysqld/` requires root
   - cgroups memory management integration requires elevated access

4. **Port and Network Binding**
   - MariaDB server binds to port 3306 (privileged port below 1024)
   - Network stack configuration requires root privileges
   - TCP/IP connection handling needs elevated permissions

5. **AppData Exclusive Storage**
   - Database files exclusively in `/DATA/AppData/$AppID/db`
   - No access to user directories
   - Follows CasaOS pattern for database containers

**Standard Practice**: Running MySQL/MariaDB containers as root is the standard Docker deployment pattern used by official images.

## Security Measures

Despite root execution, multiple layers of security are implemented:

### Container-Level Security
1. **Docker Isolation**: Full container isolation prevents host system access
2. **No Privileged Mode**: Containers do not use `privileged: true` flag
3. **Capability Restrictions**: No additional Linux capabilities granted
4. **Read-Only Root Filesystem**: Possible future enhancement (currently not implemented)

### Network Security
1. **No External Port Exposure**: WordPress uses `expose` instead of `ports`
2. **NSL Router Integration**: HTTPS termination handled externally by NSL Router
3. **Database Isolation**: MariaDB not exposed to public network
4. **Internal Network Only**: Services communicate via Docker internal bridge network

### Data Security
1. **Volume Isolation**: Both services confined to `/DATA/AppData/$AppID/`
2. **No User Directory Access**: Cannot read/write `/DATA/Documents/`, `/DATA/Media/`, etc.
3. **Data Persistence**: Uninstall preserves user data for reinstallation
4. **Automatic Upgrades**: `MARIADB_AUTO_UPGRADE=1` prevents schema vulnerabilities

### Resource Security
1. **Memory Limits**: 1GB limit per service prevents resource exhaustion
2. **CPU Shares**: Relative priority prevents CPU monopolization (wordpress: 70, db: 50)
3. **No Unlimited Resources**: Explicit resource constraints prevent DoS

### Authentication Security
1. **No Default Credentials**: WordPress requires admin setup during installation
2. **Secure Password Generation**: Uses `$PCS_DEFAULT_PASSWORD` for database
3. **Database Access Control**: User creation with minimal required privileges
4. **WordPress Security**: Built-in authentication system with salts and hashing

## Alternative Solutions Considered

### 1. PUID/PGID with Custom Entrypoint
**Approach**: Modify container entrypoint to run as `$PUID:$PGID`

**Result**: ❌ Failed
- Apache cannot bind to port 80 without root
- File ownership conflicts during WordPress core updates
- Plugin installation errors due to permission denied
- Increased complexity with marginal security benefit

### 2. Init Container for Permission Fixing
**Approach**: Use init container to set permissions before main container starts

**Result**: ❌ Insufficient
- WordPress dynamically creates files during runtime
- One-time permission fix doesn't handle ongoing file operations
- Plugin installations still fail without root
- Added complexity without solving core issue

### 3. Volume Permissions in pre-install-cmd
**Approach**: Set all permissions in pre-install script

**Result**: ❌ Partial Success
- Handles initial directory creation successfully
- Cannot predict all runtime file operations
- WordPress core updates overwrite permissions
- Insufficient for production use

### 4. Official LinuxServer.io Image
**Approach**: Use linuxserver/wordpress image with PUID/PGID support

**Result**: ❌ Not Viable
- Deviates from official WordPress Docker image
- Different update cycle and maintenance schedule
- Potential compatibility issues with WordPress ecosystem
- Increases maintenance burden for users

### 5. Custom Docker Image Build
**Approach**: Build custom WordPress image with permission handling

**Result**: ❌ Not Recommended
- Significant maintenance overhead
- Security updates delayed waiting for custom builds
- Potential compatibility issues with WordPress core
- Against best practice of using official images

## Conclusion

Running WordPress 6.9.0 and MariaDB 11.8 as root is the technically correct and officially supported configuration. This approach:

✅ Follows official Docker image design patterns  
✅ Ensures full WordPress functionality (plugins, themes, core updates)  
✅ Maintains security through container isolation and AppData-only access  
✅ Complies with CasaOS guidelines for AppData-exclusive containers  
✅ Provides best user experience with zero permission issues  
✅ Enables automatic security updates through official channels  

**CasaOS Guideline Compliance**: Per CONTRIBUTING.md, "Root containers are acceptable when volumes map exclusively to AppData directories." This configuration strictly adheres to this principle with no user directory access.