# PsiTransfer - Security Exception Rationale

## Root User Requirement

**Exception**: This application runs as `user: 0:0` (root)

**Justification**: 
- PsiTransfer requires root permissions for file upload operations
- The application's internal file handling mechanism fails with PUID:PGID permissions
- Tested with `user: $PUID:$PGID` but file uploads were blocked due to permission errors
- All volumes map exclusively to AppData (`/DATA/AppData/psitransfer/`), not user directories
- This follows the permission strategy: "Root containers are acceptable when volumes map exclusively to AppData"

**Security Mitigation**:
- No access to user directories (Documents, Downloads, Media, Gallery)
- Isolated to its own AppData directory
- No network host mode or privileged flags
- Resource limits enforced (512M memory, 0.5 CPU)