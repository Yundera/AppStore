# Tailscale Security Rationale

## Root User Exception

This application runs as `user: 0:0` (root) which is an exception to the standard CasaOS security policy.

### Justification for Root Access
- Required for direct TUN device access (`/dev/net/tun`)
- Tailscale daemon needs privileged networking capabilities
- Enables full mesh VPN functionality without limitations

### Security Mitigations
- Uses userspace networking mode (`TS_USERSPACE=true`) to reduce kernel attack surface
- Container is isolated from the host system
- Network traffic is encrypted end-to-end via WireGuard protocol
- Persistent data stored in dedicated directories under `/DATA/AppData/tailscale/`

### Functional Benefits
Running with root privileges enables:
- Full networking performance without userspace overhead
- Complete VPN functionality including exit node capabilities
- Reliable TUN interface management
- Optimal mesh networking between devices

### Design Decision
Root access was chosen to:
- Provide complete Tailscale functionality
- Ensure reliable VPN performance
- Maintain compatibility with standard Tailscale deployment patterns
- Enable advanced networking features like subnet routing

This configuration balances security considerations with full VPN functionality requirements.