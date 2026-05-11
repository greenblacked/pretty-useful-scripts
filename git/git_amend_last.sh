#!/usr/bin/env bash
# Amend the latest commit with staged changes (--no-edit), optionally stage all first.

set -euo pipefail

ADD_ALL=0
DRY_RUN=0

usage() {
  cat <<EOF
git_amend_last.sh - amend the last commit without changing the message

Optionally runs git add --all before amending (like folding unstaged work into
the previous commit).

Usage:
  $(basename "$0") [--add-all] [--dry-run]

Options:
  --add-all, -a   Run git add --all before amending
  --dry-run       Show what would run without changing the repository
  --help, -h      Show this help

Requires something staged after optional --add-all, or amend would be a no-op.

Exit code 4 if nothing is staged to include in the amend.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --add-all|-a)
      ADD_ALL=1
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      printf "unknown argument: %s\n" "$1" >&2
      usage
      exit 3
      ;;
    *)
      printf "unknown argument: %s\n" "$1" >&2
      usage
      exit 3
      ;;
  esac
  shift
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf "not inside a Git repository\n" >&2
  exit 2
fi

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  printf "no commits to amend\n" >&2
  exit 4
fi

if (( DRY_RUN == 1 )); then
  if (( ADD_ALL == 1 )); then
    printf "dry-run: would run: git add --all\n"
    printf "dry-run: would run: git commit --amend --no-edit\n"
    exit 0
  fi
  if git diff --cached --quiet; then
    printf "nothing staged to amend; use --add-all or stage files first\n" >&2
    exit 4
  fi
  printf "dry-run: would run: git commit --amend --no-edit\n"
  exit 0
fi

if (( ADD_ALL == 1 )); then
  git add --all
fi

if git diff --cached --quiet; then
  printf "nothing staged to amend; use --add-all or stage files first\n" >&2
  exit 4
fi

git commit --amend --no-edit
printf "amended last commit (message unchanged)\n"
