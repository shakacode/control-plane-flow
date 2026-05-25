#!/bin/sh
set -e
# Runs before the main command

is_rails_server_command() {
  if [ "${1:-}" = "bundle" ] && [ "${2:-}" = "exec" ]; then
    shift 2
  fi

  # Matches generated, flag-free Thruster invocations. Hand-edited commands with
  # env prefixes or Thruster flags before rails skip generated DB prep.
  if [ "${1:-}" = "thrust" ] || [ "${1:-}" = "bin/thrust" ] || [ "${1:-}" = "./bin/thrust" ]; then
    shift
  fi

  if [ "${1:-}" = "bundle" ] && [ "${2:-}" = "exec" ]; then
    shift 2
  fi

  { [ "${1:-}" = "rails" ] || [ "${1:-}" = "bin/rails" ] || [ "${1:-}" = "./bin/rails" ]; } &&
    { [ "${2:-}" = "server" ] || [ "${2:-}" = "s" ]; }
}

# Match generated Rails server commands; workers and renderers skip DB prep.
# Generated Dockerfiles use WORKDIR /app; adjust this path if your hand-edited
# image runs the entrypoint from a different working directory.
if is_rails_server_command "$@"; then
  echo " -- Preparing database"
  ./bin/rails db:prepare
fi

echo " -- Finishing entrypoint.sh, executing command"
exec "$@"
