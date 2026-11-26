# Chatpad — rationale

## No data volume

`chatpad-backend` (`ghcr.io/deiucanta/chatpad`) is a static single-page application served
by nginx: the image holds only the built bundle, a `config.json` of UI defaults and nginx's
config. The server stores nothing. What a user creates — conversations, saved prompts,
settings and the OpenAI API key — is kept in the browser's IndexedDB on the user's device,
and requests go from the browser to the OpenAI API directly. There is therefore no state
location in the container to map, and no folder under `/DATA/AppData/chatpad/` is needed.
Chatpad's own **Settings > Export / Import** moves that data between browsers.

## Root container

`chatpad-backend` runs as the image's default user (root, as the official nginx image it is
built on does) and has no bind mount at all, so it touches no host path (rule D1). No
privilege, capability or host namespace is added.
