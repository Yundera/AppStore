#!/usr/bin/env bash
# Migration 2: Lamplighter 0.4 data -> the 0.5+ shape (shipped image 0.7.2).
#
# Lamplighter 0.5.0 moved forge tokens into a `credentials` table and folded that into its base
# migration "with no upgrade path: wipe a pre-0.5.0 data directory". Its own migrator only runs
# migrations past the recorded schema_version, so a 0.4 database would boot 0.7.2 with no
# `credentials` table. This does upstream's missing conversion in place, with the 0.7.2 image's
# own node and better-sqlite3, as the app user:
#   - each GitHub/Gitea forge's username + token become that forge's default credential;
#   - groups.credential_id, repos.credential_id and proposals.auto_waiting are added, and the
#     old token columns are dropped from forges, so the tables match a fresh 0.7.2 install;
#   - schema_version is set to 3, so 0.7.2 runs its last migration (command_runs) itself;
#   - config.yaml gets the `sandbox:` block a fresh install seeds from LAMPLIGHTER_DOCKER_URL.
# A database already in the new shape (it has a `credentials` table), or no database at all,
# is left alone, and a config.yaml that already has `sandbox:` is not touched.

[ -e "$APP_DIR/lamplighter.db" ] || [ -e "$APP_DIR/config.yaml" ] || exit 0

docker run --rm -i --user "$PUID:$PGID" -v "$APP_DIR:/DATA" -w /app --entrypoint node \
  ghcr.io/worph/lamplighter:0.7.2 - <<'JS'
const fs = require('fs')
const Database = require('better-sqlite3')

const cfgFile = '/DATA/config.yaml'
if (fs.existsSync(cfgFile)) {
  const cfg = fs.readFileSync(cfgFile, 'utf8')
  if (/^sandbox:/m.test(cfg)) {
    console.log('config.yaml already has a sandbox block')
  } else {
    fs.appendFileSync(cfgFile, (cfg.endsWith('\n') ? '' : '\n') +
      '\nsandbox:                     # added by the store migration to 0.7: Docker through the lamplighter-docker proxy\n' +
      '  enabled: true\n' +
      '  docker_url: tcp://lamplighter-docker:2375\n')
    console.log('config.yaml: sandbox block added')
  }
}

const dbFile = '/DATA/lamplighter.db'
if (!fs.existsSync(dbFile)) { console.log('no database yet'); process.exit(0) }
const db = new Database(dbFile)
db.pragma('busy_timeout = 5000')
const has = (t) => !!db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?").get(t)
const cols = (t) => db.prepare(`PRAGMA table_info(${t})`).all().map((c) => c.name)
if (!has('forges')) { console.log('database has no schema yet'); process.exit(0) }
if (has('credentials')) { console.log('database is already in the 0.5+ shape'); process.exit(0) }

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 24) || 'cred'
db.transaction(() => {
  // Migration 1 of 0.4 (blocked_input), for a database that stopped at 0.2.
  if (!cols('findings').includes('blocked_input')) db.exec('ALTER TABLE findings ADD COLUMN blocked_input TEXT')
  db.exec(`CREATE TABLE credentials (
    id TEXT PRIMARY KEY,
    forge_id TEXT NOT NULL REFERENCES forges(id) ON DELETE CASCADE,
    label TEXT NOT NULL,
    username TEXT,
    token TEXT,
    token_set_at TEXT,
    auth_json TEXT,
    commit_name TEXT,
    commit_email TEXT,
    is_default INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
  )`)
  const fc = cols('forges')
  const pick = (c) => (fc.includes(c) ? c : 'NULL')
  const forges = db.prepare(`SELECT id, kind, created_at, ${pick('username')} AS username, ${pick('token')} AS token, ${pick('token_set_at')} AS token_set_at FROM forges`).all()
  const add = db.prepare('INSERT INTO credentials (id, forge_id, label, username, token, token_set_at, auth_json, is_default, created_at) VALUES (?, ?, ?, ?, ?, ?, NULL, 1, ?)')
  let n = 0
  for (const f of forges) {
    // A bare git forge authenticates with the container's SSH key and has no credential.
    if (f.kind === 'git' || (!f.username && !f.token)) continue
    const label = f.username || 'default'
    add.run(`${f.id}-${slug(label)}`, f.id, label, f.username || null, f.token || null, f.token ? f.token_set_at || f.created_at : null, f.created_at)
    n++
  }
  for (const c of ['username', 'token', 'token_set_at', 'auth_json']) if (fc.includes(c)) db.exec(`ALTER TABLE forges DROP COLUMN ${c}`)
  db.exec('ALTER TABLE groups ADD COLUMN credential_id TEXT REFERENCES credentials(id) ON DELETE SET NULL')
  db.exec('ALTER TABLE repos ADD COLUMN credential_id TEXT REFERENCES credentials(id) ON DELETE SET NULL')
  db.exec('ALTER TABLE proposals ADD COLUMN auto_waiting INTEGER NOT NULL DEFAULT 0')
  db.prepare('UPDATE schema_version SET version = 3').run()
  console.log(`database converted: ${n} forge token(s) moved to credentials`)
})()
db.close()
JS
