# Stirling-PDF Security Exception Rationale

## Root User Requirement

### Why Root Access is Needed

Stirling-PDF requires root user (`user: "0:0"`) for the following technical reasons:

1. **Temporary File Processing Architecture**
   - PDF processing operations require extensive temporary file creation
   - The application's Java runtime needs unrestricted access to `/tmp` directory
   - Multiple PDF processing libraries (PDFBox, iText, etc.) expect full write permissions

2. **Multi-format Conversion Tools**
   - Integrates LibreOffice, ImageMagick, Tesseract OCR, and other tools
   - Each tool has different permission requirements and temp file patterns
   - Root access ensures compatibility across all integrated conversion tools

3. **Java Runtime Requirements**
   - Java applications often expect to manage their own temp directories
   - JVM garbage collection and optimization require flexible file system access
   - Running as non-root can cause Java-specific permission issues

### Security Mitigations

While running as root, the following security measures are in place:

1. **No Authentication by Design**
   - `SECURITY_ENABLELOGIN=false` is intentional for this use case
   - This is a valid exception because:
     - All PDF processing happens locally on the server
     - Files never leave the user's infrastructure
     - NSL router provides network-level access control
     - Designed as a personal tool, not multi-tenant service

2. **Isolated Processing**
   - All data confined to `/DATA/AppData/$AppID/`
   - User files accessed read-only from `/DATA/Downloads`
   - No system-critical directories are accessed

3. **Reduced Feature Set**
   - `DISABLE_ADDITIONAL_FEATURES=true` minimizes attack surface
   - `INSTALL_BOOK_AND_ADVANCED_HTML_OPS=false` reduces complexity
   - Only core PDF operations are enabled

4. **Container Isolation**
   - Application runs in isolated Docker container
   - No access to host system beyond mounted volumes
   - Network access controlled by NSL router

5. **Resource Limits**
   - Memory limited to 2GB
   - CPU limited to 1.0 cores
   - Prevents resource exhaustion attacks

### Authentication Exception Justification

Authentication is disabled because:

1. **Personal Use Tool** - Designed for individual users, not shared environments
2. **Local Processing** - All files processed locally, no data transmission
3. **NSL Router Protection** - Access already controlled at network level
4. **Simplified UX** - Removes friction for legitimate personal use
5. **Public Tool Nature** - Similar to having a local PDF editor installed

This aligns with the CONTRIBUTING.md exception: "public websites that do not require authentication" or tools where "app handles authentication configuration on first launch." In this case, no authentication is the intended design.

### Alternative Approaches Considered

1. **Running as PUID:PGID** - Rejected due to Java runtime and multi-tool permission conflicts
2. **Pre-configured permissions** - Insufficient for dynamic temp file creation
3. **Separate tool containers** - Not feasible as processing requires integrated pipeline

### Data Protection

Even without authentication:
- Files auto-deleted after processing
- No persistent storage of uploaded PDFs
- All processing in ephemeral temp directories
- User controls when files are uploaded

### Conclusion

Root access and disabled authentication are both necessary design choices for Stirling-PDF:
- Root enables proper function of Java runtime and integrated PDF tools
- No authentication is appropriate for a personal, locally-processing tool
- Security is maintained through container isolation, resource limits, and NSL router access control
- Data privacy is preserved through local processing and AppData isolation