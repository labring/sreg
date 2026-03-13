#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <owner> <ref_tag> <short_sha>"
  exit 1
fi

OWNER="$1"
REF_TAG="$2"
SHORT_SHA="$3"

push_manifest() {
  local image="$1"

  docker manifest create "ghcr.io/${OWNER}/${image}:${REF_TAG}" \
    "ghcr.io/${OWNER}/${image}:${REF_TAG}-amd64" \
    "ghcr.io/${OWNER}/${image}:${REF_TAG}-arm64"
  docker manifest push "ghcr.io/${OWNER}/${image}:${REF_TAG}"

  docker manifest create "ghcr.io/${OWNER}/${image}:sha-${SHORT_SHA}" \
    "ghcr.io/${OWNER}/${image}:sha-${SHORT_SHA}-amd64" \
    "ghcr.io/${OWNER}/${image}:sha-${SHORT_SHA}-arm64"
  docker manifest push "ghcr.io/${OWNER}/${image}:sha-${SHORT_SHA}"
}

push_manifest "sreg"
push_manifest "sreg-storage"
