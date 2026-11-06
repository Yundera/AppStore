#!/bin/sh
# SnappyMail's configuration, run by the `snappymail-config` setup step on every
# up, before the server starts, in the SnappyMail image (data folder mounted at
# /var/lib/snappymail). SNAPPYMAIL_ADMIN_PASSWORD comes from the app's secrets.
#
# Every up: HTTPS left to the proxy, and the admin panel's password set from the
# secret (so a change from Maison's Security tab takes effect).
# First up only (marker .yundera-setup): defaults a user can change later in the
# admin panel: contacts, invitation viewer, threads, and the mail domains of the
# big providers, with TLS certificate checks on (SnappyMail checks none by default).
set -eu
D=/var/lib/snappymail/_data_/_default_
INI=$D/configs/application.ini
[ -n "${SNAPPYMAIL_ADMIN_PASSWORD:-}" ] || { echo "SNAPPYMAIL_ADMIN_PASSWORD missing" >&2; exit 1; }

# The default config and domains, written the way the image's entrypoint does it.
if [ ! -f "$INI" ]; then
  chown -R www-data:www-data /var/lib/snappymail
  su - www-data -s /bin/sh -c 'php /snappymail/index.php' > /tmp/out || { cat /tmp/out; exit 1; }
  [ -f "$INI" ] || { echo "SnappyMail wrote no $INI" >&2; exit 1; }
  # That first run also adds a domain named after this (throwaway) container's host name.
  rm -f "$D/domains/$(hostname).json"
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
# domain_file NAME IMAPHOST IMAPPORT IMAPTYPE SMTPHOST SMTPPORT SMTPTYPE
# type: 0 plain, 1 SSL/TLS, 2 STARTTLS. The login is the full address.
domain_file() {
  ssl='"ssl": {"verify_peer": true, "verify_peer_name": true, "allow_self_signed": false, "SNI_enabled": true, "disable_compression": true, "security_level": 1}'
  sasl='"sasl": ["SCRAM-SHA-256", "SCRAM-SHA-1", "PLAIN", "LOGIN"]'
  cat > "$D/domains/$1.json" <<EOF
{
  "IMAP": {"host": "$2", "port": $3, "type": $4, "timeout": 300, "shortLogin": false, "lowerLogin": true,
           $sasl, $ssl, "disabled_capabilities": ["METADATA", "OBJECTID", "PREVIEW", "STATUS=SIZE"],
           "use_expunge_all_on_delete": false, "fast_simple_search": true, "force_select": false,
           "message_all_headers": false, "message_list_limit": 10000, "search_filter": ""},
  "SMTP": {"host": "$5", "port": $6, "type": $7, "timeout": 60, "shortLogin": false, "lowerLogin": true,
           $sasl, $ssl, "useAuth": true, "setSender": false, "usePhpMail": false},
  "Sieve": {"host": "$2", "port": 4190, "type": 0, "timeout": 10, "shortLogin": false, "lowerLogin": true,
            $sasl, $ssl, "enabled": false},
  "whiteList": ""
}
EOF
}

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
  # Mail domains. SnappyMail ships only a "*" entry pointing at localhost (and the
  # names of a few providers in its disabled list, with no settings behind them):
  # write the big providers that still take an app password over IMAP, with
  # certificate checks on (SnappyMail's default is off), and switch "*" off, so
  # any other domain is an explicit admin step.
  for spec in \
    "gmail.com imap.gmail.com 993 1 smtp.gmail.com 465 1" \
    "googlemail.com imap.gmail.com 993 1 smtp.gmail.com 465 1" \
    "yahoo.com imap.mail.yahoo.com 993 1 smtp.mail.yahoo.com 465 1" \
    "icloud.com imap.mail.me.com 993 1 smtp.mail.me.com 587 2" \
    "fastmail.com imap.fastmail.com 993 1 smtp.fastmail.com 465 1"; do
    set -- $spec
    domain_file "$@"
  done
  printf '*\n' > "$D/domains/disabled"
  touch "$D/.yundera-setup"
  echo "defaults written"
fi

chown -R www-data:www-data /var/lib/snappymail
