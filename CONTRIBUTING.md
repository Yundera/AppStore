# Contributing to the AppStore

This document describes how to contribute an app to CasaOS AppStore.

**IMPORTANT**: Your PR must be *well tested* on your own CasaOS first. This is the mandatory first step for your submission.

## Submission Checklist

Before submitting your PR, ensure your app meets these requirements:

### Security Checklist
- [ ] Default authentication (Basic Auth, OAuth, etc.) is enabled and documented - exceptions must be explained in rationale.md (e.g., public websites)
- [ ] No hardcoded credentials in the compose file - use environment variables or secrets
- [ ] No root access required - use "user:PUID:PGID" for file permissions or explain in rationale.md if root is necessary. Root level service is also ok if no volumes are mounted or only in readonly mode.
- [ ] Uses PUID/PGID for proper file permissions or Docker user functionality by default - root or special capability access applications must be explained in rationale.md
- [ ] Specific version tag (no `:latest`)
- [ ] Resource limits are mandatory and set appropriately (on all services in case of multiple services) - exceptions must be explained in rationale.md
- [ ] Migration path from previous versions is tested - only incremental migration is supported (if a user wants to go from v1.1 to v1.4, they must execute v1.2 and v1.3 first)

### Functionality Checklist
- [ ] Works immediately after installation - no need to check logs or run commands - pre-install scripts create sensible defaults
- [ ] Data is mapped to appropriate `/DATA` subdirectories - if things are mapped outside of /DATA, this should be explained in rationale.md
- [ ] No manual configuration required for basic functionality - should work out of the box

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

### File Structure

Understanding the directory structure is essential for proper app development and data management. All user data and application configurations are stored under `/DATA`:

The files under `/DATA` are owned by the user and group IDs specified by `PUID` and `PGID` (usually, `1000:1000` for the 'pcs:pcs' user),
which are set during the CasaOS installation. 
This ensures that all applications running under CasaOS have the correct 
permissions to read and write to these directories. The applications must respect these IDs to avoid permission issues.
Some exceptions may apply, such as when a config file needs to be protected from user access, but these should be documented in the app's rationale file.

The files in Documents, Downloads, Gallery, and Media directories should be human-readable and user-friendly, no config files, no strange hash name, if unsure just store the data in the app data.
eg Immich stores its data in `/DATA/AppData/immich/data` and `/DATA/AppData/immich/config`, not in `/DATA/Gallery/immich` because the way Immich works is that it manages its own data in a specific way.

```
/DATA/
├── AppData/                    # Application-specific data and configurations
│   ├── casaos/                # CasaOS system files
│   │   ├── 1/                 # System configuration
│   │   ├── apps/              # Individual app instances
│   │   │   └── immich/        # Example: Immich app directory
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

- **`/DATA/AppData/[AppName]/`**: Primary location for app-specific data
  - Use this pattern in your `docker-compose.yml` volumes
  - Example: `/DATA/AppData/immich/config:/app/config`

- **`/DATA/Gallery/`**: Shared photo/image storage
  - Ideal for photo management apps like Immich, PhotoPrism
  - Example: `/DATA/Gallery/immich:/usr/src/app/upload`

- **`/DATA/Media/`**: Shared media storage
  - Use for media servers like Plex, Jellyfin, Emby
  - Subdirectories help organize content types

- **`/DATA/Documents/` & `/DATA/Downloads/`**: General file storage
  - Document management and download directories

**Volume Mapping Best Practices:**

```yaml
services:
  myapp:
    volumes:
      # App configuration and data
      - /DATA/AppData/myapp/config:/app/config
      - /DATA/AppData/myapp/data:/app/data
      
      # Shared media access (if needed)
      - /DATA/Gallery:/photos:ro          # Read-only photo access
      - /DATA/Media:/media:ro             # Read-only media access
      - /DATA/Downloads:/downloads        # Download directory
      
      # System integration
      - /etc/localtime:/etc/localtime:ro  # Timezone sync
```

**AppData Structure Example (Immich):**
```
/DATA/AppData/immich/
├── model-cache/          # ML model cache
├── pgdata/              # PostgreSQL database files
│   ├── base/            # Database tables
│   ├── pg_wal/          # Write-ahead logs
│   └── [other-pg-dirs]/ # Other PostgreSQL directories
└── redis/               # Redis data files
```

This structure ensures:
- Clean separation between apps
- Shared access to common directories
- Easy backup and migration
- Consistent file permissions with PUID/PGID

### Project Structure

```shell
CasaOS-AppStore
├─ category-list.json   # Configuration file for category list
├─ recommend-list.json  # Configuration file for recommended apps list
├─ featured-apps.json   # TBD
├─ Apps                 # App Store files
└─ psd-source           # Icon thumbnail screenshot PSD Templates
```

### A CasaOS App typically includes the following files

```shell
App-Name
├─ docker-compose.yml   # (Required) A valid Docker Compose file
├─ icon.png             # (Required) App icon
├─ screenshot-1.png     # (Required) At least one screenshot is needed to demonstrate the app runs on CasaOS successfully
├─ screenshot-2.png     # (Optional) More screenshots to demonstrate different functionalities are highly recommended
├─ screenshot-3.png     # (Optional) ...
└─ thumbnail.png        # (Required) A thumbnail file is needed if you want it to be featured in AppStore front (see specification at bottom)
```

#### A CasaOS App is a Docker Compose app, or a *compose app*

Each directory under [Apps](Apps) corresponds to a CasaOS App. The directory should contain at least a `docker-compose.yml` file:

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

- **System Variables**: CasaOS now provides additional system-wide variables for enhanced functionality:

    ```yaml
    environment:
      PGID: $PGID                           # Preset Group ID
      PUID: $PUID                           # Preset User ID  
      TZ: $TZ                               # Current system timezone
      PASSWORD: $default_pwd                # Secure default password generated by CasaOS
      DOMAIN: $domain                       # Domain (or subdomain) mapped to this container
      PUBLIC_IP: $public_ip                 # Public IP used for port binding and announcements
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
        | Username   | Password       |
        | --------   | ------------   |
        | `admin`    | `$default_pwd` |
