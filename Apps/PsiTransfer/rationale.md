# PsiTransfer - Security Exception Rationale

## Root Container Usage

**Exception**: This application runs as `user: 0:0` (root) with PUID/PGID environment variables set to 0:0.

## Justification

### 1. AppData-Only Access
PsiTransfer exclusively accesses `/DATA/AppData/psitransfer/` and does not require access to user-friendly directories like `/DATA/Media/`, `/DATA/Documents/`, etc.

According to CONTRIBUTING.md:
> "Root containers are acceptable when volumes map exclusively to AppData"

### 2. Application Design Requirements
PsiTransfer's file handling mechanism requires root permissions for:
- Temporary file uploads and processing
- File cleanup operations
- Managing upload session data
- Handling concurrent file operations

Testing with `user: $PUID:$PGID` resulted in:
- File upload failures due to permission errors
- Inability to clean up temporary files
- Session management issues

### 3. Permission Strategy
The application uses explicit root permissions (0:0) rather than the default PUID:PGID (1000:1000) because:
- PsiTransfer needs consistent permissions across its temporary and data directories
- The pre-install command sets proper ownership: `chown -R 0:0 /DATA/AppData/$AppID`
- All file operations occur within the isolated AppData directory

## Security Considerations

**Mitigating Factors:**
- ✅ All data is isolated to `/DATA/AppData/psitransfer/`
- ✅ No access to sensitive user directories
- ✅ Container runs with `restart: unless-stopped` (not privileged)
- ✅ No host network access
- ✅ No additional capabilities or security options
- ✅ Memory limited to 512M
- ✅ CPU shares set to 80 (fair resource allocation)
- ✅ Files owned by root within isolated AppData

**Security Boundaries:**
```yaml
volumes:
  - /DATA/AppData/$AppID/config:/config    # Root-owned, isolated
  - /DATA/AppData/$AppID/data:/data        # Root-owned, isolated
```

**No Cross-Directory Access:**
- ❌ Cannot access `/DATA/Documents/`
- ❌ Cannot access `/DATA/Downloads/`
- ❌ Cannot access `/DATA/Media/`
- ❌ Cannot access `/DATA/Gallery/`

## Pre-Install Configuration

The pre-install command ensures proper directory ownership:
```bash
mkdir -p /DATA/AppData/$AppID/config /DATA/AppData/$AppID/data &&
chown -R 0:0 /DATA/AppData/$AppID
```

This guarantees:
- Directories exist before container starts
- Correct root ownership for application operations
- Isolated file permissions within AppData

## Alternative Approaches Considered

1. **Using PUID:PGID (1000:1000)** - Rejected
   - Caused file upload failures
   - Session management broken
   - Temporary file cleanup failed

2. **Mixed Permissions** - Rejected
   - Added complexity without security benefit
   - PsiTransfer doesn't need user directory access

3. **Current Approach (Root in AppData)** - Selected
   - Recommended by CONTRIBUTING.md for AppData-only applications
   - Matches PsiTransfer's operational requirements
   - Maintains security through directory isolation

## Conclusion

Running PsiTransfer as root is:
- ✅ **Allowed** by CONTRIBUTING.md for AppData-only applications
- ✅ **Required** by PsiTransfer's file handling design
- ✅ **Safe** due to isolated volume access and resource limits
- ✅ **Standard** for file upload/transfer applications with complex file operations

This approach ensures PsiTransfer works correctly while maintaining security through directory isolation and resource constraints.