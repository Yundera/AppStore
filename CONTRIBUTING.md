# Contributing to the AppStore

This document describes how to contribute an app to the Yundera Compose AppStore.

**IMPORTANT**: Your PR must be *well tested* on your own CasaOS first. This is the mandatory first step for your submission.

## Submission Checklist

Before submitting your PR, ensure your app meets these requirements:

### Tech Checklist
- [ ] Proper file permissions based on volume usage. See [Permission Strategy](#permission-strategy) for details
- [ ] **Pre-install and Post-install commands security**: If using `pre-install-cmd` or `post-install-cmd`, ensure specific version tags (no `:latest`) and proper user permissions (`--user $PUID:$PGID` when writing to user directories)
- [ ] **Install hooks are idempotent**: a hook is rerun on every reinstall and every version upgrade, so guard one-shot work behind an existence check or a sentinel. A hook that exits non-zero leaves the app installed but **stopped**. See [Pre-Installation Commands](#pre-installation-commands)
- [ ] **Directories the app needs are declared** under `x-compose-app.folders` with `schema_version: 2`, not created by a hook. See [Maison and `x-compose-app`](#maison-and-x-compose-app)
- [ ] **Deployment values are references, not literals**: the shared network is declared as `name: ${APP_NET:-pcs}` (never a bare `name: pcs`), and every bind source starts with `${DATA_ROOT:-/DATA}`. Maison copies the compose byte-for-byte and never rewrites it, so a literal freezes the app to one deployment. See [System Variables](#system-variables)
- [ ] **Only services that need outside reachability are on the shared network**, and each of them has an app-prefixed service name and `container_name`. Siblings that only talk to each other belong on an app-internal `driver: bridge` network. See [Shared-network hygiene](#caddy-integration-web-ui-access)

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
- [ ] A mount that exposes a broad slice of `/DATA` (`/DATA/Documents`, `/DATA/Downloads`, `/DATA/Media`, `/DATA/Gallery`, or `/DATA` itself) is called out — in the app `description`, in `tips.before_install`, or in `rationale.md`. The user has to be able to see what the app can reach before they install it
- [ ] Icon and screenshots meet specifications - files and URLs point to this Yundera repository (eg https://cdn.jsdelivr.net/gh/Yundera/AppStore@main/Apps/Duplicati/thumbnail.png)

## Testing and Submit Process

App submission should be done via Pull Request. Fork this repository and prepare the app per guidelines below.
Once the PR is ready, create and assign your PR to anyone from the CasaOS Team or another trusted contributor.

To ensure easy testing, please follow these steps:

1. Start with a regular compose app, which is a directory containing a `docker-compose.yml` file. Test it on your own machine to ensure you can start it successfully. In your instance, you can edit the compose file with a text editor and restart the app to check if the changes work. Use SSH to do `docker compose up -d` if needed.

2. Copy the compose onto a PCS under the app's own folder, e.g. `/DATA/AppData/MyApp/docker-compose.yml`, add the required metadata (`x-casaos`, `x-compose-app`), and test it there over SSH with `docker compose up -d`. A hand-run `docker compose up -d` in the app's folder is exactly what Maison does — it copies your `docker-compose.yml` byte-for-byte and never edits it; the only things it adds are the app's `.env` (the deployment's variables) and `docker-compose.override.yml` (the extra domains it publishes on). So if it works by hand with a real `.env`, it works as an installed app. Step 4 still proves the listing itself — metadata, icon, pre-install assets.

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
- **Graceful Data Reuse**: Applications must detect and reuse existing data when reinstalled. In practice this is a property of the app's **install hook**: it runs again on every reinstall and every upgrade, so anything that only makes sense once must be guarded by an existence check
- **No Data Erasure**: Container startup processes must never erase or overwrite existing user data
- **Configuration Preservation**: Settings, user accounts, and preferences should persist across container lifecycle

**Implementation Guidelines:**
- Map all persistent data to `/DATA/AppData/[AppName]/` subdirectories
- Use initialization scripts that check for existing data before creating defaults — and remember `&&` chains propagate the failure: one initialiser refusing to overwrite an existing file takes the whole hook down with it
- Ensure database migrations are handled gracefully on version updates
- Test uninstall/reinstall scenarios to verify data persistence

**Example Volume Mapping:**
```yaml
volumes:
  - ${DATA_ROOT:-/DATA}/AppData/myapp/config:/app/config
  - ${DATA_ROOT:-/DATA}/AppData/myapp/database:/var/lib/database
  - ${DATA_ROOT:-/DATA}/AppData/myapp/uploads:/app/uploads
```

Write the bind source as `${DATA_ROOT:-/DATA}/…`, not a bare `/DATA/…`. The data
folder is `/DATA` on a PCS but not on every deployment, and a bind source is resolved
by the **host** daemon — so the reference is what makes the app portable. The `:-/DATA`
default keeps the compose working when you run it by hand. See
[System Variables](#system-variables). Elsewhere in this document `/DATA/...` is used
as shorthand for the data folder itself; in a bind source, always write the variable.

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

Apps are configured through two extension blocks: `x-casaos`, inherited from the
CasaOS store format, and `x-compose-app`, read by Yundera's own dashboard.

#### Maison and `x-compose-app`

Yundera's dashboard is **Maison**. It consumes the unmodified CasaOS `x-casaos`
block, so every existing store app keeps working unchanged — but it also reads its
own Compose extension, `x-compose-app`, and **prefers it for every field it
defines**, falling back for anything it omits:

```
x-compose-app  →  x-casaos  →  runtime derivation
```

Maison reads the **app-level** `x-casaos` block. It does *not* read the per-service
`x-casaos.envs` / `x-casaos.volumes` / `ports` / `devices` description lists that the
CasaOS UI used to render as a per-field config form — the struct is parsed and then
never consumed, so those `description:` entries reach no user. **Don't write them in
new apps.** They survive in a handful of older apps (`Apps/FileBrowser`,
`Apps/Stremio`) as inert metadata; leave them alone rather than churning the files.
Anything a user genuinely needs to know before installing belongs in the app
`description`, in `tips.before_install`, or in `rationale.md`.

Most apps in this store already carry an `x-compose-app` block. Two of its keys are
load-bearing and both require `schema_version: 2`: **`folders`** and **`hooks`**.
Declare `schema_version: 2` when your app *needs* them, so an older Maison refuses
the app outright instead of silently starting it without its directories.

##### The stack-up sequence

Everything below hangs off one sequence, and **every** `docker compose up` Maison
runs goes through it — install, start from the tile, store update, and saving the
app's config alike:

```
ensure folders  →  pre_up  →  docker compose up -d  →  post_up
```

`pre_install` / `post_install` bracket that sequence, but only on the install itself:

```
write compose + .env  →  ensure folders  →  pull images
                      →  pre_install  →  [ the up sequence ]  →  post_install
```

The ordering is the part to internalise: **a directory declared under `folders`
exists, owned correctly, before any image is pulled, before any hook runs, and
before the containers start** — on the first boot and on every boot after it.

##### `folders` — the directories your app needs

Compose creates a missing bind-mount source as an empty **root-owned** directory. An
app that drops privileges to `PUID:PGID` then can't write to its own config volume:
the classic "permission denied on first start". `folders` fixes that declaratively.

```yaml
x-compose-app:
  schema_version: 2
  folders:
    - /DATA/AppData/$AppID/config            # shorthand: this path, all defaults
    - path: /DATA/AppData/$AppID/data        # full form
      user: $PUID
      group: $PGID
      mode: "0750"
    - path: /DATA/Media
      group: media
      recursive: true                        # also reclaim what is already inside
```

| Key | Default | Meaning |
|---|---|---|
| `path` | — (required) | Absolute host path, under `/DATA`. Interpolated with the app's variables and its `.env`. |
| `user` | `$PUID` | Owning user. |
| `group` | `$PGID` | Owning group. |
| `mode` | `"0755"` | Permissions of `path` itself. **Must be quoted.** |
| `recursive` | `false` | Apply `user`/`group` to everything already inside `path`, not just `path`. |

**Maison does not read `volumes:` and guess.** A compose file says nothing about
whether a bind source is meant to be a directory or a config file, and every
heuristic for it — a trailing `/`, a dot in the last segment — is wrong in one
direction or the other. So a directory your app needs is a directory your app
**declares**; anything undeclared is left to Docker exactly as it would be outside
Maison. This is the one real porting step for an app coming from a CasaOS store:
its bind mounts work, but any directory needing `PUID:PGID` ownership before first
start has to be listed here.

Three things are declaration *errors* that fail the up rather than being skipped: a
variable that resolves to nothing, a relative path, and a path outside `/DATA`.
Ownership and mode are applied best-effort — a filesystem that can't `chown` logs a
warning rather than blocking an otherwise healthy start.

`mode` must be quoted. Unquoted, YAML types it as an octal *int* and the leading
zero is gone before Maison ever sees it:

```yaml
mode: "0750"   # ✅
mode: 0750     # ❌ rejected — Maison names the fix rather than guessing what 488 meant
```

Use `recursive: true` only when the app must reclaim a tree it didn't create — a
restored backup, a media library another app wrote, a directory an earlier
root-running version left behind. The walk is proportional to the size of the tree,
so keep it off multi-terabyte media folders that are already correct. It rewrites
**ownership only**; `mode` still applies to `path` itself and nothing below it.

##### `hooks` — shell around the lifecycle

| Hook | Runs |
|---|---|
| `pre_install` | Once, at install: after images are pulled, before the first up. |
| `post_install` | Once, right after that first up succeeds. |
| `pre_up` | Before **every** up — install, every later start, update, and config save. |
| `post_up` | After every up. |

```yaml
x-compose-app:
  schema_version: 2
  hooks:
    pre_install: |
      # No openssl in the Maison container — use od(1), which busybox and
      # coreutils both provide. Anything beyond a POSIX shell toolbox should go
      # through a pinned `docker run` (Style B below) rather than be assumed.
      od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > /DATA/AppData/$AppID/secrets/key
    post_up: |
      echo "$AppID up at $(date)" >> /var/log/maison-apps.log
```

`pre_install` / `post_install` generalise the CasaOS `pre-install-cmd` /
`post-install-cmd` and **win over them** when both are present. An app carrying only
`x-casaos` keeps working with no change, which is why most of this store still uses
`pre-install-cmd` — both run through the same machinery and the requirements below
apply identically.

**Failure semantics.** `pre_install` and `pre_up` are **fatal**: a pre-hook is the
app's precondition, and if it doesn't hold the stack must not start. Note what that
means for `pre_up` — a flaky one blocks the app on *every* start. `post_install` and
`post_up` are logged and swallowed, because tearing a healthy app back down over a
failed after-the-fact tweak would be worse than the failed tweak.

**Where hooks run.** Through `/bin/bash -c` **inside the Maison container**, with the
working directory set to the app's folder, but talking to the **host** Docker daemon
via `DOCKER_HOST`. They get the app's interpolation variables plus its `.env`,
`AppID`, and `APP_DIR`. Because they're aimed at the host daemon, `/DATA` and
`${DATA_ROOT}` references in a hook name **host** paths — so a `docker run -v` in a
hook must name a path the host daemon can resolve.

**Reaching the app's `.env`.** `$APP_DIR` is the app's folder and is already the
working directory, so the env file Maison prefills is `$APP_DIR/.env`:

```yaml
    pre_install: |
      # Append, never truncate: Maison has already written APP_DOMAIN, PUID,
      # PGID, APP_DEFAULT_PASSWORD and APP_NET into this file. A bare `>` wipes
      # them and the app installs with an empty environment.
      grep -q '^MYAPP_SECRET=' $APP_DIR/.env ||
        printf 'MYAPP_SECRET=%s\n' "$(cat /DATA/AppData/$AppID/secrets/key)" >> $APP_DIR/.env
```

> There is **no** `/DATA/AppData/casaos/apps/<id>/.env`. That was CasaOS's layout;
> Maison does not use it, and a hook writing there silently succeeds while the app
> never sees the value.

> **Don't `mkdir` in a hook.** That path is a host path, but the `mkdir` itself runs
> in the Maison container — creating the wrong directory in the wrong place. Declare
> it under `folders` instead: those are created through Maison's data mount and are
> correct on both sides. Hooks are for **Docker-level** work — priming a volume with
> `docker run`, pulling a sidecar image, poking another stack. Directories are what
> `folders` is for.

##### `webui-host` — the click URL

CasaOS asks for a container port and *derives* a hostname at install time.
`x-compose-app` instead lets you declare the **final URL**, so the tile's link and
the app's Caddy route are the same string:

```yaml
services:
  myapp:
    labels:
      caddy_0: myapp-${APP_DOMAIN}         # the route
x-compose-app:
  webui-host: myapp-${domain}              # the click URL host — same shape
  webui-path: /
```

| Field | Default | Meaning |
|---|---|---|
| `webui-host` | — | The URL host. Omit for a headless app — its tile gets no open action. |
| `webui-path` | `/` | Path appended to the host; may include a query string. |
| `webui-scheme` | `https` | The scheme the **browser** uses. |
| `webui-port` | `""` | The **URL** port, not the container port. Empty in the normal gateway case. |

`${domain}` / `${DOMAIN}` are resolved on every render, so the URL tracks a domain
change and works for apps Maison never installed. Keeping `webui-host` identical to
the `caddy_0` label also matters for route generation: Maison clones the app's Caddy
route group onto every additional domain the deployment answers on, so the click URL
keeps mirroring the route it was cloned from.

##### `view` — which grid the tile lands in

```yaml
x-compose-app:
  view: system        # apps (default) | system | hidden
```

`view: system` also **protects** the app — Maison refuses Stop and Uninstall (Restart
and Start stay available, so a wedged platform app is still recoverable without SSH)
and skips it in scheduled backups. It is a foot-gun guard, not a security boundary:
the app declares it about itself. Reserve it for platform pieces; ordinary apps
should leave `view` alone.

##### Keys Maison writes itself

`store` / `store-app-id` and `generated-routes` show up in an *installed* app's
override file. They are Maison's own bookkeeping — don't use those names for
author fields.

#### Pre-Installation Commands

You can specify commands to run before container startup using `pre-install-cmd`. It executes on the host before any of the app's services start. Two styles are acceptable — pick whichever is simpler for your needs:

**Style A — plain shell on the host.** Good for downloading static assets or seeding config files with tools that already exist on the host. (For *directories*, use `x-compose-app.folders` instead — see [Maison and `x-compose-app`](#maison-and-x-compose-app).)

```yaml
x-casaos:
  pre-install-cmd: |
    # config/ is created and chowned by x-compose-app.folders before this hook
    # runs — there is nothing to mkdir here.
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
    # db/ is created and chowned by x-compose-app.folders, which Maison guarantees
    # before this hook runs — don't mkdir or chown it here.
    # Idempotency: seed the database only on a first install. `config init` refuses
    # an existing database and exits non-zero, which would abort the whole hook on
    # every reinstall and every version upgrade.
    if [ ! -f /DATA/AppData/$AppID/db/database.db ]; then
      docker run --rm --user $PUID:$PGID -v /DATA/AppData/$AppID/db/:/db/ filebrowser/filebrowser:v2.63.2 config init --database /db/database.db &&
      docker run --rm --user $PUID:$PGID -v /DATA/AppData/$AppID/db/:/db/ filebrowser/filebrowser:v2.63.2 users add admin $APP_DEFAULT_PASSWORD --perm.admin --database /db/database.db
    fi
```

> The guard is not decoration. Chaining one-shot initialisers with `&&` and no
> existence check is the single most common way an app passes a fresh install and
> then fails every reinstall and upgrade afterwards — the hook exits non-zero, and
> the app is left installed but **stopped**, with its data intact but unreachable
> until someone presses Start by hand.

**Requirements (apply to both styles):**
- [ ] **Specific version tags**: Never use `:latest` — always pin exact versions (e.g. `alpine:3.19`, `ubuntu:22.04`).
- [ ] **Idempotent**: Safe to rerun. Guard destructive / one-shot work behind a sentinel file (`touch /DATA/AppData/$AppID/.initialized`) or an existence check.
- [ ] **Non-interactive**: Must not prompt.
- [ ] **No hardcoded credentials**: Use `$APP_DEFAULT_PASSWORD` and friends.
- [ ] **User permissions when touching user directories**: Use `--user $PUID:$PGID` (Style B) whenever files will live under `/DATA/Documents`, `/DATA/Downloads`, `/DATA/Media`, or `/DATA/Gallery`. To *own a directory*, declare it under `x-compose-app.folders` rather than chowning it here — Maison creates and chowns it before this hook runs.

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
- Ensure the `pcs` network is declared as shown below

**Compose File Requirements:**
- Use `expose` to expose the web UI port (required for Caddy discovery)
- Add Caddy labels to every service that answers on its own hostname. Most apps have exactly one; an app that also ships, say, its own Dex has two, and each gets its own `caddy_N` group on its own service
- Declare the shared network yourself, and connect **every service that must be reachable from outside your own compose project** to it — anything with Caddy labels, plus anything another app talks to. Services that only talk to their siblings do not belong on it (see *Shared-network hygiene* below):

  ```yaml
  networks:
    pcs:                       # the key is yours; the name is the deployment's
      name: ${APP_NET:-pcs}
      external: true
  ```

  Write `${APP_NET:-pcs}`, never a bare `pcs`. Maison copies your `docker-compose.yml` byte-for-byte and does not rewrite it, so the reference is what lets the same app run on a deployment whose network is called something else — and the `:-pcs` default keeps a bare `docker compose up` working when you test by hand
- Use `${APP_DOMAIN}` and `\${APP_PUBLIC_IP_DASH}` variables
- Set `container_name` explicitly on every service you attach to `pcs`. Caddy resolves each label's upstream via container DNS on that network, so the container must have a stable, predictable name. Constraints:
  - lowercase alphanumerics and `-` only (no underscores, dots, or other special characters)
  - must **not** start with a digit
  - should match the top-level `name:` and service name for consistency

**Shared-network hygiene:**

`pcs` is one flat network shared by every app on the box, and its DNS namespace is
shared with them. Compose gives each attached service an alias equal to its **service
name**, and Docker also resolves **container names** — so two apps that each attach a
service called `db` will cross-resolve, and one app's web tier can end up talking to
another's database. It is rare in practice only because names differ.

Two rules keep it that way:

- **Attach only what needs outside reachability.** A database, a cache or a worker that
  only its own siblings talk to belongs on an app-internal network (`driver: bridge`),
  not on `pcs`. Services on the same compose project reach each other by service name
  without either.
- **Prefix what you do attach.** Give every service on `pcs` an app-prefixed service
  name and `container_name` (`outline-dex`, not `dex`).

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
    name: ${APP_NET:-pcs}
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
    name: ${APP_NET:-pcs}
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
- Always include the `pcs` network definition with `external: true`, and **never set
  `name:` on it** — see the two rules below. Both are load-bearing on a real PCS.

> **Declare `pcs` without `name:`.** Write `pcs: {external: true}` and nothing more.
> Compose resolves an external network from its key, so the wire network is still
> `pcs` — but Maison's launcher treats an external network whose `name:` equals its
> own key as one *it* generated, deletes the entry, and detaches it from **every**
> service. Only `x-casaos.main` then gets the app network back. Writing
> `name: pcs` therefore strands every other service on the compose default bridge,
> where Docker's embedded DNS does not resolve container names.

> **`x-casaos.main` must name the service carrying the `caddy_N` labels.** Maison
> attaches the app network to that service and no other, and the tile's health
> follows it. Point `main` at a backend and the public-facing sidecar is left off the
> network entirely: Caddy has no upstream and every request 502s or 503s, behind a
> tile still showing green. For an AppShield app, `main` is always the **sidecar**.

> **Multi-service apps: consider an app-private bridge.** A second network shared by
> your services (`myapp-internal: {driver: bridge}`, listed on each service alongside
> `pcs`) keeps backend↔sidecar DNS working regardless of how the shared network is
> rewritten. Required if your services must reach each other by name.

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
    hostname: myapp                          # must equal container_name — OIDC identity (load-bearing — see checklist)
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
      # Optional:
      # USER: "ADMIN"                                       # extra basic-auth gate in front of the UI
      # PASSWORD: $APP_DEFAULT_PASSWORD
      # ALLOWED_PATHS: "mcp"                                # paths reachable with the hash token only (MCP servers)
      # OAUTH_RESOURCE: "https://myapp-${APP_DOMAIN}/mcp"   # OAuth 2.1 gate on that path (machine/API clients)
      # OAUTH_SCOPE: "mcp"
      # OAUTH_DATA_DIR: "/data/oauth"                       # mount /DATA/AppData/myapp/oauth here to persist clients
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
    name: ${APP_NET:-pcs}
    external: true

x-casaos:
  main: myapp                       # the SIDECAR — the service carrying the caddy_N
                                    # labels. Never the backend: see the rules above.
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
| `USER` / `PASSWORD` | optional | Extra basic-auth gate in front of the UI (e.g. `ADMIN` / `$APP_DEFAULT_PASSWORD`). |
| `ALLOWED_PATHS` | optional | Paths reachable with just the hash token, bypassing basic-auth — e.g. `mcp` for MCP servers. |
| `OAUTH_RESOURCE` | optional | Enables AppShield's OAuth 2.1 broker and gates exactly the path in the URL (e.g. `https://myapp-${APP_DOMAIN}/mcp`) on Bearer tokens. The machine/API path for MCP servers — see `Apps/Beacon`, `Apps/ChronosMCP`. Requires AppShield **>= 2.0.7**. |
| `OAUTH_SCOPE` | optional | Scope the resource advertises/grants (default `access`; MCP apps use `mcp`). |
| `OAUTH_DATA_DIR` | optional | Where registered clients, signing keys and grants live. Set to `/data/oauth` and bind-mount `/DATA/AppData/<app>/oauth` so they survive redeploys. |

> **`CREDENTIAL_VALIDATE_URL` is gone.** It used to point at `http://casaos-oidc-bridge:8090/validate` so machine clients could authenticate with CasaOS credentials. The bridge is being removed — do **not** add this variable to new apps. Machine/API access now goes through `OAUTH_RESOURCE` (or a real `AUTH_HASH`, which needs `AUTH_HASH_MODE: "env"` or `"managed"` — the default is `off` and silently ignores `AUTH_HASH`).

**Checklist for OIDC apps:**
- [ ] Caddy labels are attached **only to the AppShield sidecar**, never to the backend — otherwise the backend is exposed unauthenticated.
- [ ] The sidecar carries the full env set: `AUTH_HASH`, `BACKEND_HOST`, `BACKEND_PORT`, `LISTEN_PORT`, `OIDC_REGISTRAR_URL`, `REDIRECT_HOST_SUFFIXES`.
- [ ] `x-casaos.index` is set to `/?hash=$AUTH_HASH` when using `AUTH_HASH`.
- [ ] `x-casaos.main` points at the primary service.
- [ ] Backend service has no `ports:` and no public Caddy labels; it is reachable only via the `pcs` network.
- [ ] The sidecar's `container_name` equals the top-level `name:` (lowercase alnum + `-`, not starting with a digit). `auth-registrar` derives the OIDC `client_id` from the container name via PTR lookup on the `pcs` network, so the `container_name` is load-bearing — it must be stable across reinstalls. The compose **service name itself may differ** (shipped apps use `myapp`, `myapp-proxy`, `nginxhashlock`, etc.).
- [ ] The sidecar sets `hostname:` to the **same value** as its `container_name`. AppShield's auth-service builds its OIDC redirect URIs from `os.hostname()` (as `<app>-<suffix>`), and `auth-registrar` independently attests the app name via the container's PTR record and **rejects any redirect URI that doesn't match**. If `hostname:` is omitted, Docker defaults it to the random container ID, the submitted redirect URIs won't match the attested name, and OIDC registration fails at first login. (`container_name` alone does **not** set the in-container hostname.)
- [ ] Do not claim `auth-${APP_DOMAIN}` in any Caddy label — it collides with the PCS's Authelia and causes intermittent `invalid_client` errors.
- [ ] Pin AppShield to a specific version tag (currently `ghcr.io/yundera/appshield:2.0.3`) — never `:latest` / `:main`.

**Requirements on the host PCS:** the `authelia` and `auth-registrar` containers must be running on the `pcs` network (provisioned automatically by the current `template-root`). If they are missing, the app fails at first login with `ENOTFOUND auth-registrar` in the sidecar logs.

#### System Variables

Yundera injects the following variables into every app at container creation. Reference them in `environment:`, `volumes:`, `labels:`, and `pre-install-cmd`.

These are written into the app's `.env` on install and refreshed on **every start**, so they track the deployment as it changes. Maison does not edit your compose file — a variable reaches your app only because your compose references it.

For the two that describe *where the deployment puts things*, write the defaulted form (`${APP_NET:-pcs}`, `${DATA_ROOT:-/DATA}`): the reference is what makes the app portable, and the default is what keeps a hand-run `docker compose up -d` working before Maison has written an `.env`.

**Available variables:**
- `$APP_NET`: The shared external network apps are attached to (`pcs` on a PCS). Use it as `name: ${APP_NET:-pcs}` in your `networks:` block — see [Caddy Integration](#caddy-integration-web-ui-access).
- `$DATA_ROOT`: The data folder as the **Docker host** sees it — normally `/DATA`, but not on every deployment. Use it as the prefix of every bind source: `${DATA_ROOT:-/DATA}/AppData/$AppID/…`.
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
  - ${DATA_ROOT:-/DATA}/AppData/$AppID/data:/app/data
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
