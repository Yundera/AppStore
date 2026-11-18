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
- Container exposes only the GUI (5580) and RC API (5572) ports, to the app's own network;
  `rclone-router` is the only service on the shared network

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
- `rclone gui --user admin --pass $RCLONE_ADMIN_PASSWORD`: every RC API call needs that login
- The GUI itself is static files (no data); its first screen is the "Connect to rclone" login,
  and nothing behind it loads without the credentials
- GUI and API share one host through `rclone-router` (GET/HEAD → GUI, other methods → API), so
  no cross-origin access is needed

### Web GUI (rclone 1.76 and later)
rclone 1.76 removed `rcd --rc-web-gui` (it now exits with "superseded by the `rclone gui`
command"). `rclone gui` serves the GUI embedded in the binary, so nothing is downloaded at
start. The GUI learns the API address only from `/login?url=…`; the router sends a browser
that has never connected there, with this host's own address. The `rclone_gui` cookie that
marks a browser as connected is set only on a successful authenticated API call, the moment
the GUI itself stores the address.

### Cache (`/DATA/AppData/rclone/cache/:/cache/`)
**Rationale**: `--cache-dir` holds the VFS cache of mounts. The container runs as
`$PUID:$PGID`, so the directory must be a bind mount owned by the app user (declared under
`folders`): the image's root filesystem is not writable by the non-root user.

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

