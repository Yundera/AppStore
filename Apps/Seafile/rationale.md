# Seafile App - Security and Architecture Rationale

## Root User Usage

This Seafile deployment uses root containers for several services due to technical requirements:

### Database Service (MariaDB)
- **Reason**: MariaDB requires root privileges for proper initialization and database management
- **Mitigation**: Data is isolated to `/DATA/AppData/seafile/mysql` with no user directory access

### Redis Service
- **Reason**: Redis runs as root for consistency with other services in the stack
- **Mitigation**: Limited to internal networking, no external exposure, resource limited

### Seafile Application Services
- **Reason**: Seafile-mc container requires root for internal service management and initialization
- **Mitigation**: All services are contained within the seafile-net network with controlled exposure

### RClone FUSE Mount Service
- **Reason**: FUSE mounting requires root privileges and system capabilities:
  - `privileged: true` for FUSE operations
  - `SYS_ADMIN` capability for mount operations  
  - `/dev/fuse` device access
- **Mitigation**: File ownership is properly managed via `--uid $PUID --gid $PGID` flags, ensuring mounted files at `/DATA/Seafile` have correct user permissions

### Caddy Reverse Proxy
- **Reason**: Caddy-docker-proxy requires Docker socket access for dynamic configuration
- **Mitigation**: Limited to reverse proxy functionality, no direct data access

## Resource Limits Justification

Resource limits are set based on typical usage patterns:

- **Database**: 1GB memory, 1 CPU - handles metadata and user data
- **Seafile App**: 2GB memory, 1.5 CPU - main application processing
- **Redis**: 256MB memory, 0.25 CPU - caching layer
- **Notification Server**: 128MB memory, 0.1 CPU - lightweight service
- **Seadoc**: 512MB memory, 0.5 CPU - document editing service
- **RClone**: 256MB memory, 0.25 CPU - file system mounting
- **Caddy**: 128MB memory, 0.1 CPU - lightweight reverse proxy

These limits provide adequate performance while preventing resource exhaustion on shared systems.

## Network Isolation

All services communicate through the isolated `seafile-net` network, with only the main web interface exposed via NSL Router integration.