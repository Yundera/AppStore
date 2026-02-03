#!/bin/bash
# Script to initialize PostgreSQL for Guacamole

echo "Starting PostgreSQL initialization..."

# Start PostgreSQL in background
docker-entrypoint.sh postgres &
PG_PID=$!

# Wait for PostgreSQL to be ready
until PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c 'SELECT 1' &>/dev/null; do
  echo 'Waiting for PostgreSQL to start...'
  sleep 2
done

# Check if database is already initialized
if ! PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c 'SELECT 1 FROM guacamole_connection_group LIMIT 1' &>/dev/null; then
  echo 'Database not initialized. Running initialization scripts...'
  
  # Run initialization scripts (they should already be downloaded by pre-install-cmd)
  if [ -f /init/001-create-schema.sql ]; then
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /init/001-create-schema.sql
  else
    echo 'Warning: Schema file not found, downloading...'
    wget -O /init/001-create-schema.sql "https://raw.githubusercontent.com/apache/guacamole-client/main/extensions/guacamole-auth-jdbc/modules/guacamole-auth-jdbc-postgresql/schema/001-create-schema.sql"
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /init/001-create-schema.sql
  fi
  
  if [ -f /init/002-create-admin-user.sql ]; then
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /init/002-create-admin-user.sql
  else
    echo 'Warning: Admin user file not found, downloading...'
    wget -O /init/002-create-admin-user.sql "https://raw.githubusercontent.com/apache/guacamole-client/main/extensions/guacamole-auth-jdbc/modules/guacamole-auth-jdbc-postgresql/schema/002-create-admin-user.sql"
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /init/002-create-admin-user.sql
  fi
  
  echo 'Database initialization complete'
else
  echo 'Database already initialized. Skipping initialization.'
fi

# Set up trap for clean shutdown
trap 'kill -TERM $PG_PID; exit 0' TERM INT

# Wait for PostgreSQL process
echo "PostgreSQL ready with PID $PG_PID"
wait $PG_PID