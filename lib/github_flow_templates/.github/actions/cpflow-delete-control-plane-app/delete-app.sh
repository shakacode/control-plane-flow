#!/bin/bash

set -euo pipefail

: "${APP_NAME:?APP_NAME environment variable is required}"
: "${CPLN_ORG:?CPLN_ORG environment variable is required}"

if echo "$APP_NAME" | grep -iqE '(production|staging)'; then
  echo "❌ ERROR: refusing to delete an app containing 'production' or 'staging'" >&2
  echo "App name: $APP_NAME" >&2
  exit 1
fi

echo "🔍 Checking if application exists: $APP_NAME"
if ! cpflow exists -a "$APP_NAME" --org "$CPLN_ORG"; then
  echo "⚠️ Application does not exist: $APP_NAME"
  exit 0
fi

echo "🗑️ Deleting application: $APP_NAME"
cpflow delete -a "$APP_NAME" --org "$CPLN_ORG" --yes

echo "✅ Successfully deleted application: $APP_NAME"
