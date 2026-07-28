# Rclone Security and Configuration Rationale

## Security Exceptions

### User Permissions (user: $PUID:$PGID)
**Rationale**: Rclone runs as the system user to ensure proper file ownership and permissions. FUSE mounting is enabled through `SYS_ADMIN` capability and `/dev/fuse` device access.

**Benefits**: 
- Files created/mounted have correct user ownership
- No root-owned files that users cannot modify
- Follows CasaOS security best practices

### Privileged Container
**Rationale**: Required for FUSE mount propagation to work correctly. The `privileged: true` setting is necessary for:
- FUSE filesystem mounting inside containers
- Mount propagation with `:rshared,z` to make mounts visible on the host
- Access to `/dev/fuse` device

**Mitigation**:
- Limited to specific security contexts with `apparmor:unconfined`
- Volumes are specifically mapped and controlled
- Container only exposes web UI port (80)

### Mount Configuration
**Mount Point**: `/DATA/Rclone/:/data/:rshared,z`

**Rationale for rshared,z**:
- `:rshared` - Enables recursive mount propagation for FUSE mounts to be visible outside container
- `,z` - SELinux relabeling for proper security context on systems using SELinux

**Important**: Users must mount cloud remotes to `/data` inside the container for files to appear at `/DATA/Rclone` on the host system.

### Read-only host file mounts (`/etc/passwd`, `/etc/group`, `/etc/fuse.conf`)
**Rationale**: FUSE needs to resolve host UIDs/GIDs to names and to honour the host's
`user_allow_other` setting so that `--allow-other` mounts are visible to other containers.
All three are mounted `:ro` and are never written to.

## Configuration Requirements

### Authentication
- Default authentication enabled via `--rc-user admin --rc-pass $default_pwd`
- Web UI requires login with admin username and generated secure password
- Remote access controlled via `--rc-allow-origin "*"` (necessary for NSL router integration)

### Web GUI cache (`/DATA/AppData/rclone/cache/:/cache/`)
**Rationale**: `rcd --rc-web-gui` downloads and unpacks the web interface bundle into
`--cache-dir` on first start. The container runs as `$PUID:$PGID`, so that directory must be a
bind mount owned by the app user — without it the image's root filesystem is not writable by
the non-root user and rclone silently starts with no web interface (the API answers, but every
UI request returns `404 page not found`).

**The trailing slash on the source path is required**: CasaOS only pre-creates and chowns
volume sources that end in `/`. Any other source is created by Docker as `root:root`, which the
non-root app user still cannot write to.

Mounting it also persists the bundle across restarts, so the app does not re-download it on
every boot.

### Resource Limits
- `cpu_shares: 70` — interactive web UI with heavy background transfers, so it must stay
  responsive but should yield to administrative services.
- `memory: 2G` limit / `256M` reservation — rclone's baseline footprint is small, but VFS read
  chunks and parallel transfers are held in memory. 2 GB comfortably covers the settings
  recommended in the install tips (128M chunks, default 4 transfers). Users who raise the chunk
  size or transfer count should raise this limit too.

Note this is a memory limit only; CPU is shared via `cpu_shares` rather than a hard quota, so
large transfers are not artificially throttled on an otherwise idle machine.

### Mount Propagation Notes
The FUSE mount setup requires specific Docker configuration:
1. `cap_add: SYS_ADMIN` for mount operations
2. `devices: /dev/fuse:/dev/fuse:rwm` for FUSE access  
3. Mount propagation `rshared,z` for host visibility
4. Users mount remotes to `/data` which maps to `/DATA/Rclone/` on host
