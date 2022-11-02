#!/bin/sh

LOCATION="${CPL_REVIEW_LOCATION:-$CPL_DEFAULT_LOCATION}"

# TODO: works for review apps only atm
IMAGE=$CPL_GVC:latest

for arg in "$@"; do
  TEMPLATE="$CPL_CONFIG_PATH/templates/$arg.yml"

  if [ -f "$TEMPLATE" ]; then
    cat "$TEMPLATE" |
      sed "s/APP_GVC/$CPL_GVC/" |
      sed "s/APP_LOCATION/$LOCATION/" |
      sed "s/APP_ORG/$CPL_ORG/" |
      sed "s/APP_IMAGE/$IMAGE/" |
      cpln apply --gvc $CPL_GVC --file -
  else
    echo "Can't find template for '$arg' at $TEMPLATE"
    exit -1
  fi
done
