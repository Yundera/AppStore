# Security Rationale for Plausible Analytics

## Root User Execution (user: 0:0)

All three services in this application run as root (`user: 0:0`) for the following reasons:

### AppData-Only Access Pattern

**Access Scope:**
- All services exclusively access `/DATA/AppData/plausible/` subdirectories
- No access to user directories:
  - `/DATA/Documents/`
  - `/DATA/Downloads/`
  - `/DATA/Gallery/`
  - `/DATA/Media/`

**Volume Mappings:**
```yaml
plausible-db:
  volumes:
    - /DATA/AppData/plausible/db:/var/lib/postgresql/data

plausible-events-db:
  volumes:
    - /DATA/AppData/plausible/event-data:/var/lib/clickhouse
    - /DATA/AppData/plausible/event-logs:/var/log/clickhouse-server

plausible:
  volumes:
    - /DATA/AppData/plausible/secrets:/secrets
```

All data is confined to the application's AppData directory, with no access to shared user data.

---

### Database Container Requirements

**PostgreSQL (postgres:16-alpine):**
- Official PostgreSQL image uses internal `postgres` user (UID 70)
- Attempting to override with `PUID:PGID` causes permission conflicts
- Database initialization fails when UID doesn't match internal expectations
- Root execution allows PostgreSQL to manage its own internal user properly

**ClickHouse (clickhouse/clickhouse-server:24.12-alpine):**
- Official ClickHouse image uses internal `clickhouse` user (UID 101)
- Similar to PostgreSQL, internal user management conflicts with PUID:PGID override
- Root execution required for proper ulimit configuration (`nofile: 262144`)
- Database initialization and data directory management require elevated privileges

**Testing Results:**
- Attempted `user: $PUID:$PGID` on PostgreSQL → Database initialization failed
- Attempted `user: $PUID:$PGID` on ClickHouse → Permission denied on ulimits and data directory
- Root execution → Both databases initialize and operate correctly

---

### Main Application (Plausible)

**Why root execution:**
1. **Secret Generation**: Startup command generates cryptographic secrets if they don't exist
   - Creates files in `/secrets` directory
   - Requires write permissions on mounted volume
   - Root ensures consistent permissions across container restarts

2. **Database Management**: Runs `db createdb` and `db migrate` commands
   - Requires database connection and schema modification privileges
   - Official Plausible entrypoint expects root execution context

3. **Consistency**: All three services run as root for uniform behavior
   - Simplifies debugging and log analysis
   - No mixed permission scenarios

**Alternative Considered:**
- Using `user: $PUID:$PGID` for main application only
- **Rejected because**: Requires complex permission management for secret files, inconsistent with database containers, adds unnecessary complexity

---

### Security Measures

Even with root execution, security is maintained through:

1. **Network Isolation:**
   - Dedicated bridge network (`plausible-network`)
   - No direct external access (NSL Router provides HTTPS termination)
   - Database services not exposed to host network

2. **Volume Isolation:**
   - All data confined to `/DATA/AppData/plausible/`
   - No bind mounts to system directories
   - No access to sensitive host paths

3. **Resource Limits:**
   - Memory reservations prevent resource exhaustion
   - CPU shares ensure fair scheduling
   - Healthchecks detect and restart failed services

4. **Container Isolation:**
   - Each service runs in separate container
   - No privileged flags or capability additions
   - Standard Docker security namespace isolation

5. **Application-Level Security:**
   - Registration set to "invite_only" by default
   - First user becomes admin automatically
   - No default credentials (secrets auto-generated)

---

### Permission Management

**Host Filesystem:**
```bash
/DATA/AppData/plausible/
├── db/                    # PostgreSQL data (owned by postgres:postgres inside container)
├── event-data/            # ClickHouse data (owned by clickhouse:clickhouse inside container)
├── event-logs/            # ClickHouse logs (owned by clickhouse:clickhouse inside container)
└── secrets/               # Cryptographic keys (owned by root:root inside container)
```

**On Host:**
- AppData directory owned by `PUID:PGID` (typically 1000:1000)
- User can remove entire application directory
- Backup tools can access all data

**Inside Containers:**
- Each service manages its own internal permissions
- Root execution allows proper internal user management
- No permission conflicts between services

---

### Comparison with Alternative Approaches

**If using PUID:PGID for all services:**
- ❌ PostgreSQL fails to initialize (UID mismatch)
- ❌ ClickHouse fails to set ulimits (requires root)
- ❌ Complex volume permission management required
- ❌ Inconsistent behavior across different PUID values
- ✅ Slightly better host filesystem integration

**Current approach (root for all):**
- ✅ All services initialize correctly
- ✅ Simple and consistent permission model
- ✅ Follows official image recommendations
- ✅ No permission conflicts
- ⚠️ Requires rationale documentation (this file)

---

### Conclusion

Root execution for all three services is the most appropriate choice because:

1. **AppData-only access** ensures no security risk to user files
2. **Official database images** require specific internal user management
3. **Network isolation** prevents external attack surface
4. **Simpler debugging** with consistent execution context
5. **Reliable operation** without permission conflicts

This configuration follows the Yundera AppStore guideline:
> "Root containers are acceptable when volumes map exclusively to AppData"

The security model relies on **container isolation** and **volume scoping** rather than user namespace isolation, which is appropriate for an AppData-only application with database dependencies.