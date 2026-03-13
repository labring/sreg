#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 5 ]; then
  echo "usage: $0 <binary_path> <owner> <arch> <ref_tag> <short_sha>"
  exit 1
fi

BINARY_PATH="$1"
OWNER="$2"
ARCH="$3"
REF_TAG="$4"
SHORT_SHA="$5"

if [ ! -f "$BINARY_PATH" ]; then
  echo "binary not found: $BINARY_PATH"
  exit 1
fi

cp "$BINARY_PATH" sreg
chmod +x sreg

build_and_push() {
  local image="$1"
  local dockerfile="$2"

  docker build -f "$dockerfile" \
    -t "ghcr.io/${OWNER}/${image}:${REF_TAG}-${ARCH}" \
    -t "ghcr.io/${OWNER}/${image}:sha-${SHORT_SHA}-${ARCH}" \
    .

  docker push "ghcr.io/${OWNER}/${image}:${REF_TAG}-${ARCH}"
  docker push "ghcr.io/${OWNER}/${image}:sha-${SHORT_SHA}-${ARCH}"
}

build_and_push "sreg" "Dockerfile"
build_and_push "sreg-storage" "Dockerfile.sreg-storage"
