#!/bin/bash
#
# Creates Guacamole's "guacadmin" administrator account.
#
# Run once by the stock postgres entrypoint from /docker-entrypoint-initdb.d/,
# immediately after 001-create-schema.sql and only while the data directory is
# still empty.
#
# This replaces upstream's 002-create-admin-user.sql, which seeds the constant,
# publicly-known guacadmin/guacadmin credential. Guacamole never forces a
# password change at first login and this app publishes itself on the public
# internet, so the account is created here with the per-deployment password
# Yundera generates ($APP_DEFAULT_PASSWORD, passed in as
# GUACAMOLE_ADMIN_PASSWORD) and a fresh random salt.
#
# Password hashing matches guacamole-auth-jdbc's PasswordEncryptionService:
#     hash = SHA-256( UTF8(password) || UPPERCASE_HEX(salt) )
#
# The permission grants below are taken from upstream 002-create-admin-user.sql
# (Apache Guacamole, Apache License 2.0).

# Everything runs in a subshell: the postgres entrypoint *sources* any
# non-executable *.sh it finds here, and shell options set at top level would
# leak into it. Options set inside a subshell do not, while a non-zero exit
# still aborts the init as it should.
(
    set -eu

    if [ -z "${GUACAMOLE_ADMIN_PASSWORD:-}" ]; then
        echo "002-create-admin-user.sh: GUACAMOLE_ADMIN_PASSWORD is empty -" \
             "refusing to create an administrator without a password." >&2
        exit 1
    fi

    psql -v ON_ERROR_STOP=1 \
        --username "$POSTGRES_USER" \
        --dbname "$POSTGRES_DB" \
        --set=admin_password="$GUACAMOLE_ADMIN_PASSWORD" <<'EOSQL'

-- The administrator entity.
INSERT INTO guacamole_entity (name, type) VALUES ('guacadmin', 'USER');

-- 32 random salt bytes, then the salted hash of this deployment's password.
INSERT INTO guacamole_user (entity_id, password_hash, password_salt, password_date)
SELECT
    guacamole_entity.entity_id,
    sha256(convert_to(:'admin_password' || upper(encode(generated.salt, 'hex')), 'UTF8')),
    generated.salt,
    CURRENT_TIMESTAMP
FROM guacamole_entity
CROSS JOIN (
    SELECT decode(
        replace(gen_random_uuid()::text, '-', '') ||
        replace(gen_random_uuid()::text, '-', ''),
        'hex') AS salt
) AS generated
WHERE guacamole_entity.name = 'guacadmin'
  AND guacamole_entity.type = 'USER';

-- Grant this user all system permissions
INSERT INTO guacamole_system_permission (entity_id, permission)
SELECT entity_id, permission::guacamole_system_permission_type
FROM (
    VALUES
        ('guacadmin', 'CREATE_CONNECTION'),
        ('guacadmin', 'CREATE_CONNECTION_GROUP'),
        ('guacadmin', 'CREATE_SHARING_PROFILE'),
        ('guacadmin', 'CREATE_USER'),
        ('guacadmin', 'CREATE_USER_GROUP'),
        ('guacadmin', 'ADMINISTER')
) permissions (username, permission)
JOIN guacamole_entity ON permissions.username = guacamole_entity.name AND guacamole_entity.type = 'USER';

-- Grant admin permission to read/update/administer self
INSERT INTO guacamole_user_permission (entity_id, affected_user_id, permission)
SELECT guacamole_entity.entity_id, guacamole_user.user_id, permission::guacamole_object_permission_type
FROM (
    VALUES
        ('guacadmin', 'guacadmin', 'READ'),
        ('guacadmin', 'guacadmin', 'UPDATE'),
        ('guacadmin', 'guacadmin', 'ADMINISTER')
) permissions (username, affected_username, permission)
JOIN guacamole_entity          ON permissions.username = guacamole_entity.name AND guacamole_entity.type = 'USER'
JOIN guacamole_entity affected ON permissions.affected_username = affected.name AND guacamole_entity.type = 'USER'
JOIN guacamole_user            ON guacamole_user.entity_id = affected.entity_id;

EOSQL

    echo "002-create-admin-user.sh: administrator 'guacadmin' created."
)
