#!/usr/bin/env bash
# Run Python tooling inside Docker. Host only needs Docker + Compose v2.
#
# Long-running model (fast: reuses one container, cached deps):
#   ./run.sh up                     # start/refresh the dev container in the background
#   ./run.sh pytest -q              # exec inside the running container
#   ./run.sh ruff check .
#   ./run.sh shell                  # interactive bash inside the running container
#   ./run.sh logs                   # tail container logs
#   ./run.sh down                   # stop + remove the dev container
#
# One-shot model (no persistent container):
#   ./run.sh --once pytest -q       # docker compose run --rm
#   ./run.sh --once --shell         # one-off bash
#
# Maintenance:
#   ./run.sh --rebuild              # rebuild image after pyproject/Dockerfile change
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
COMPOSE=(docker compose -f "$ROOT/docker/docker-compose.yml")
SERVICE=dev

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "docker compose v2 is required" >&2; exit 1; }

once=0
rebuild=0
shell_flag=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)            once=1;        shift ;;
    --rebuild|--build) rebuild=1;     shift ;;
    --shell)           shell_flag=1;  shift ;;
    --) shift; break ;;
    *) break ;;
  esac
done

if (( rebuild )); then
  "${COMPOSE[@]}" build --pull
fi

# Subcommands for managing the long-running container.
case "${1:-}" in
  up)
    shift || true
    exec "${COMPOSE[@]}" up -d --remove-orphans "$SERVICE"
    ;;
  down)
    shift || true
    exec "${COMPOSE[@]}" down --remove-orphans "$@"
    ;;
  logs)
    shift || true
    exec "${COMPOSE[@]}" logs -f "$SERVICE"
    ;;
  ps|status)
    exec "${COMPOSE[@]}" ps
    ;;
  shell)
    shift || true
    "${COMPOSE[@]}" up -d "$SERVICE" >/dev/null
    exec "${COMPOSE[@]}" exec "$SERVICE" bash "$@"
    ;;
esac

# One-shot path: never touches the persistent container.
if (( once )); then
  if (( shell_flag )) || [[ "${1:-}" == "" ]]; then
    exec "${COMPOSE[@]}" run --rm --entrypoint bash "$SERVICE" "$@"
  fi
  exec "${COMPOSE[@]}" run --rm "$SERVICE" "$@"
fi

# Default path: exec inside the persistent container, starting it if needed.
if ! "${COMPOSE[@]}" ps --status running --services 2>/dev/null | grep -qx "$SERVICE"; then
  "${COMPOSE[@]}" up -d "$SERVICE" >/dev/null
fi

if (( shell_flag )) || [[ $# -eq 0 ]]; then
  exec "${COMPOSE[@]}" exec "$SERVICE" bash "$@"
fi
exec "${COMPOSE[@]}" exec "$SERVICE" "$@"
