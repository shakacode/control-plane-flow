#!/bin/sh

echo "Starting entrypoint.sh..."

wait_for_services()
{
  echo "Waiting for PostgreSQL..."

  if [ -z "$DATABASE_URL" ]; then
    echo "ERROR: DATABASE_URL must be set before waiting for PostgreSQL." >&2
    return 1
  fi

  if ! command -v pg_isready >/dev/null 2>&1; then
    echo "ERROR: pg_isready is required; install postgresql-client." >&2
    return 1
  fi

  # A TCP connection (including an empty proxy reply) does not prove PostgreSQL
  # is accepting connections. pg_isready also works before db:prepare creates
  # the application's database. Bound each probe and the overall retry count.
  attempt=1
  while [ "$attempt" -le 60 ]; do
    pg_isready -q -t 3 -d "$DATABASE_URL" >/dev/null 2>&1
    status=$?
    case "$status" in
      0) echo " - PostgreSQL is accepting connections"; return 0 ;;
      1|2) ;;
      *) echo "ERROR: PostgreSQL readiness probe failed; check DATABASE_URL and pg_isready." >&2; return 1 ;;
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
