#!/usr/bin/env bash
# Run Test Kitchen inside Docker. Host only needs Docker + Compose v2.
#   ./run.sh                  # kitchen list (default)
#   ./run.sh kitchen verify   # any kitchen subcommand
#   ./run.sh --rebuild ...    # force image rebuild (after Gemfile/Dockerfile change)
#   ./run.sh --shell          # drop into a bash shell inside the runner
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
COMPOSE=(docker compose -f "$ROOT/docker/docker-compose.yml")

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "docker compose v2 is required" >&2; exit 1; }

rebuild=0
shell=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild|--build) rebuild=1; shift ;;
    --shell)           shell=1;   shift ;;
    --) shift; break ;;
    *) break ;;
  esac
done

if (( rebuild )); then
  "${COMPOSE[@]}" build --pull
fi

if (( shell )); then
  exec "${COMPOSE[@]}" run --rm --entrypoint bash kitchen "$@"
fi

exec "${COMPOSE[@]}" run --rm kitchen "$@"
