#!/usr/bin/env bash
# Build the tester image and run macos-initial-setup checks in Docker.
# Requires Docker with Compose v2. No host shellcheck or zsh required.
#
#   ./run.sh              # build + run
#   ./run.sh --no-build # reuse existing image (faster iteration)
#
# Host env VERBOSE=1 is passed into the container for noisier test output.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="$HERE/docker-compose.yml"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-pretty-useful-macos-setup}"
export COMPOSE_PROJECT_NAME

NO_BUILD=0
if [[ "${1:-}" == "--no-build" ]]; then
  NO_BUILD=1
  shift
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose v2 plugin is required" >&2
  exit 1
fi

cd "$HERE"

if [[ "$NO_BUILD" -eq 0 ]]; then
  echo "=== Building macos-initial-setup tester image ==="
  docker compose -f "$COMPOSE_FILE" build
else
  echo "=== Skipping image build (--no-build) ==="
fi

echo "=== Running tests in container ==="
exec docker compose -f "$COMPOSE_FILE" run --rm \
  -e "VERBOSE=${VERBOSE:-0}" \
  tester
