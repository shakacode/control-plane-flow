#!/bin/sh

WORKLOAD="${CPL_RUN_WORKLOAD:-$CPL_DEFAULT_WORKLOAD}"
LOCATION="${CPL_RUN_LOCATION:-$CPL_DEFAULT_LOCATION}"

ONEOFF="$WORKLOAD$(date +%s)"

function finish {
  # TODO: check if workload exists before deleting
  echo "- Deleting workload '$WORKLOAD' on '$CPL_GVC'"
  cpln workload delete $ONEOFF --gvc $CPL_GVC 2> /dev/null
}
trap finish EXIT
trap finish ERR

echo "- Cloning workload '$WORKLOAD' on '$CPL_GVC'"
cpln workload clone $WORKLOAD --name $ONEOFF --gvc $CPL_GVC > /dev/null

echo "- Wait for replica to be running"
until cpln workload get-replicas $ONEOFF --location $LOCATION --gvc $CPL_GVC 2> /dev/null \
      | grep -q $ONEOFF; do
  echo "waiting..."
  sleep 1
done

if [ -z "$1" ]; then
  echo "- Interactive replica ready, connecting"

  cpln workload connect $ONEOFF --gvc $CPL_GVC --location $LOCATION
else
  echo "- Non-interactive replica ready, executing command"

expect <<EOF
set timeout 600
spawn -noecho cpln workload connect $ONEOFF --gvc $CPL_GVC --location $LOCATION
expect "root@$ONEOFF-"
send "$@\n"
expect "root@$ONEOFF-"
EOF

  echo
fi
