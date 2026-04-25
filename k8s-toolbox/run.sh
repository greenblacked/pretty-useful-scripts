#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Run an interactive k8s-toolbox container locally.

Usage:
  ./k8s-toolbox/run.sh [--tag TAG] [--root] [--no-kubeconfig] [-- CMD...]

Defaults:
  TAG: k8s-toolbox:local
  CMD: bash

Notes:
  - Mounts current directory at /work.
  - Mounts ~/.kube read-only by default (can disable).
EOF
}

tag="k8s-toolbox:local"
run_as_root="false"
mount_kubeconfig="true"

cmd=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) tag="${2:?missing value}"; shift 2 ;;
    --root) run_as_root="true"; shift ;;
    --no-kubeconfig) mount_kubeconfig="false"; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; cmd+=("$@"); break ;;
    *) cmd+=("$1"); shift ;;
  esac
done

if [[ ${#cmd[@]} -eq 0 ]]; then
  cmd=("bash")
fi

args=(run --rm -it)

if [[ "${run_as_root}" == "true" ]]; then
  args+=(--user 0)
fi

args+=(
  -v "${PWD}:/work"
  -w /work
)

if [[ "${mount_kubeconfig}" == "true" && -d "${HOME}/.kube" ]]; then
  args+=(-v "${HOME}/.kube:/home/toolbox/.kube:ro")
fi

exec docker "${args[@]}" "${tag}" "${cmd[@]}"

