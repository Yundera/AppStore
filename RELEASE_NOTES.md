# Release Notes Guide

This document outlines the best practices for creating release notes in the Yundera AppStore.

## Tag Naming Convention

We use **app-specific tags** to track updates for individual applications.

### Format

```
{app-name}-v{version}
```

### Examples

| App | Upstream Version | Tag |
|-----|------------------|-----|
| Immich | 2.3.1 | `immich-v2.3.1` |
| Nextcloud | 28.0.1 | `nextcloud-v28.0.1` |
| Seafile | 11.0.5 | `seafile-v11.0.5` |
| Mastodon | 4.2.0 | `mastodon-v4.2.0` |

### Rules

1. **Lowercase app name**: Use lowercase for the app name (e.g., `immich`, not `Immich`)
2. **Match upstream version**: Use the same version number as the upstream project
3. **Semantic versioning**: Follow the upstream's versioning scheme (usually semver)
4. **No prefix duplication**: Use `immich-v2.3.1`, not `immich-version-2.3.1`

## Release Note Structure

Each release note should follow this template:

```markdown
## {App Name} v{Version}

**{Brief summary of the update}**

### New Features
- Feature 1 description
- Feature 2 description

### Updated Components
| Component | Old Version | New Version |
|-----------|-------------|-------------|
| component-1 | x.x.x | y.y.y |
| component-2 | x.x.x | y.y.y |

### Breaking Changes
- Description of any breaking changes (if applicable)

### Migration Notes
- Step-by-step migration instructions (if needed)
- Configuration changes required

### Links
- [Official Release Notes](https://...)
- [Documentation](https://...)
```

### Section Guidelines

| Section | Required | Description |
|---------|----------|-------------|
| Title | Yes | App name and version |
| Summary | Yes | One-line description of the update |
| New Features | Yes | List of new features (use "Bug fixes" if patch release) |
| Updated Components | Yes | Table of updated Docker images/dependencies |
| Breaking Changes | No | Only if there are breaking changes |
| Migration Notes | No | Only if special steps are required |
| Links | Recommended | Links to upstream docs and release notes |

## Creating Releases via Command Line

### Prerequisites

1. Install GitHub CLI:
   ```bash
   # Ubuntu/Debian
   curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
   sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
   echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
   sudo apt update && sudo apt install gh -y

   # macOS
   brew install gh
   ```

2. Authenticate with GitHub:
   ```bash
   gh auth login
   ```

### Creating a Release

#### Basic Command

```bash
gh release create {tag} --title "{Title}" --notes "{Release notes}"
```

#### Using a HEREDOC for Multi-line Notes

```bash
gh release create immich-v2.3.1 --title "Immich v2.3.1" --notes "$(cat <<'EOF'
## Immich v2.3.1

**Major upgrade from v1.143.1 to v2.3.1**

### New Features
- OCR (Optical Character Recognition) - Search for text within photos
- Improved web performance via Rust/WebAssembly

### Updated Components
| Component | Old Version | New Version |
|-----------|-------------|-------------|
| immich-server | v1.143.1 | v2.3.1 |
| immich-machine-learning | v1.143.1 | v2.3.1 |

### Migration Notes
- No special migration steps required
- To enable OCR for existing photos, run the OCR job in Administration > Job Settings

### Links
- [Official Release Notes](https://github.com/immich-app/immich/releases/tag/v2.3.1)
EOF
)"
```

#### Using a Release Notes File

```bash
# Create release notes file
cat > /tmp/release-notes.md << 'EOF'
## App Name vX.Y.Z

Release notes content here...
EOF

# Create release from file
gh release create app-vX.Y.Z --title "App Name vX.Y.Z" --notes-file /tmp/release-notes.md
```

### Additional Options

```bash
# Create a draft release (not published immediately)
gh release create tag --draft --title "Title" --notes "Notes"

# Create a pre-release
gh release create tag --prerelease --title "Title" --notes "Notes"

# Target a specific commit (instead of latest)
gh release create tag --target abc1234 --title "Title" --notes "Notes"

# Upload assets with the release
gh release create tag --title "Title" --notes "Notes" ./file1.zip ./file2.tar.gz
```

### Viewing Existing Releases

```bash
# List all releases
gh release list

# View a specific release
gh release view immich-v2.3.1

# Download release assets
gh release download immich-v2.3.1
```

### Editing an Existing Release

```bash
# Edit release notes
gh release edit immich-v2.3.1 --notes "Updated notes"

# Edit title
gh release edit immich-v2.3.1 --title "New Title"

# Edit from file
gh release edit immich-v2.3.1 --notes-file /tmp/updated-notes.md
```

### Deleting a Release

```bash
# Delete release (keeps the tag)
gh release delete immich-v2.3.1

# Delete release and its tag
gh release delete immich-v2.3.1 --yes --cleanup-tag
```

## Workflow Summary

1. **Make changes** to the app's `docker-compose.yml`
2. **Commit and push** the changes to main branch
3. **Create release** with appropriate tag and notes:
   ```bash
   gh release create {app}-v{version} --title "{App} v{version}" --notes "$(cat <<'EOF'
   Release notes here...
   EOF
   )"
   ```
4. **Verify** the release on GitHub: `https://github.com/Yundera/AppStore/releases`

## Example: Full Release Workflow

```bash
# 1. Navigate to repository
cd /path/to/YunderaAppStore

# 2. Make changes to app config
# (edit Apps/Immich/docker-compose.yml)

# 3. Commit changes
git add Apps/Immich/docker-compose.yml
git commit -m "update immich to version 2.3.1"
git push origin main

# 4. Create release
gh release create immich-v2.3.1 --title "Immich v2.3.1" --notes "$(cat <<'EOF'
## Immich v2.3.1

**Major upgrade to stable v2.x series**

### New Features
- OCR support for text search in photos
- Improved performance

### Updated Components
| Component | Old | New |
|-----------|-----|-----|
| immich-server | v1.143.1 | v2.3.1 |

### Links
- [Release Notes](https://github.com/immich-app/immich/releases/tag/v2.3.1)
EOF
)"

# 5. Verify
gh release view immich-v2.3.1
```
