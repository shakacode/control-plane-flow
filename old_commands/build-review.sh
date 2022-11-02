#!/bin/sh

# VERSION=$(date +%s)
VERSION=latest
IMAGE=${CPL_GVC}:${VERSION}

cpln image build \
  --name ${IMAGE} \
  --dockerfile ${CPL_CONFIG_PATH}/Dockerfile \
  --dir ${CPL_APP_PATH} \
  --push

# NOTE: atm, updating only app container with default workload name
cpln workload update ${CPL_REVIEW_WORKLOAD} \
  --set spec.containers.${CPL_REVIEW_WORKLOAD}.image=/org/${CPL_ORG}/image/${IMAGE} \
  --gvc ${CPL_GVC}

if [ "$VERSION" == "latest" ]; then
  cpln workload force-redeployment ${CPL_REVIEW_WORKLOAD} --gvc ${CPL_GVC}
fi
