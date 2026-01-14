# Odoo Security Rationale

## Root Container Usage

This application uses root containers (`user: "0:0"`) for both PostgreSQL and Odoo services.

### Why Root is Required

**CasaOS Permission Behavior:**
- CasaOS automatically applies PUID:PGID (1000:1000) when no `user` field is specified
- This differs from standard Docker behavior and can cause conflicts with official images

**PostgreSQL Service:**
- The official PostgreSQL image expects to run as the `postgres` user (UID 999)
- When CasaOS applies UID 1000, PostgreSQL cannot properly initialize or access its data directory
- Running as root allows PostgreSQL to properly manage file permissions in `/var/lib/postgresql/data`

**Odoo Service:**
- The official Odoo image expects to run as the `odoo` user
- Similar to PostgreSQL, CasaOS's automatic UID 1000 assignment conflicts with Odoo's internal user management
- Running as root ensures proper access to `/var/lib/odoo`, `/etc/odoo`, and `/mnt/extra-addons`

### Security Mitigation

**Volume Isolation:**
- All volumes are mapped exclusively to `/DATA/AppData/$AppID/`
- No access to user directories (`/DATA/Documents/`, `/DATA/Media/`, etc.)
- No shared volumes with other applications

**Network Isolation:**
- PostgreSQL is not exposed outside the Docker network
- Only Odoo's web interface (port 8069) is exposed via NSL Router
- Database communication is container-to-container only

**Official Images:**
- Using official `postgres:15.15` and `odoo:18.0` images from Docker Hub
- These images have been security audited and are regularly updated
- Images include internal security measures and user management

### Alternative Approaches Considered

1. **Using specific UIDs (999 for postgres, odoo UID for Odoo):**
   - Would require knowing exact UIDs used by official images
   - Would break when images change their internal user IDs
   - Less maintainable across updates

2. **Custom entrypoint scripts:**
   - Would add complexity and maintenance burden
   - Could introduce security vulnerabilities
   - Would deviate from official image best practices

3. **User directory access:**
   - Not required for this application
   - All data is contained within AppData directory

### Conclusion

Root containers are necessary for this application due to CasaOS's automatic PUID/PGID behavior conflicting with official PostgreSQL and Odoo images. The security risk is minimal because:
- Volumes are isolated to AppData only
- Using official, security-audited images
- No access to user directories or system files
- PostgreSQL is not exposed outside the container network