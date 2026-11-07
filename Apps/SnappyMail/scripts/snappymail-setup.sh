#!/bin/sh
# SnappyMail's configuration, run by the `snappymail-config` setup step on every
# up, before the server starts, in the SnappyMail image (data folder mounted at
# /var/lib/snappymail). SNAPPYMAIL_ADMIN_PASSWORD comes from the app's secrets.
#
# Every up: HTTPS left to the proxy, and the admin panel's password set from the
# secret (so a change from Maison's Security tab takes effect).
# First up only (marker .yundera-setup): defaults a user can change later in the
# admin panel: contacts, invitation viewer, threads. The mail domains of the big
# providers are the compose's `files`, written right after this step.
set -eu
D=/var/lib/snappymail/_data_/_default_
INI=$D/configs/application.ini
[ -n "${SNAPPYMAIL_ADMIN_PASSWORD:-}" ] || { echo "SNAPPYMAIL_ADMIN_PASSWORD missing" >&2; exit 1; }

# The default config and domains, written the way the image's entrypoint does it.
if [ ! -f "$INI" ]; then
  chown -R www-data:www-data /var/lib/snappymail
  su - www-data -s /bin/sh -c 'php /snappymail/index.php' > /tmp/out || { cat /tmp/out; exit 1; }
  [ -f "$INI" ] || { echo "SnappyMail wrote no $INI" >&2; exit 1; }
  # That first run also adds a domain named after this (throwaway) container's host name,
  # and SnappyMail's own disabled list (gmail.com, yahoo.com…): the compose's `files`
  # bring the listing's (only "*" off), written only where no file is.
  rm -f "$D/domains/$(hostname).json" "$D/domains/disabled"
fi

# ini_get SECTION KEY / ini_set SECTION KEY VALUE (VALUE written as is)
ini_get() {
  awk -v s="[$1]" -v k="$2" '
    /^\[/ { insec = ($0 == s) }
    insec && $0 ~ "^" k " *=" { sub("^" k " *= *", ""); gsub(/^"|"$/, ""); print; exit }' "$INI"
}
ini_set() {
  awk -v s="[$1]" -v k="$2" -v v="$3" '
    /^\[/ { insec = ($0 == s) }
    insec && $0 ~ "^" k " *=" { print k " = " v; next }
    { print }' "$INI" > "$INI.new" && cat "$INI.new" > "$INI" && rm -f "$INI.new"
}

# Caddy terminates TLS; since 3.0 force_https ignores X-Forwarded-Proto and loops.
ini_set security force_https Off

# The admin panel password: a bcrypt hash in the config. Rewritten only when it
# no longer matches the secret. The generated admin_password.txt is not used.
current=$(ini_get security admin_password)
if ! php -r 'exit(password_verify(getenv("SNAPPYMAIL_ADMIN_PASSWORD"), $argv[1]) ? 0 : 1);' "$current"; then
  hash=$(php -r 'echo password_hash(getenv("SNAPPYMAIL_ADMIN_PASSWORD"), PASSWORD_DEFAULT);')
  ini_set security admin_login '"admin"'
  ini_set security admin_password "\"$hash\""
  echo "admin password set"
fi
rm -f "$D/admin_password.txt"

if [ ! -f "$D/.yundera-setup" ]; then
  ini_set contacts enable On
  ini_set contacts allow_sync On
  ini_set contacts sync_interval 20
  ini_set contacts type '"sqlite"'
  ini_set plugins enable On
  ini_set plugins enabled_list '"view-ics"'
  ini_set login sign_me_auto '"DefaultOn"'
  ini_set defaults mail_use_threads On
  touch "$D/.yundera-setup"
  echo "defaults written"
fi

chown -R www-data:www-data /var/lib/snappymail
