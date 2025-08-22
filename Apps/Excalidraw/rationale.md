# Security Rationale for Excalidraw

## No Authentication Required

Excalidraw is designed as a public collaborative whiteboard tool that works without user accounts. This is intentional for the following reasons:

- **Frictionless collaboration**: Enables instant sharing and collaboration without barriers
- **No barrier to entry**: Anyone can start drawing immediately without registration
- **Public whiteboard nature**: The application is designed to be open and accessible like a physical whiteboard
- **Privacy by design**: No user data is collected since there are no accounts

## Root User Justification  

The main container runs as root (`user: 0:0`) because:

- **No user file access required**: The application only accesses AppData directories under `/DATA/AppData/$AppID/`
- **Container isolation**: Docker container isolation provides sufficient security boundaries
- **No mixed permissions**: All data is stored in application-specific directories, not user-accessible areas
- **Simple deployment**: Eliminates permission complexity while maintaining security through containerization

## Network Security

- **Internal communication**: All inter-service communication happens within the Docker network
- **NSL Router protection**: External access is controlled through the NSL mesh router system
- **No direct port exposure**: Services use `expose` rather than `ports` for web UI access
- **HTTPS termination**: NSL Router handles SSL/TLS termination and provides secure access

## Data Privacy

- **Self-hosted**: All data remains on the user's server, never transmitted to external services
- **Redis storage**: Temporary collaboration data is stored in Redis for real-time features
- **No telemetry**: The application contains no analytics or tracking code
- **Local persistence**: Drawings can be exported locally by users for permanent storage