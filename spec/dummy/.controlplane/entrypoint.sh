#!/bin/sh

echo "Starting entrypoint.sh..."

wait_for_services()
{
  echo "Waiting for PostgreSQL..."

  if [ -z "$DATABASE_URL" ]; then
    echo "ERROR: DATABASE_URL must be set before waiting for PostgreSQL." >&2
    return 1
  fi

  if ! command -v ruby >/dev/null 2>&1; then
    echo "ERROR: Ruby and the pg gem are required for PostgreSQL readiness." >&2
    return 1
  fi

  # A TCP connection (including an empty proxy reply) does not prove PostgreSQL
  # is accepting connections. The app's pg gem uses the same libpq ping API as
  # pg_isready, including before db:prepare creates the database. Read the URL
  # from the existing environment so its credentials never enter process argv.
  attempt=1
  while [ "$attempt" -le 60 ]; do
    ruby -e '
      begin
        require "bundler/setup"
        require "pg"
        exit PG::Connection.ping(ENV.fetch("DATABASE_URL"), connect_timeout: 3)
      rescue LoadError, StandardError
        exit 3
      end
    ' >/dev/null 2>&1
    status=$?
    case "$status" in
      0) echo " - PostgreSQL is accepting connections"; return 0 ;;
      1|2) ;;
      *) echo "ERROR: PostgreSQL readiness probe failed; check DATABASE_URL and the Ruby pg gem." >&2; return 1 ;;
    esac
    if [ "$attempt" -eq 60 ]; then
      break
    fi
    echo " - PostgreSQL is unavailable, sleeping..."
    sleep 1
    attempt=$((attempt + 1))
  done

  echo "ERROR: PostgreSQL did not become ready after 60 attempts; check the database workload." >&2
  return 1
}

wait_for_services || exit 1

# If running the rails server then create or migrate existing database
# Note: db:prepare is also run in release.sh during deployment. This ensures
# the database is ready even if release script wasn't executed (e.g., in development).
if [ "${1}" = "./bin/rails" ] && [ "${2}" = "server" ]; then
  echo "Preparing database..."
  ./bin/rails db:prepare
fi

printf "Finishing entrypoint.sh, executing '%s'...\n" "$*"

exec "$@"
