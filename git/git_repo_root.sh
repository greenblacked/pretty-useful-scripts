#!/usr/bin/env bash
# Print the absolute path to the current Git repository root.

set -euo pipefail

usage() {
  cat <<EOF
git_repo_root.sh - print the repository root directory

Usage:
  $(basename "$0") [--help]

Output is a single line: the absolute path from git rev-parse --show-toplevel.
Use in shell: cd "\$($(basename "$0"))"
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

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf "not inside a Git repository\n" >&2
  exit 2
fi

git rev-parse --show-toplevel
