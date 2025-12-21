# Navidrome Security Rationale

## Root User Permission (user: "0:0")

### Why Root Permission is Required

Navidrome requires root execution due to internal cache directory permission management:

1. **Internal Cache Structure**: Navidrome creates complex nested cache directories (`/data/cache/images/`) with specific permission requirements that conflict with PUID:PGID execution

2. **Permission Denied Errors**: When running as `user: $PUID:$PGID`, Navidrome fails to create and access cache directories:
   ```
   Error accessing image cache: open /data/cache/images/64/78/...: permission denied
   Error accessing image cache: mkdir /data/cache/images/84: permission denied
   ```

3. **Official Image Design**: The deluan/navidrome image is designed to manage its own internal permissions and expects to run with elevated privileges for cache management

### Security Justification

Root execution is safe for this application because:

1. **AppData-Only Access**: All writable volumes are mapped exclusively to `/DATA/AppData/navidrome/`
   - `/DATA/AppData/navidrome/data/:/data` - Configuration and database storage
   
2. **Read-Only Media Access**: Music library is mounted read-only (`/DATA/Media/Music/:/music:ro`), preventing any modifications to user media files

3. **No User Directory Modifications**: The application cannot write to user-accessible directories like `/DATA/Documents/`, `/DATA/Downloads/`, or `/DATA/Gallery/`

4. **Isolated Container Environment**: Container isolation limits the scope of root access to the container filesystem only

5. **Resource Limits**: Memory limit (512M) prevents resource exhaustion attacks

### Alternative Approaches Considered

1. **PUID:PGID with Pre-install Scripts**: Attempted but failed due to Navidrome's dynamic cache directory creation patterns
2. **Manual Permission Fixes**: Not viable as cache directories are created on-demand during runtime
3. **Custom Entrypoint**: Would require maintaining a fork of the official image, reducing security and update reliability

### Conclusion

Root execution is the recommended approach for Navidrome as it:
- Ensures stable operation without permission errors
- Maintains security through AppData-only write access
- Aligns with the official image's intended usage
- Provides the best user experience with zero manual configuration

This permission model is consistent with CasaOS guidelines for AppData-only applications.
