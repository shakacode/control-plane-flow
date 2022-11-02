#!/bin/sh

export CPL_SCRIPT_PATH=$(dirname $(realpath $0))

for config in './' './..' './../..'; do
  if [ -f "$(realpath $config)/.controlplane/controlplane.config" ]; then
    export CPL_APP_PATH=$(realpath $config)
    export CPL_CONFIG_PATH=$CPL_APP_PATH/.controlplane
    export CPL_CONFIG_FILE=$CPL_CONFIG_PATH/controlplane.config
  fi
done

if [ -z "$CPL_CONFIG_FILE" ]; then
  echo "Can't find project config file. Should be in '$CONFIG_TEMPLATE'"
  exit -1
fi

export $(cat $CPL_CONFIG_FILE | grep "^[^#]" | xargs)

# special case as app may not yet exists
if [ "$2" == "setup" ]; then
  export CPL_GVC="$1"
  shift
  shift
  "$CPL_SCRIPT_PATH/setup.sh" "$@"
  exit
fi

# check if gvc exists
if cpln gvc query --prop name="$1" 2> /dev/null | grep -q "$1"; then
  export CPL_GVC="$1"
else
  echo "Unknown gvc (app) '$1'"
  exit -1
fi

# check if command exists and call it
if [ -f "$CPL_SCRIPT_PATH/$2.sh" ]; then
  CPL_SCRIPT_CMD=$2
  shift
  shift
  "$CPL_SCRIPT_PATH/$CPL_SCRIPT_CMD.sh" "$@"
else
  echo "Unknown command '$2', check script for available options"
fi
