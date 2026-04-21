#!/usr/bin/env bash
#
# old_stay_fresh.sh — legacy macOS housekeeping.
#
# Companion to stay_fresh.sh. Keeps the step/next/try reporting style from
# ~/scripts/functions so output matches other scripts in ~/scripts.
#
# Steps:
#   - refresh Quick Look + Finder caches
#   - purge inactive memory
#   - clear shell history leftovers
#   - clear ~/Library caches (incl. Xcode Archives / DerivedData)
#   - update Homebrew taps + formulae and clean caches
#   - refresh toolchains behind version managers:
#       Terraform (tfenv), Helm, Python (pyenv), Go (gvm)
#   - refresh gcloud components, print aws CLI version
#   - print free space on /
#
# Safe to run repeatedly. Missing tools are skipped with a note; one failing
# step never aborts the rest of the run.

# -e is intentionally omitted: step/next + try already propagate status, and
# we want later steps to keep running when an earlier tool is missing.
set -uo pipefail

# shellcheck source=/dev/null
. "$HOME/scripts/functions"

# Show hidden files in globs (so */.* patterns work as expected).
shopt -s dotglob

# Prompt for sudo password once, then keep it alive for the whole run.
sudo -v
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

# ---------------------------------------------------------------------------
# Generic version-manager update helper.
#
# Every tool we manage (tfenv, pyenv, gvm, helm) follows the same flow:
#   1. Is the manager/tool installed?
#   2. What version is currently active?
#   3. What's the latest version upstream?
#   4. If different, install it, switch to it, remove the old one.
#
# The pattern was duplicated 4× in the original script; this helper drops
# each tool to a few function definitions.
#
# Usage:
#   version_update <label> <have_fn> <current_fn> <latest_fn> \
#                  <install_fn> <use_fn> <remove_fn>
#
# Each *_fn is a shell function name. install/use/remove receive the target
# version as $1. All calls are best-effort: the helper itself never errors out.
# ---------------------------------------------------------------------------
version_update() {
  local label=$1 have=$2 current=$3 latest=$4 install=$5 use=$6 remove=$7
  local cur lat

  if ! "$have"; then
    printf "  %s: version manager not installed; skipping.\n" "$label"
    return 0
  fi

  cur=$("$current" 2>/dev/null || true)
  [ -n "$cur" ] || cur="none"
  lat=$("$latest" 2>/dev/null || true)

  if [ -z "$lat" ]; then
    printf "  %s: could not determine latest version; skipping.\n" "$label"
    return 0
  fi

  if [ "$cur" = "$lat" ]; then
    printf "  %s is already up-to-date: %s\n" "$label" "$cur"
    return 0
  fi

  printf "  Updating %s from %s to %s...\n" "$label" "$cur" "$lat"
  if ! "$install" "$lat"; then
    printf "  Failed to install %s %s; keeping %s.\n" "$label" "$lat" "$cur"
    return 0
  fi
  "$use" "$lat" || printf "  Warning: failed to activate %s %s.\n" "$label" "$lat"

  if [ "$cur" != "none" ] && [ "$cur" != "$lat" ]; then
    printf "  Removing old %s version: %s\n" "$label" "$cur"
    "$remove" "$cur" || printf "  Warning: failed to uninstall %s %s.\n" "$label" "$cur"
  fi
}

# ---------------------------------------------------------------------------
# Per-tool definitions (kept tiny on purpose).
# ---------------------------------------------------------------------------

# Terraform via tfenv.
tf_have()    { command -v tfenv >/dev/null 2>&1; }
tf_current() { terraform version 2>/dev/null | head -n1 | awk '{print $2}' | tr -d 'v'; }
tf_latest()  { tfenv list-remote 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1; }
tf_install() { tfenv install "$1"; }
tf_use()     { tfenv use "$1"; }
tf_remove()  { tfenv uninstall "$1"; }

