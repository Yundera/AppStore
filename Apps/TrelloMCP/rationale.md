# TrelloMCP — Rationale

## Setup requires a trello.com account (zero-config exception)

Trello MCP is a bridge to the **Trello** REST API, and Trello identity lives on **trello.com**,
a service outside the operator's control. Every Trello tool needs an API key and a token, and
the only way to get them is through a trello.com account: create a Power-Up in
[Trello Power-Ups Admin](https://trello.com/power-ups/admin), copy its API key, then approve
**Authorize with Trello** on trello.com. Until then the MCP server runs and its Web UI works,
but every Trello tool answers "credentials not configured".

This is inherent to what the app does — it exposes the user's own Trello boards — not a
packaging choice, and nothing in this compose can change it. No file has to be edited and no
command has to be run: the API key is pasted into the Web UI's Setup page, and the token comes
back on `/callback` in the same browser session and is saved automatically. Neither credential
is written to a log, and neither has to be read from a file.

The operator's path is documented where the platform surfaces it: the Tips dialog walks through
the two setup steps (Power-Up with the app's own URL as Iframe connector and allowed origin,
then Authorize with Trello).

Recorded here under the Functional Review Protocol's **third-party identity exception**, so an
audit that holds no trello.com account records `zero-config` as a pass with the dependency
named, instead of leaving the run unsettleable and retried forever.
