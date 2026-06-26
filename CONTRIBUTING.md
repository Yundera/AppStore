# Contributing to the AppStore

This document describes how to contribute an app to the Yundera Compose AppStore.

**IMPORTANT**: Your PR must be *well tested* on your own CasaOS first. This is the mandatory first step for your submission.

## Submission Checklist

Before submitting your PR, ensure your app meets these requirements:

### Tech Checklist
- [ ] Proper file permissions based on volume usage. See [Permission Strategy](#permission-strategy) for details
- [ ] **Pre-install and Post-install commands security**: If using `pre-install-cmd` or `post-install-cmd`, ensure specific version tags (no `:latest`) and proper user permissions (`--user $PUID:$PGID` when writing to user directories)

### Security Checklist
- [ ] An authentication method is enabled and documented - this is **mandatory**. Exceptions must be explained in rationale.md (e.g., public websites).
  - **Recommended**: OIDC via the **AppShield** sidecar (`ghcr.io/yundera/appshield`, formerly `nginx-hash-lock`), which auto-registers with the PCS's `auth-registrar` and protects the app with the built-in Authelia SSO. See [OIDC Authentication](#oidc-authentication-recommended) for the minimal setup, and copy a recently-shipped app (e.g. `Apps/ConvertX`, `Apps/Spliit`, `Apps/BrowserMCP`) as a reference deployment.
  - Acceptable alternatives: Basic Auth, the app's own built-in auth (e.g. Jellyfin, Immich onboarding), or any other login gate that is enabled by default.
  - Example of valid exception:
    - A public website that does not require authentication
    - The app handles authentication configuration on first launch via an onboarding process (e.g. Jellyfin, Immich)
- [ ] No hardcoded credentials in the compose file - use environment variables or secrets
- [ ] Specific version tag (no `:latest`)

### Functionality Checklist
- [ ] Works immediately after installation - no need to check logs or run commands - pre-install scripts create sensible defaults
- [ ] Data is mapped to appropriate `/DATA` subdirectories - if things are mapped outside of /DATA, this should be explained in rationale.md
- [ ] No manual configuration required for basic functionality - should work out of the box
- [ ] Data persistence requirements are met - see [Data Persistence](#data-persistence) section for details
- [ ] CPU field cpu_shares is set appropriately (on all services)
- [ ] fresh installation tested
- [ ] uninstall/reinstall tested - An application should be able to be uninstalled and reinstalled without losing user data or configuration (See the keep user data option when uninstalling)
- [ ] Upgrade from previous version tested - installing the new version on top of existing `/DATA/AppData/[AppName]/` data from a previous version must not corrupt, erase, or downgrade user data or configuration. Only incremental migration is supported (to go from v1.1 to v1.4, the user must pass through v1.2 and v1.3 first).


### Documentation Checklist
- [ ] Clear description of the application
- [ ] Volume and environment variable descriptions
- [ ] Icon and screenshots meet specifications - files and URLs point to this Yundera repository (eg https://cdn.jsdelivr.net/gh/Yundera/AppStore@main/Apps/Duplicati/thumbnail.png)

## Testing and Submit Process

App submission should be done via Pull Request. Fork this repository and prepare the app per guidelines below.
Once the PR is ready, create and assign your PR to anyone from the CasaOS Team or another trusted contributor.

To ensure easy testing, please follow these steps:

1. Start with a regular compose app, which is a directory containing a `docker-compose.yml` file. Test it on your own machine to ensure you can start it successfully. In your instance, you can edit the compose file with a text editor and restart the app to check if the changes work. Use SSH to do `docker compose up -d` if needed.

2. Copy the docker compose to an instance of CasaOS, e.g., `/DATA/AppData/casaos/apps/MyApp/docker-compose.yml`. Add all the required CasaOS-specific fields (x-casaos metadata, etc.) and test from the instance using SSH and the `docker compose up -d` command.

3. When the local setup is stable, push to your forked repo. Create a new directory under `Apps` with your app name (along with logo, screenshot, and description files), e.g., `MyApp`.

4. Test this app listing on your own CasaOS instance:
  - Use the GitHub URL of your forked repo as the AppStore URL. It should look like this:
   ```shell
   https://github.com/user/AppStore/archive/refs/heads/main.zip 
   ```

5. Once it works in your store, create a PR.
 - See the checklist above to ensure your app meets the requirements.
 - Remember to change where the asset links point to (should be the main repository)

6. Once approved, your app will be directly available in the app listing.

## Guidelines

### Rationale (`rationale.md`)

When an app deviates from the default requirements, it must ship a `rationale.md` file **alongside its `docker-compose.yml`** (i.e. `Apps/[AppName]/rationale.md`). Reviewers read this file first when the compose file raises a flag.

**When a `rationale.md` is required:**
- The app runs as `user: 0:0` or exposes volumes outside `/DATA/AppData/[AppName]/` and `/DATA/[user-dir]/`.
- The app ships with authentication disabled, or relies on the app's own first-launch onboarding instead of an enabled default.
- The app uses a root container with mixed access to user directories and AppData (see [Mixed Usage Applications](#permission-strategy)).
- Any other explicit deviation from this document.

**Recommended structure** (see `Apps/Stirling-PDF/rationale.md` for a full worked example):

```markdown
# [AppName] — Rationale

## What deviation / exception is being requested
<Concrete, e.g. "runs as root", "auth disabled", "mounts /DATA/Downloads as rw">

## Why it is necessary
<Technical reason — upstream constraints, runtime requirements, etc.>

## Security mitigations in place
<Resource limits, container isolation, disabled features, read-only mounts, etc.>

## Alternatives considered and rejected
<Each alternative + why it didn't work>

## Data protection
<What protects user data given this exception>
```

Keep it factual and short — reviewers should be able to decide in a minute.

### Data Persistence

Applications must be designed to preserve user data across uninstallation and reinstallation cycles. This ensures users never lose their personal data when updating or reinstalling applications.

**Requirements:**
- **Persistent Volume Mapping**: All user data, configurations, and databases must be stored in volumes mapped to `/DATA/AppData/[AppName]/`
- **Graceful Data Reuse**: Applications must detect and reuse existing data when reinstalled
- **No Data Erasure**: Container startup processes must never erase or overwrite existing user data
- **Configuration Preservation**: Settings, user accounts, and preferences should persist across container lifecycle

**Implementation Guidelines:**
- Map all persistent data to `/DATA/AppData/[AppName]/` subdirectories
- Use initialization scripts that check for existing data before creating defaults
- Ensure database migrations are handled gracefully on version updates
- Test uninstall/reinstall scenarios to verify data persistence

**Example Volume Mapping:**
```yaml
volumes:
  - /DATA/AppData/myapp/config:/app/config
  - /DATA/AppData/myapp/database:/var/lib/database
  - /DATA/AppData/myapp/uploads:/app/uploads
```

This approach ensures that when users uninstall and reinstall applications, they can continue from where they left off without losing any personal data or configurations.

### File Structure

Understanding the directory structure is essential for proper app development and data management. All user data and application configurations are stored under `/DATA`:

**Permission Strategy:**

To be mindful of permission user *must* always be specified in the compose file.
1 - with the user: `user: xx:xx`
and
2 - by setting the `PUID` and `PGID` environment variables in the compose file.

Yundera uses a dual permission model to balance security and usability:
Files owned by `PUID:PGID` (usually `1000:1000` for the 'pcs:pcs' user)

**if no "user" field is specified in the compose file, the container will run as PUID:PGID (different behavior than the docker default so be carful)**
if you need to run as root, you must specify `user: 0:0` in the compose file.


**User-Friendly Directories** 
- `PUID:PGID` ownership required
- `/DATA/Documents/`, `/DATA/Downloads/`, `/DATA/Gallery/`, `/DATA/Media/`
- Users can directly browse, modify, and manage these files
- Content should be human-readable with meaningful filenames
- Applications accessing these directories **must** use `user: $PUID:$PGID`

**AppData Directories** 
Contains the App folder : `/DATA/AppData/[AppName]/` - Application-specific data and configurations

- Root ownership withing the App folder is acceptable but preferably `PUID:PGID` to allow user to change configurations easily
- Contains databases, config files, cache, logs, and internal app data
- Root containers are acceptable when volumes map exclusively to AppData
- Examples: `/DATA/AppData/immich/pgdata`, `/DATA/AppData/immich/model-cache`

The App folder should always be owned by `PUID:PGID` to allow the user to romove the folder if needed.
inside this folder the permission may vary depending on usage.

example`:
```
root@yundera:/DATA/AppData# ls -al
drwxr-xr-x 13 pcs  pcs    4096 Sep  3 14:17 .
drwxrwxrwx  8 pcs  pcs    4096 Sep  3 14:17 ..
drwxr-xr-x  5 pcs  pcs    4096 Sep  4 12:12 casaos
drwxr-xr-x  3 pcs  pcs    4096 Jun 25 10:30 duplicati
drwxr-xr-x  3 pcs  pcs    4096 Aug  3 19:35 filebrowser
drwxr-xr-x  4 pcs  pcs    4096 Jun 25 10:30 jellyfin
```

**Mixed Usage Applications:**
- If an app needs both AppData and user directory access, use `user: $PUID:$PGID`
- Alternative: Use separate containers (one for system tasks, one for user file access)
- Document the approach in rationale.md if using root containers with mixed access

```
/DATA/
├── AppData/                    # Application-specific data and configurations
│   ├── casaos/                # CasaOS system files
│   │   ├── 1/                 # CasaOS configuration
│   │   ├── apps/              # Individual app docker-compose
│   │   │   └── [AppName]/     # App directory (this is where the docker compose is stored - no app data)
│   │   └── db/                # CasaOS database
│   └── [AppName]/             # Per-app data directories
│       ├── config/            # App configuration files
│       ├── data/              # App-specific data
│       └── [other-dirs]/      # Additional app directories
├── Documents/                  # User documents
├── Downloads/                  # Download directory
├── Gallery/                    # Photo and image storage
└── Media/                      # Media files
    ├── Movies/                # Movie collection
    ├── Music/                 # Music collection
    └── TV Shows/              # TV series collection
```

**Key Directory Usage:**

- **`/DATA/AppData/[AppName]/`**: Primary location for app-specific data (config files, databases, logs)
  - Use this pattern in your `docker-compose.yml` volumes
  - Example: `/DATA/AppData/immich/config:/app/config`
  - not intended for direct user access

- **`/DATA/Gallery/`**: Shared photo/image storage
  - Ideal for photo management apps

- **`/DATA/Media/`**: Shared media storage
  - Use for media servers like Plex, Jellyfin, Emby
  - Subdirectories help organize content types

- **`/DATA/Documents/` & `/DATA/Downloads/`**: General file storage
  - Document management and download directories

**Volume Mapping Examples:**

**AppData-only Application (Root container OK):**
```yaml
services:
  database:
    image: postgres:13
    # No user specification needed - root is fine for AppData-only access
    volumes:
      - /DATA/AppData/myapp/pgdata:/var/lib/postgresql/data
      - /DATA/AppData/myapp/config:/app/config
```

**User Directory Application (PUID:PGID required):**
```yaml
services:
  filemanager:
    image: filebrowser/filebrowser
    user: $PUID:$PGID                    # Required for user directory access
    volumes:
      - /DATA/AppData/filebrowser:/app/config
      - /DATA/Documents:/srv/documents
      - /DATA/Downloads:/srv/downloads
```

**Mixed Usage Application:**
```yaml
services:
  mediaserver:
    image: jellyfin/jellyfin
    user: $PUID:$PGID                    # Required due to media access
    volumes:
      - /DATA/AppData/jellyfin:/config   # System config (user can thus modify)
      - /DATA/Media:/media:ro            # User media (read-only)
      - /DATA/Downloads:/downloads       # User downloads
```

This structure ensures:
- Clean separation between apps
- Shared access to common directories
- Easy backup and migration
- Consistent file permissions with PUID/PGID

### CPU Share Guidelines

It is mandatory to set CPU shares for all services in your compose file. This helps ensure fair resource allocation and prevents any single container from monopolizing CPU resources.

CPU shares determine relative CPU priority between containers. Higher values get more CPU time when the system is under load.

**Placement:** `cpu_shares` is a **top-level service field**, not part of `deploy:`. The value is a relative weight, not a percentage.

```yaml
services:
  myapp:
    image: myapp:1.2.3
    cpu_shares: 70          # ← top level of the service
    # deploy.resources is for memory/cpu limits, not cpu_shares
```

#### CPU Share Allocation:
```
**100 - System Critical** (Reserved)
- System services that must never be starved

**90 - Administrative Critical**
- Applications that must always be responsive with no heavy background processes
- Examples: CasaOS, Portainer, admin dashboards, monitoring tools

**80 - User-Facing Interactive**
- Real-time applications requiring immediate user responsiveness
- Examples: Web servers, frontend applications, API backends, reverse proxies

**70 - Interactive with Heavy Tasks**  
- Real-time applications that may have intensive background processes
- Examples: Nextcloud (web + background jobs), WebRTC servers, databases serving interactive apps

**50 - Standard Applications** (Default)
- Regular applications without special performance requirements
- Examples: Most containerized applications, file servers, basic services

**30 - Background Services**
- Non-interactive services that don't require immediate responsiveness  
- Examples: Backup services (Duplicati), log aggregation, scheduled tasks

**20 - Heavy Background Processing**
- Resource-intensive background tasks with no real-time requirements
- Examples: Machine learning services (Immich ML), video transcoding, batch processing

**10 - System Background** (Reserved)
- Reserved for system maintenance tasks
```

#### Resource limits

Optional
Only add if necessary to prevent resource exhaustion but most application don't need it.
   
```yaml
   deploy:
     resources:
       limits:
         memory: 512M
```

3. **Testing**: Consider your server's typical load when choosing values

### Project Structure

```shell
CasaOS-AppStore
├─ category-list.json   # Configuration file for category list
├─ recommend-list.json  # Configuration file for recommended apps list
├─ featured-apps.json   # TBD
├─ Apps                 # App Store files
└─ psd-source           # Icon thumbnail screenshot PSD Templates
```

### An App typically includes the following files

```shell
App-Name
├─ docker-compose.yml   # (Required) A valid Docker Compose file
├─ icon.png             # (Required) App icon
├─ screenshot-1.png     # (Required) At least one screenshot is needed to demonstrate the app runs on CasaOS successfully
├─ screenshot-2.png     # (Optional) More screenshots to demonstrate different functionalities are highly recommended
├─ screenshot-3.png     # (Optional) ...
├─ thumbnail.png        # (Required) Tile image shown in the AppStore listing (see specification at bottom)
└─ rationale.md         # (Conditional) Required when the app needs a documented exception — see "Rationale" below
```

#### An App is a Docker Compose app, or a *compose app*

Each directory under [Apps](Apps) corresponds to a Compose App. The directory should contain at least a `docker-compose.yml` file:

- It should be a valid [Docker Compose file](https://docs.docker.com/compose/compose-file/). Here are some requirements (but not limited to):

    - `name` must contain only lowercase letters, numbers, underscore "`_`" and hyphen "`-`" (in other words, must match `^[a-z0-9][a-z0-9_-]*$`)

- Image tag should be specific, e.g. `:0.1.2`, instead of `:latest`.

  > [What's Wrong With The Docker `:latest` Tag?](https://github.com/IceWhaleTech/CasaOS-AppStore/issues/167)

- The `name` property is used as the *store App ID*, which should be unique across all apps.

  For example, in the [`docker-compose.yml` of Syncthing](Apps/Syncthing/docker-compose.yml#L1), its store App ID is `syncthing`:

    ```yaml
    name: syncthing
    services:
        syncthing:
            image: linuxserver/syncthing:<specific version>
    ...
    ```

- Language codes are case sensitive and should be in all lowercase, e.g. `en_us`, `zh_cn`.

- There are several system-wide variables that can be used in `environment` and `volumes`:

    ```yaml
    environment:
      PGID: $PGID                           # Preset Group ID
      PUID: $PUID                           # Preset User ID
      TZ: $TZ                               # Current system timezone
    ...
    volumes:
      - type: bind
        source: /DATA/AppData/$AppID/config # $AppID = app name, e.g. syncthing
    ```

- **System Variables**: Yundera injects the following variables at container creation. Reference them in `environment:`, `volumes:`, `labels:`, and `pre-install-cmd`:

    ```yaml
    environment:
      # User / system
      PGID: $PGID                           # Preset Group ID
      PUID: $PUID                           # Preset User ID
      TZ: $TZ                               # Current system timezone

      # App identity & networking
      APP_DOMAIN: $APP_DOMAIN               # Domain root for this app (e.g. user.nsl.sh)
      APP_PUBLIC_IP_DASH: $APP_PUBLIC_IP_DASH  # Public IPv4 with dashes, for nip.io / sslip.io
      APP_DEFAULT_PASSWORD: $APP_DEFAULT_PASSWORD  # Secure default password generated by Yundera
      APP_EMAIL: $APP_EMAIL                 # Admin email (admin@DOMAIN)
    ```

    Typical usage — publishing the app's own URL back to itself (e.g. for OAuth callbacks, email links, CORS):

    ```yaml
    environment:
      BASE_URL: https://myapp-${APP_DOMAIN}
    ```

- CasaOS specific metadata, also called *store info*, are stored under the [extension](https://docs.docker.com/compose/compose-file/#extension) property `x-casaos`.

  #### Compose App Level Configuration

  For the same example, at the bottom of the [`docker-compose.yml` of Syncthing](Apps/Syncthing/docker-compose.yml):

    ```yaml
    x-casaos:
        architectures:                  # a list of architectures that the app supports
            - amd64
            - arm
            - arm64
        main: syncthing                 # the name of the main service under `services`
        author: CasaOS Team
        category: Backup
        description:                    # multiple locales are supported
            en_us: Syncthing is a continuous file synchronization program. It synchronizes files between two or more computers in real time, safely protected from prying eyes. Your data is your data alone and you deserve to choose where it is stored, whether it is shared with some third party, and how it's transmitted over the internet.
        developer: Syncthing
        icon: https://cdn.jsdelivr.net/gh/IceWhaleTech/CasaOS-AppStore@main/Apps/Syncthing/icon.png
        tagline:                        # multiple locales are supported
            en_us: Free, secure, and distributed file synchronisation tool.
        thumbnail: https://cdn.jsdelivr.net/gh/IceWhaleTech/CasaOS-AppStore@main/Apps/Jellyfin/thumbnail.jpg
        title:                          # multiple locales are supported
            en_us: Syncthing
        tips:
            before_install:
                en_us: |
                    (some notes for user to read prior to installation, such as preset `username` and `password` - markdown is supported!)
        index: /                        # the index page for web UI, e.g. index.html
        port_map: "8384"                # the port for web UI
    ```

#### use tips before_install to provide a default account if needed
```yml
x-casaos:
  tips:
    before_install:
      en_us: |
        Default Account
        | Username   | Password                |
        | --------   | ----------------------- |
        | `admin`    | `$APP_DEFAULT_PASSWORD` |
```

### Features

CasaOS supports additional configuration options for enhanced app management:

#### Pre-Installation Commands

You can specify commands to run before container startup using `pre-install-cmd`. It executes on the host before any of the app's services start. Two styles are acceptable — pick whichever is simpler for your needs:

**Style A — plain shell on the host.** Good for creating directories, downloading static assets, or setting permissions with tools that already exist on the host.

```yaml
x-casaos:
  pre-install-cmd: |
    mkdir -p /DATA/AppData/$AppID/config
    # Idempotency: guard work behind a sentinel file so reruns are no-ops
    if [ ! -f /DATA/AppData/$AppID/.initialized ]; then
      wget -O /DATA/AppData/$AppID/config/init.sql \
        https://raw.githubusercontent.com/Yundera/AppStore/main/Apps/MyApp/pre-install/init.sql
      touch /DATA/AppData/$AppID/.initialized
    fi
```

Static assets the script needs can live under `Apps/[AppName]/pre-install/` in this repo and be fetched via jsDelivr or `raw.githubusercontent.com` (see `Apps/Guacamole/pre-install/` for a real example).

**Style B — one-shot `docker run` containers.** Good when the setup needs a binary that isn't on the host (for example, the app's own CLI to initialise its database).

```yaml
x-casaos:
  pre-install-cmd: |
    docker run --rm -v /DATA/AppData/filebrowser/db/:/db filebrowser/filebrowser:v2.32.0 config init --database /db/database.db &&
    docker run --rm -v /DATA/AppData/filebrowser/:/data ubuntu:22.04 chown -R $PUID:$PGID /data &&
    docker run --rm -v /DATA/AppData/filebrowser/db/:/db filebrowser/filebrowser:v2.32.0 users add admin $APP_DEFAULT_PASSWORD --perm.admin --database /db/database.db
```

**Requirements (apply to both styles):**
- [ ] **Specific version tags**: Never use `:latest` — always pin exact versions (e.g. `alpine:3.19`, `ubuntu:22.04`).
- [ ] **Idempotent**: Safe to rerun. Guard destructive / one-shot work behind a sentinel file (`touch /DATA/AppData/$AppID/.initialized`) or an existence check.
- [ ] **Non-interactive**: Must not prompt.
- [ ] **No hardcoded credentials**: Use `$APP_DEFAULT_PASSWORD` and friends.
- [ ] **User permissions when touching user directories**: Use `--user $PUID:$PGID` (Style B) or `chown -R $PUID:$PGID` (either style) whenever files will live under `/DATA/Documents`, `/DATA/Downloads`, `/DATA/Media`, or `/DATA/Gallery`.

**Common use cases:**
- Create default configuration files
- Set up initial data structures
- Generate certificates or keys
- Prepare the environment with sensible defaults

#### Caddy Integration (Web UI Access)

The Yundera AppStore uses Caddy reverse proxy with Docker labels for automatic HTTPS routing. Apps are accessible via three methods:
- **Gateway-routed domain**: `https://appname-username.nsl.sh` (custom CA)
- **Direct access via nip.io**: `https://appname-192-168-1-1.nip.io` (custom CA)
- **Direct access via sslip.io**: `https://appname-192-168-1-1.sslip.io` (Let's Encrypt)

**How It Works:**
- Caddy watches Docker containers for specific labels
- Labels define the subdomain prefix and backend port
- Three access methods provide flexibility for different network scenarios
- nsl.sh provides free subdomains for all Yundera users

**Label Format (Required for all Web UI apps):**
```yaml
labels:
  # 1. Gateway-routed domain - Custom CA
  caddy_0: appname-${APP_DOMAIN}
  caddy_0.import: gateway_tls
  caddy_0.reverse_proxy: "{{upstreams 80}}"

  # 2. Direct access via nip.io - Custom CA
  caddy_1: appname-\${APP_PUBLIC_IP_DASH}.nip.io
  caddy_1.import: gateway_tls
  caddy_1.reverse_proxy: "{{upstreams 80}}"

  # 3. Direct access via sslip.io - Let's Encrypt (public cert)
  caddy_2: appname-\${APP_PUBLIC_IP_DASH}.sslip.io
  caddy_2.reverse_proxy: "{{upstreams 80}}"
```

**Notes:**
- `caddy_2` does NOT have `import: gateway_tls` - uses Let's Encrypt
- Replace `80` with your app's actual web UI port
- Add labels only to the main web UI service
- Ensure the `pcs` network is configured

**Compose File Requirements:**
- Use `expose` to expose the web UI port (required for Caddy discovery)
- Add Caddy labels to the main web UI service only
- Connect the main service to the `pcs` network
- Use `${APP_DOMAIN}` and `\${APP_PUBLIC_IP_DASH}` variables
- Set `container_name` explicitly on the main service. Caddy resolves each label's upstream via container DNS on the `pcs` network, so the container must have a stable, predictable name. Constraints:
  - lowercase alphanumerics and `-` only (no underscores, dots, or other special characters)
  - must **not** start with a digit
  - should match the top-level `name:` and service name for consistency

**Example - Complete Caddy Configuration:**
```yaml
services:
  immich:
    image: altran1502/immich-server:v1.135.3
    expose:
      - 80
    labels:
      caddy_0: immich-${APP_DOMAIN}
      caddy_0.import: gateway_tls
      caddy_0.reverse_proxy: "{{upstreams 80}}"
      caddy_1: immich-\${APP_PUBLIC_IP_DASH}.nip.io
      caddy_1.import: gateway_tls
      caddy_1.reverse_proxy: "{{upstreams 80}}"
      caddy_2: immich-\${APP_PUBLIC_IP_DASH}.sslip.io
      caddy_2.reverse_proxy: "{{upstreams 80}}"
    networks:
      - pcs
    environment:
      IMMICH_PORT: 80

networks:
  pcs:
    name: pcs
    external: true

x-casaos:
  main: immich
  webui_port: 80
```

**Result URLs:**
- `https://immich-username.nsl.sh/` (via gateway)
- `https://immich-192-168-1-1.nip.io/` (direct, custom CA)
- `https://immich-192-168-1-1.sslip.io/` (direct, Let's Encrypt)

**Example - Non-Port-80 Service:**
```yaml
services:
  duplicati:
    image: linuxserver/duplicati:latest
    expose:
      - 8200
    labels:
      caddy_0: duplicati-${APP_DOMAIN}
      caddy_0.import: gateway_tls
      caddy_0.reverse_proxy: "{{upstreams 8200}}"
      caddy_1: duplicati-\${APP_PUBLIC_IP_DASH}.nip.io
      caddy_1.import: gateway_tls
      caddy_1.reverse_proxy: "{{upstreams 8200}}"
      caddy_2: duplicati-\${APP_PUBLIC_IP_DASH}.sslip.io
      caddy_2.reverse_proxy: "{{upstreams 8200}}"
    networks:
      - pcs

networks:
  pcs:
    name: pcs
    external: true

x-casaos:
  main: duplicati
  webui_port: 8200
```

**Port Selection Guidelines:**
- Configure applications to use port 80 when possible
- Any port works with Caddy - just match the `expose` and label port values
- The URL remains clean regardless of the backend port

Caddy handles:
- Automatic HTTPS certificate management
- Subdomain routing to the correct container
- Load balancing and health checks
- WebSocket proxying

**Web UI Requirements (all must be configured together):**
- The main service must `expose` the web UI port
- Add all three Caddy label blocks (caddy_0, caddy_1, caddy_2)
- Connect the service to the `pcs` network
- The `webui_port` field must match the exposed port number
- The `main` field must reference the service with Caddy labels

**Important Notes:**
- Add Caddy labels only to the main web UI service (not to database or backend services)
- The app name in the Caddy labels should be simple without spaces or special characters
- Use `${APP_DOMAIN}` and `\${APP_PUBLIC_IP_DASH}` for portability
- Always include the `pcs` network definition with `external: true`

**Example Multi-Service Configuration:**

```yaml
services:
  database:
    image: postgres:13
    # Database service - no Caddy labels needed

  webui-service:
    image: myapp:latest
    expose:
      - 8080                        # Must expose the web UI port
    labels:
      - "caddy=myapp-${APP_DOMAIN}"
      - "caddy.reverse_proxy={{upstreams 8080}}"
    ports:
      - "9000:9000"                 # Direct port binding for API or other services
    depends_on:
      - database

x-casaos:
    main: webui-service             # References the service with Caddy labels
    webui_port: 8080               # Must match the exposed port
```

#### OIDC Authentication (Recommended)

The recommended way to satisfy the authentication requirement is to front your app with the **AppShield** sidecar (`ghcr.io/yundera/appshield`, formerly `nginx-hash-lock`), which plugs into the PCS's built-in Authelia SSO. The sidecar self-registers as an OIDC client with the PCS's `auth-registrar` on first login — there are **no client IDs, no secrets, and no issuer URL to configure**.

Reference deployments: copy a recently-shipped SSO app such as `Apps/ConvertX`, `Apps/Spliit`, or `Apps/BrowserMCP` (an MCP server). The live store is the source of truth — if this guide and a shipped app disagree, the app wins.

**Pattern:** put the AppShield container in front of your backend, point Caddy at AppShield instead of the backend, and keep the backend reachable only on the internal `pcs` network.

```yaml
name: myapp
services:
  myapp:                                    # AppShield sidecar (public-facing)
    image: ghcr.io/yundera/appshield:2.0.3
    container_name: myapp                    # must equal top-level name: (load-bearing — see checklist)
    restart: unless-stopped
    user: "root"
    expose:
      - 80
    labels:
      caddy_0: myapp-${APP_DOMAIN}
      caddy_0.import: gateway_tls
      caddy_0.reverse_proxy: "{{upstreams 80}}"
      caddy_1: myapp-\${APP_PUBLIC_IP_DASH}.nip.io
      caddy_1.import: gateway_tls
      caddy_1.reverse_proxy: "{{upstreams 80}}"
      caddy_2: myapp-\${APP_PUBLIC_IP_DASH}.sslip.io
      caddy_2.reverse_proxy: "{{upstreams 80}}"
    environment:
      AUTH_HASH: $AUTH_HASH                                 # token; pair with x-casaos.index: /?hash=$AUTH_HASH
      BACKEND_HOST: "myapp-backend"                         # internal DNS name of the protected container
      BACKEND_PORT: "80"                                    # port the backend listens on
      LISTEN_PORT: "80"                                     # port AppShield listens on (matches `expose` + Caddy)
      OIDC_REGISTRAR_URL: "http://auth-registrar:9092"      # presence of this enables OIDC mode
      REDIRECT_HOST_SUFFIXES: "${APP_DOMAIN},\${APP_PUBLIC_IP_DASH}.nip.io,\${APP_PUBLIC_IP_DASH}.sslip.io"
      CREDENTIAL_VALIDATE_URL: "http://casaos-oidc-bridge:8090/validate"
      # Optional:
      # USER: "ADMIN"                                       # extra basic-auth gate in front of the UI
      # PASSWORD: $APP_DEFAULT_PASSWORD
      # ALLOWED_PATHS: "mcp"                                # paths reachable with the hash token only (MCP servers)
    depends_on:
      - myapp-backend
    cpu_shares: 80
    networks:
      - pcs

  myapp-backend:
    image: myapp:1.2.3
    container_name: myapp-backend
    # No Caddy labels — only the AppShield sidecar is publicly reachable
    expose:
      - 80
    cpu_shares: 50
    networks:
      - pcs

networks:
  pcs:
    name: pcs
    external: true

x-casaos:
  main: myapp                       # primary service (the sidecar; some apps point it at the backend)
  index: /?hash=$AUTH_HASH          # launch URL carries the hash token so the user lands authenticated
  webui_port: 80                    # optional; keep at 80 if set
```

**AppShield environment reference (OIDC mode):**

| Variable | Required | Purpose |
| --- | --- | --- |
| `AUTH_HASH` | yes | Injected token; pair with `x-casaos.index: /?hash=$AUTH_HASH`. |
| `BACKEND_HOST` / `BACKEND_PORT` | yes | Internal DNS name + port of the protected container. |
| `LISTEN_PORT` | yes | Port AppShield listens on (matches `expose` + Caddy `{{upstreams}}`). |
| `OIDC_REGISTRAR_URL` | yes | `http://auth-registrar:9092` — enables OIDC; self-registers (no client id/secret). |
| `REDIRECT_HOST_SUFFIXES` | yes | `${APP_DOMAIN},${APP_PUBLIC_IP_DASH}.nip.io,${APP_PUBLIC_IP_DASH}.sslip.io` — valid OIDC redirect hosts. |
| `CREDENTIAL_VALIDATE_URL` | yes | `http://casaos-oidc-bridge:8090/validate` — validates the session against the PCS bridge. |
| `USER` / `PASSWORD` | optional | Extra basic-auth gate in front of the UI (e.g. `ADMIN` / `$APP_DEFAULT_PASSWORD`). |
| `ALLOWED_PATHS` | optional | Paths reachable with just the hash token, bypassing basic-auth — e.g. `mcp` for MCP servers. |

**Checklist for OIDC apps:**
- [ ] Caddy labels are attached **only to the AppShield sidecar**, never to the backend — otherwise the backend is exposed unauthenticated.
- [ ] The sidecar carries the full env set: `AUTH_HASH`, `BACKEND_HOST`, `BACKEND_PORT`, `LISTEN_PORT`, `OIDC_REGISTRAR_URL`, `REDIRECT_HOST_SUFFIXES`, `CREDENTIAL_VALIDATE_URL`.
- [ ] `x-casaos.index` is set to `/?hash=$AUTH_HASH` when using `AUTH_HASH`.
- [ ] `x-casaos.main` points at the primary service.
- [ ] Backend service has no `ports:` and no public Caddy labels; it is reachable only via the `pcs` network.
- [ ] The sidecar's `container_name` equals the top-level `name:` (lowercase alnum + `-`, not starting with a digit). `auth-registrar` derives the OIDC `client_id` from the container name via PTR lookup on the `pcs` network, so the `container_name` is load-bearing — it must be stable across reinstalls. The compose **service name itself may differ** (shipped apps use `myapp`, `myapp-proxy`, `nginxhashlock`, etc.).
- [ ] Do not claim `auth-${APP_DOMAIN}` in any Caddy label — it collides with the PCS's Authelia and causes intermittent `invalid_client` errors.
- [ ] Pin AppShield to a specific version tag (currently `ghcr.io/yundera/appshield:2.0.3`) — never `:latest` / `:main`.

**Requirements on the host PCS:** the `authelia`, `auth-registrar`, and `casaos-oidc-bridge` containers must be running on the `pcs` network (provisioned automatically by the current `template-root`). If they are missing, the app fails at first login with `ENOTFOUND auth-registrar` in the sidecar logs.

#### System Variables

Yundera injects the following variables into every app at container creation. Reference them in `environment:`, `volumes:`, `labels:`, and `pre-install-cmd`.

**Available variables:**
- `$APP_DOMAIN`: Domain root for this app (e.g. `user.nsl.sh`). Compose a full URL as `https://<prefix>-${APP_DOMAIN}`.
- `$APP_PUBLIC_IP_DASH`: The server's public IPv4 with dots converted to dashes — used for `nip.io` / `sslip.io` Caddy labels.
- `$APP_DEFAULT_PASSWORD`: A secure default password generated by Yundera. Use it for first-boot admin credentials instead of hard-coding.
- `$APP_EMAIL`: Admin email in the format `admin@DOMAIN`.
- `$AppID`: The application name (equal to the compose top-level `name:`). Use in volume paths: `/DATA/AppData/$AppID/…`.
- `$PUID` / `$PGID`: User / group IDs for proper file permissions (typically `1000:1000`).
- `$TZ`: System timezone.

**Example usage:**
```yaml
environment:
  - BASE_URL=https://myapp-${APP_DOMAIN}
  - PUBLIC_URL=https://myapp-${APP_PUBLIC_IP_DASH}.sslip.io
  - ADMIN_PASSWORD=$APP_DEFAULT_PASSWORD
  - ADMIN_EMAIL=$APP_EMAIL
  - PUID=$PUID
  - PGID=$PGID
  - TZ=$TZ
volumes:
  - /DATA/AppData/$AppID/data:/app/data
```

#### Environment Variables

CasaOS provides additional functionality for environment variable management:

- **User-defined Variables**: Your application can read environment variables set by users, such as `OPENAI_API_KEY`. These are stored in `/etc/casaos/env` and can be set once and used across multiple applications.

- **Variable Updates**: Environment variables can be changed via API. After changes, all applications will restart to inject the new environment variables.

**Note**: Changing the configuration doesn't immediately change environment variables in running containers. Use the CLI to set environment variables for immediate effect.

## Requirements for Featured Apps

We occasionally select certain apps as featured apps to display at the AppStore front. Featured apps have higher standards than regular apps:

- **Icon**: Transparent background PNG image, 192x192 pixels
- **Thumbnail**: 784x442 pixels with rounded corner mask, preferably PNG with transparent background
- **Screenshots**: 1280x720 pixels, PNG or JPG format, keep file size as small as possible

Please use the prepared [PSD template files](psd-source) to quickly create these images.

**Language Requirement:**
- **Mandatory:** English (`en_us`) — required for *title*, *tagline*, and *description*.
- **Recommended:** French (`fr_fr`), Korean (`ko_kr`), Chinese (`zh_cn`), and Spanish (`es_es`) — provide *tagline* and *description* in these whenever possible. These are the five languages the store fully supports and translations help reach the full user base.

## Feedback

If you have any feedback or suggestions about this contributing process, please let us know via Discord or Issues. Thanks!