# Helm: no version manager, but upstream ships an installer script that takes
# a target version. The "use" and "remove" steps are no-ops because the
# installer overwrites the single binary in-place.
helm_have()    { command -v helm >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; }
helm_current() { helm version --template '{{.Version}}' 2>/dev/null; }
helm_latest()  { curl -fsSL https://api.github.com/repos/helm/helm/releases/latest | jq -r '.tag_name'; }
helm_install() {
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
    | bash -s -- --version "$1"
}
helm_use()    { :; }
helm_remove() { :; }

# Python via pyenv. Restrict to 3.x.y so we don't downgrade to Python 2 or
# pick up free-form lines (miniconda, pypy, stackless) from pyenv's listing.
py_have()    { command -v pyenv >/dev/null 2>&1; }
py_current() { python --version 2>/dev/null | awk '{print $2}'; }
py_latest()  {
  pyenv install --list 2>/dev/null \
    | awk '{$1=$1};1' \
    | grep -E '^3\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -1
}
py_install() { pyenv install "$1"; }
py_use()     { pyenv global "$1" && pyenv rehash; }
py_remove()  { pyenv uninstall -f "$1"; }

# Go via gvm. gvm is a shell function, so source it before probing.
[ -s "$HOME/.gvm/scripts/gvm" ] && . "$HOME/.gvm/scripts/gvm"
go_have()    { command -v gvm >/dev/null 2>&1; }
go_current() { go version 2>/dev/null | awk '{print $3}' | sed 's/^go//'; }
go_latest()  { curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1 | sed 's/^go//'; }
go_install() { gvm install "go$1"; }
go_use()     { gvm use "go$1" --default; }
go_remove()  { gvm uninstall "go$1"; }

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

step "Refresh Quick Look & Finder caches"
  try qlmanage -r
  if pgrep -x Finder >/dev/null 2>&1; then
    try killall Finder
  fi
next

step "Purge inactive memory"
  try sudo /usr/sbin/purge
next

step "Clear history leftovers"
  [ -f "$HOME/.lesshst" ]       && try rm -f "$HOME/.lesshst"
  [ -f "$HOME/.mysql_history" ] && try rm -f "$HOME/.mysql_history"
next

step "Clear user caches"
  [ -d "$HOME/Library/Caches" ] \
    && try find "$HOME/Library/Caches" -mindepth 1 -delete 2>/dev/null
  if [ -d "$HOME/Library/Developer/Xcode" ]; then
    [ -d "$HOME/Library/Developer/Xcode/Archives" ] \
      && try find "$HOME/Library/Developer/Xcode/Archives" -mindepth 1 -delete 2>/dev/null
    [ -d "$HOME/Library/Developer/Xcode/DerivedData" ] \
      && try find "$HOME/Library/Developer/Xcode/DerivedData" -mindepth 1 -delete 2>/dev/null
  fi
  if command -v composer >/dev/null 2>&1; then
    try composer clearcache --quiet
  fi
next

step "Update Homebrew taps"
  output_start
  if BREW_REPO=$(brew --repo 2>/dev/null); then
    for dir in "$BREW_REPO" "$BREW_REPO"/Library/Taps/*/*; do
      [ -d "$dir/.git" ] || continue
      echo "Housekeeping $dir"
      git -C "$dir" gc --auto --prune=now 2>/dev/null || true
    done
    HOMEBREW_NO_ENV_HINTS=1 brew update --force
  else
    echo "Homebrew not installed; skipping."
  fi
  output_end
next

step "Upgrade Homebrew formulae"
  output_start
  if command -v brew >/dev/null 2>&1; then
    HOMEBREW_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1 brew upgrade || true
  else
    echo "Homebrew not installed; skipping."
  fi
  output_end
next

step "Clean Homebrew caches"
  output_start
  if command -v brew >/dev/null 2>&1; then
    brew cleanup --prune=3 -s || true
    if cache=$(brew --cache 2>/dev/null); then
      rm -rf "$cache"
    fi
    brew tap --repair || true
  else
    echo "Homebrew not installed; skipping."
  fi
  output_end
next

step "Terraform update"
  output_start
  version_update "Terraform" tf_have tf_current tf_latest tf_install tf_use tf_remove
  output_end
next

step "Helm update"
  output_start
  version_update "Helm" helm_have helm_current helm_latest helm_install helm_use helm_remove
  output_end
next

step "Python update"
  output_start
  version_update "Python" py_have py_current py_latest py_install py_use py_remove
  output_end
next

step "Go update"
  output_start
  version_update "Go" go_have go_current go_latest go_install go_use go_remove
  output_end
next

step "gcloud components update"
  output_start
  if command -v gcloud >/dev/null 2>&1; then
    gcloud version || true
    gcloud components update -q || true
    gcloud version || true
  else
    echo "gcloud not installed; skipping."
  fi
  output_end
next

step "AWS CLI version"
  output_start
  if command -v aws >/dev/null 2>&1; then
    aws --version || true
  else
    echo "aws not installed; skipping."
  fi
  output_end
next

step "Disk free on /"
  output_start
  diskutil info / | grep --color=never "Free Space" || true
  output_end
next
