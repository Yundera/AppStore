# Docusaurus — Rationale

## What deviation / exception is being requested

Authentication (AppShield) is disabled. The app is publicly accessible without login.

## Why it is necessary

Docusaurus serves a **public documentation site**. Authentication would prevent the documentation from being publicly accessible, which defeats its core purpose.

- The site is intended to be readable by anyone with the URL, without login or registration.
- Docusaurus generates **static HTML** served by Nginx — there is no dynamic backend, no user accounts, and no sensitive data processing.

## Security mitigations in place

- **Read-only web access**: Nginx serves static files in read-only mode (`:ro` volume mount). There is no admin panel or write access exposed through the web interface.
- **Content management is authenticated**: Content modifications are done either via the host file system or through the DocusaurusMCP tool, which has its own authentication via AppShield.
- **User warning**: A warning is displayed in the app's install tips:
  > **Warning:** This is a public documentation site with no login or authentication. Anyone with the address can read everything inside it. Only add content you are happy to share publicly, and never store private notes, credentials, or personal data here.

## Alternatives considered and rejected

- **AppShield sidecar**: Would prevent public access, defeating the purpose of a documentation site.
- **Basic Auth**: Same issue — documentation should be publicly readable without credentials.

## Data protection

- No sensitive data is processed or stored by the web-facing container.
- The Nginx container mounts the build output as read-only.
- Source files and build output are stored under `/DATA/AppData/$AppID/` and are only writable by the init container and DocusaurusMCP.
