#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 5 ] || [ "$#" -gt 6 ]; then
  echo "usage: $0 <binary_path_or_dir> <owner> <arch> <ref_tag> <short_sha> [push|no-push]"
  exit 1
fi

INPUT_PATH="$1"
OWNER="$2"
ARCH="$3"
REF_TAG="$4"
SHORT_SHA="$5"
MODE="${6:-push}"

resolve_binary_path() {
  local input="$1"
  local resolved=""

  if [ -f "$input" ]; then
    echo "$input"
    return 0
  fi

  if [ -d "$input" ]; then
    resolved="$(find "$input" -type f -name sreg | head -n 1)"
    if [ -n "$resolved" ]; then
      echo "$resolved"
      return 0
    fi
  fi

  local parent
  parent="$(dirname "$input")"
  if [ -d "$parent" ]; then
    resolved="$(find "$parent" -type f -name sreg | head -n 1)"
    if [ -n "$resolved" ]; then
      echo "$resolved"
      return 0
    fi
  fi

  return 1
}

if ! BINARY_PATH="$(resolve_binary_path "$INPUT_PATH")"; then
  echo "binary not found, input: $INPUT_PATH"
  echo "available files under dist-bin:"
  find dist-bin -maxdepth 4 -type f 2>/dev/null || true
  exit 1
fi

cp "$BINARY_PATH" sreg
chmod +x sreg

build_and_push() {
  local image="$1"
  local dockerfile="$2"
  local tag_ref="ghcr.io/${OWNER}/${image}:${REF_TAG}-${ARCH}"
  local tag_sha="ghcr.io/${OWNER}/${image}:sha-${SHORT_SHA}-${ARCH}"

  docker build -f "$dockerfile" \
    -t "$tag_ref" \
    -t "$tag_sha" \
    .

  if [ "$MODE" = "push" ]; then
    docker push "$tag_ref"
    docker push "$tag_sha"
  else
    echo "skip push for $tag_ref (mode=$MODE)"
    echo "skip push for $tag_sha (mode=$MODE)"
  fi
}

build_and_push "sreg" "Dockerfile"
build_and_push "sreg-storage" "Dockerfile.sreg-storage"
