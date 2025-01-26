#!/bin/sh

echo "Starting entrypoint.sh..."

wait_for_service()
{
  until curl -I -sS $1 2>&1 | grep -q "Empty reply from server"; do
    echo " - $1 is unavailable, sleeping..."
    sleep 1
  done

  echo " - $1 is available"
}

wait_for_services()
{
  echo "Waiting for services..."

  wait_for_service $(echo $DATABASE_URL | sed -e 's|^.*@||' -e 's|/.*$||')
}

wait_for_services

# If running the rails server then create or migrate existing database
# TODO: Why are migrations (db:prepare) not done in the release script?
if [ "${1}" = "./bin/rails" ] && [ "${2}" = "server" ]; then
  echo "Preparing database..."
  ./bin/rails db:prepare
fi

echo "Finishing entrypoint.sh, executing '$@'..."

exec "$@"