```

### Features

CasaOS supports additional configuration options for enhanced app management:

#### Pre-Installation Commands

You can specify commands to run before container startup using `pre-install-cmd`. This command executes before all other containers are started:

```yaml
x-casaos:
    pre-install-cmd: docker run --rm -v /DATA/AppData/$AppID/:/data/ -e PASSWORD=$default_pwd nasselle/pre-install-toolbox https://example.com/init.sh
```

**Common use cases:**
- Create default configuration files
- Set up initial data structures
- Generate certificates or keys
- Prepare the environment with sensible defaults

#### Web UI Configuration

For applications with web interfaces, you must specify both the main service and web UI port:

```yaml
x-casaos:
    main: webui-service              # Name of the service providing the web interface
    webui_port: 8080                # Port exposed by the container for web UI access
```

#### NSL Router Integration

The Yundera AppStore uses the NSL Router (mesh-router) system to provide clean HTTPS URLs for your applications. The mesh router automatically generates subdomains based on your compose configuration.

**How NSL Router Works:**
- The mesh router runs on nsl.sh domains and provides subdomain routing to Yundera users
- Each user gets a subdomain like `username.nsl.sh`
- Applications are accessible via clean URLs without port numbers

**URL Generation Pattern:**
```
https://appname-username.nsl.sh/
```

**Compose File Requirements for NSL Router:**
- Use `expose` instead of `ports` for web UI services
- Set `webui_port` to port 80 when possible (recommended for clean URLs)
- Other ports are supported but will include the port in the URL
- The router automatically handles HTTPS termination and routing

**Example - Before NSL Router:**
```
http://server-ip:2283/  # Direct port access
```

**Example - With NSL Router:**
```yaml
services:
  immich:
    image: altran1502/immich-server:v1.135.3
    expose:
      - 80                    # Expose port 80 internally
    environment:
      IMMICH_PORT: 80        # Configure app to use port 80
      
x-casaos:
  main: immich
  webui_port: 80            # Must match exposed port
```

**Result:** `https://immich-username.nsl.sh/` (clean URL, no port numbers)

**Alternative - Non-80 Port Example:**
```yaml
services:
  grafana:
    image: grafana/grafana:latest
    expose:
      - 3000                  # Expose port 3000 internally
    environment:
      GF_SERVER_HTTP_PORT: 3000
      
x-casaos:
  main: grafana
  webui_port: 3000          # Must match exposed port
```

**Result:** `https://3000-grafana-username.nsl.sh/` (includes port in URL)

**Port Selection Guidelines:**
- **Port 80**: Clean URLs without port numbers (recommended)
- **Other ports**: Accessible but URL includes port prefix
- **Standard ports**: Use application defaults when port 80 conflicts with app requirements

The mesh router handles:
- HTTPS certificate management
- Subdomain routing to the correct container
- VPN-secured communication between router and containers
- Port-based subdomain generation for non-80 ports

**Web UI Requirements (all three must be configured together):**
- The main service must `expose` the web UI port (using `expose`, not necessarily `ports`)
- The `webui_port` field must match the exposed port number
- The `main` field must reference a valid service name under `services`

**Important Notes:**
- Only one web UI domain is supported per app (even with multiple containers)
- HTTPS unwrapping is handled automatically by nsl.sh mesh router - no certificate management needed at container level
- Other ports can still be bound directly to the public IP for non-web services
- the main app name and hostname should be a simple name without spaces or special characters, as it will be used in the URL.

**Example Configuration:**

```yaml
services:
  database:
    image: postgres:13
    # Database service - no web UI
    
  webui-service:
    image: myapp:latest
    expose:
      - 8080                        # Must expose the web UI port
    ports:
      - "9000:9000"                 # Direct port binding for API or other services
    depends_on:
      - database

x-casaos:
    main: webui-service             # References the service with web UI
    webui_port: 8080               # Must match the exposed port above
```

#### System Variables

CasaOS automatically provides several system variables for your compose files:

** Variables:**
- `$default_pwd`: A secure default password generated by CasaOS for applications requiring authentication
- `$domain`: The domain or subdomain mapped to this container for web UI access
- `$public_ip`: The public IP address used for port binding announcements and external access
- `$AppID`: The application name/ID
- `$PUID/$PGID`: User/Group IDs for proper file permissions
- `$TZ`: System timezone

**Example Usage:**
```yaml
environment:
  - PASSWORD=$default_pwd
  - DOMAIN=$domain  
  - PUBLIC_IP=$public_ip
  - PUID=$PUID
  - PGID=$PGID
  - TZ=$TZ
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
All apps submitted for validation must include *descriptions* and *tagline* in at least the following languages: **English, French, Korean, Chinese, and Spanish**.
For the title, only English is required.

## Feedback

If you have any feedback or suggestions about this contributing process, please let us know via Discord or Issues. Thanks!
