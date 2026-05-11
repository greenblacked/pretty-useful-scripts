#!/usr/bin/env bash
# Print the Git identity that applies in the current directory.

set -u
set -o pipefail

usage() {
  cat <<EOF
git_whoami.sh - show the Git identity for the current directory

Usage:
  $(basename "$0") [--help]
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi
if (( $# > 0 )); then
  printf "unknown argument: %s\n" "$1" >&2
  usage
  exit 3
fi

if ! command -v git >/dev/null 2>&1; then
  printf "git is not installed or not on PATH\n" 1>&2
  exit 2
fi

scope="global"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  scope="effective for this repository"
fi

name="$(git config --get user.name || true)"
email="$(git config --get user.email || true)"
global_name="$(git config --global --get user.name || true)"
global_email="$(git config --global --get user.email || true)"

printf "Git identity (%s):\n" "$scope"
printf "  user.name:  %s\n" "${name:-<not set>}"
printf "  user.email: %s\n" "${email:-<not set>}"

if [[ "$name" != "$global_name" || "$email" != "$global_email" ]]; then
  printf "\nGlobal fallback:\n"
  printf "  user.name:  %s\n" "${global_name:-<not set>}"
  printf "  user.email: %s\n" "${global_email:-<not set>}"
fi
