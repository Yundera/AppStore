# Claude Code App Rationale

## Authentication

This app uses a custom auth proxy with session-based authentication. The `AUTH_PASSWORD` environment variable is set to `$default_pwd` which generates a secure random password on first install.

Users can find this password in the app settings and change it if needed.

## User Permissions

The container runs as root (`user: 0:0`) because:
- Supervisor needs to manage multiple processes (ttyd and auth-proxy)
- The actual Claude Code CLI runs as the `claude` user (UID 1000) inside the container
- The workspace directory is owned by UID 1000 for proper file permissions

## Resource Allocation

- CPU shares: 70 (interactive + heavy tasks category)
- Memory limit: 2048M (Claude Code can use significant memory for large codebases)

## Required Assets

The following files need to be added to this directory:

| File | Size | Description |
|------|------|-------------|
| `icon.png` | 192x192 px | App icon (transparent background) |
| `screenshot-1.png` | 1280x720 px | Login page screenshot |
| `screenshot-2.png` | 1280x720 px | Terminal with Claude running |
| `screenshot-3.png` | 1280x720 px | Claude Code in action |
| `thumbnail.png` | 784x442 px | Featured app thumbnail (rounded corners) |

## Source Repository

The Docker image is built from: https://github.com/yundera/claude-code-container
