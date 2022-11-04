#!/bin/sh

LOCATION="${CPL_REVIEW_LOCATION:-$CPL_DEFAULT_LOCATION}"

# TODO: works for review apps only atm
IMAGE=$CPL_GVC:latest

for arg in "$@"; do
  TEMPLATE="$CPL_CONFIG_PATH/templates/$arg.yml"

  if [ -f "$TEMPLATE" ]; then
    cat "$TEMPLATE" |
      sed "s/APP_GVC/$CPL_GVC/g" |
      sed "s/APP_LOCATION/$LOCATION/g" |
      sed "s/APP_ORG/$CPL_ORG/g" |
      sed "s/APP_IMAGE/$IMAGE/g" |
      cpln apply --gvc $CPL_GVC --org $CPL_ORG --file -
  else
    echo "Can't find template for '$arg' at $TEMPLATE"
    exit -1
  fi
done
