#!/usr/bin/env bash
# stay_fresh.sh
# Keep your macOS clean and up-to-date:
#   - purge inactive memory
#   - flush DNS caches
#   - clear /Library/Caches and writable /System/Library/Caches
#   - clear ~/Library caches (Caches, Logs, Saved State, Xcode DerivedData, ...)
#   - empty ~/.Trash
#   - clean developer tool caches (npm, yarn, pnpm, pip, gem, go)
#   - prune Docker / OrbStack (images, containers, volumes, builder cache)
#   - clean Xcode extras (Archives, DeviceSupport, stale simulators)
#   - clean diagnostic / crash reports (user + system)
#   - update & upgrade Homebrew (formulae + casks) and clean up
#   - refresh dev toolchains (helm plugins, gcloud components) installed by
#     install_apps.sh / install_devtools.sh
#
# Usage:
#   ./stay_fresh.sh [--dry-run] [--yes] [--verbose]
#                   [--skip-memory] [--skip-dns] [--skip-syscaches]
#                   [--skip-usercaches] [--skip-trash] [--skip-brew]
#                   [--skip-devcaches] [--skip-docker]
#                   [--skip-xcode] [--skip-diagnostics]
#                   [--no-sudo] [--help]
#
# Exit codes:
#   0   housekeeping finished (possibly with non-fatal warnings)
#   1   one or more steps hard-failed
#   2   preflight checks failed
#   3   bad CLI arguments

set -u
set -o pipefail

# ---------------------------------------------------------------------------
# output helpers (TTY-aware colors + layout)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[1;31m'
  C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'
  C_BLUE=$'\033[1;34m'
  C_MAGENTA=$'\033[1;35m'
  C_CYAN=$'\033[1;36m'
  # Semantic colors (TTY only)
  C_CLEAN="$C_BLUE"
  C_REMOVE="$C_RED"
  USE_FANCY_CHARS=1
  # UTF-8 bytes — macOS /bin/bash is 3.2 and does not expand $'\uXXXX'; hex only.
  CHAR_HR=$'\xe2\x94\x80'        # ─ light rule
  CHAR_HR_HEAVY=$'\xe2\x95\x90'  # ═ section breaks / header chrome
  CHAR_CHEVRON=$'\xe2\x80\xba'   # › list / step marker
  CHAR_BULLET=$'\xe2\x80\xa2'    # • status prefix
  CHAR_CHECK=$'\xe2\x9c\x93'     # ✓ on / success
  CHAR_RING=$'\xe2\x97\x8b'      # ○ off / skipped
  CHAR_TREE=$'\xe2\x94\x94'      # └ sub-action
  CHAR_ROUND_TL=$'\xe2\x95\xad'  # ╭
  CHAR_ROUND_TR=$'\xe2\x95\xae'  # ╮
  CHAR_ROUND_BL=$'\xe2\x95\xaf'  # ╰
  CHAR_ROUND_BR=$'\xe2\x95\xb0'  # ╯
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_MAGENTA='' C_CYAN='' C_CLEAN='' C_REMOVE=''
  USE_FANCY_CHARS=0
  CHAR_HR=''
  CHAR_HR_HEAVY=''
  CHAR_CHEVRON='>'
  CHAR_BULLET='*'
  CHAR_CHECK='+'
  CHAR_RING='o'
  CHAR_TREE='`'
  CHAR_ROUND_TL=''
  CHAR_ROUND_TR=''
  CHAR_ROUND_BL=''
  CHAR_ROUND_BR=''
fi

OUTPUT_MODE="plain" # plain (default) | pretty
FORCE_PLAIN=0       # when 1, disable ANSI + UTF-8 chrome (used by --plain)

is_pretty() { [[ "${OUTPUT_MODE:-plain}" == "pretty" ]]; }
is_plain()  { [[ "${OUTPUT_MODE:-plain}" == "plain"  ]]; }

apply_plain_style() {
  # Ensure plain mode is stable/greppable (no ANSI, no UTF-8 chrome).
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_MAGENTA='' C_CYAN='' C_CLEAN='' C_REMOVE=''
  USE_FANCY_CHARS=0
  CHAR_HR=''
  CHAR_HR_HEAVY=''
  CHAR_CHEVRON='>'
  CHAR_BULLET='*'
  CHAR_CHECK='+'
  CHAR_RING='o'
  CHAR_TREE='-'
  CHAR_ROUND_TL=''
  CHAR_ROUND_TR=''
  CHAR_ROUND_BL=''
  CHAR_ROUND_BR=''
}

term_cols() {
  local c="${COLUMNS:-}"
  if [[ -z "$c" ]] && command -v tput >/dev/null 2>&1; then
    c="$(tput cols 2>/dev/null || true)"
  fi
  [[ -z "$c" || "$c" -lt 48 ]] && c=72
  (( c > 104 )) && c=104
  printf '%s' "$c"
}

# Repeat a single character or byte to width w (for rules and boxes).
repeat_char() {
  local ch="$1" w="$2" i s=""
  for (( i = 0; i < w; i++ )); do s+="$ch"; done
  printf '%s' "$s"
}

hr() {
  local w
  w="$(term_cols)"
  is_plain && return 0
  if (( USE_FANCY_CHARS )); then
    printf "%s%s%s\n" "$C_DIM" "$(repeat_char "$CHAR_HR" "$w")" "$C_RESET"
  else
    printf "%s%s%s\n" "$C_DIM" "$(repeat_char '-' "$w")" "$C_RESET"
  fi
}

hr_heavy() {
  local w
  w="$(term_cols)"
  is_plain && return 0
  if (( USE_FANCY_CHARS )); then
    printf "%s%s%s\n" "$C_DIM" "$(repeat_char "$CHAR_HR_HEAVY" "$w")" "$C_RESET"
  else
    printf "%s%s%s\n" "$C_DIM" "$(repeat_char '=' "$w")" "$C_RESET"
  fi
}

# macOS-like masthead (rounded bar + title + subtitle).
masthead() {
  if is_plain; then
    printf '%s\n' "stay_fresh — macOS housekeeping"
    return 0
  fi
  local w inner
  w="$(term_cols)"
  inner=$(( w - 2 ))
  printf '\n'
  if (( USE_FANCY_CHARS )); then
    printf '%s%s%s%s%s\n' "$C_DIM" "$CHAR_ROUND_TL" "$(repeat_char "$CHAR_HR" "$inner")" "$CHAR_ROUND_TR" "$C_RESET"
    printf '    %sstay_fresh%s\n' "$C_BOLD" "$C_RESET"
    printf '    %sHousekeeping for this Mac%s\n' "$C_DIM" "$C_RESET"
    printf '%s%s%s%s%s\n\n' "$C_DIM" "$CHAR_ROUND_BL" "$(repeat_char "$CHAR_HR" "$inner")" "$CHAR_ROUND_BR" "$C_RESET"
  else
    printf '%s\n\n' "${C_BOLD}stay_fresh${C_RESET} — ${C_DIM}macOS housekeeping${C_RESET}"
  fi
}

# Major section: heavy rules + inset title (System Settings–style grouping).
section() {
  if is_plain; then
    printf '\n==> %s\n' "$*"
    return 0
  fi
  printf '\n'
  hr_heavy
  printf '    %s%s%s\n' "$C_BOLD" "$*" "$C_RESET"
  hr
}

# Subsection: chevron + label.
subsection() {
  if is_plain; then
    printf '==> %s\n' "$*"
    return 0
  fi
  printf '\n    %s%s%s  %s%s%s\n' "$C_DIM" "$CHAR_CHEVRON" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"
}

bold()  { printf "%s%s%s\n" "$C_BOLD"    "$*" "$C_RESET"; }
info()  { is_plain && printf '%s\n' "$*" || printf '    %s%s%s  %s\n' "$C_BLUE" "$CHAR_BULLET" "$C_RESET" "$*"; }
ok()    { is_plain && printf '%s\n' "$*" || printf '    %s%s%s  %s\n' "$C_GREEN" "$CHAR_CHECK" "$C_RESET" "$*"; }
warn()  { is_plain && printf '%s\n' "$*" || printf '    %s%s%s  %s\n' "$C_YELLOW" "$CHAR_BULLET" "$C_RESET" "$*"; }
err()   { is_plain && printf '%s\n' "$*" 1>&2 || printf '    %s%s%s  %s\n' "$C_RED" "$CHAR_BULLET" "$C_RESET" "$*" 1>&2; }
step()  {
  if is_plain; then
    printf '==> %s\n' "$*"
    return 0
  fi
  printf '\n    %s%s%s  %s%s%s\n' "$C_CYAN" "$CHAR_CHEVRON" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"
}

# Aligned key / value for summaries (inset like a preferences panel).
kv_line() {
  if is_plain; then
    printf '%s: %s\n' "$1" "$2"
    return 0
  fi
  printf '    %s%-36s%s  %s\n' "$C_DIM" "$1" "$C_RESET" "$2"
}

# ---------------------------------------------------------------------------
# defaults / CLI parsing
# ---------------------------------------------------------------------------
DRY_RUN=0
ASSUME_YES=0
VERBOSE=0
USE_SUDO=1

SKIP_MEMORY=0
SKIP_DNS=0
SKIP_SYSCACHES=0
SKIP_USERCACHES=0
SKIP_TRASH=0
SKIP_BREW=0
SKIP_DEVCACHES=0
SKIP_DEVTOOLS=0
SKIP_HELM_PLUGINS=0
SKIP_GCLOUD=0
SKIP_VERSIONS=0
SKIP_DOCKER=0
SKIP_XCODE=0
SKIP_DIAGNOSTICS=0
BREW_GREEDY=0

LOG_DIR="${TMPDIR:-/tmp}"
LOG_ENABLED=0
LOG_FILE=""
LOG_ERR_TARGET="/dev/null"

# step accounting
STEPS_OK=()
STEPS_WARN=()
STEPS_FAIL=()
STEPS_SKIP=()

# accumulated bytes freed (best-effort, measured by clear_dir / step helpers).
# STEP_FREED_B is reset per step by do_step; TOTAL_FREED_B is the sum across steps.
STEP_FREED_B=0
TOTAL_FREED_B=0
# Count of non-zero run_cmd invocations in the current step. Reset by do_step.
STEP_WARN_COUNT=0
# Marks whether a step performed a “cleanup” action (for blue "cleaned" label).
STEP_CLEANED=0

usage() {
  cat <<EOF
${C_BOLD}stay_fresh.sh${C_RESET} — macOS housekeeping in one script.

${C_BOLD}Usage:${C_RESET}
  $(basename "$0") [options]

${C_BOLD}General options:${C_RESET}
  --pretty               Decorated UI (current style). Default is plain.
  --plain                Force plain output (no color/UTF-8 chrome)
  --log-file <path>      Write a log file to <path> (default: no log file)
  --no-log               Disable file logging (default)
  --dry-run              Preview actions, change nothing
  --yes, -y              Don't prompt for confirmation
  --verbose, -v          Stream command output to terminal
  --no-sudo              Skip steps that require sudo
  --help, -h             Show this help

${C_BOLD}Step toggles (skip individual steps):${C_RESET}
  --skip-memory          Don't run 'sudo purge'
  --skip-dns             Don't flush DNS caches
  --skip-syscaches       Don't touch /Library/Caches or /System/Library/Caches
  --skip-usercaches      Don't clear ~/Library/Caches et al.
  --skip-trash           Don't empty ~/.Trash
  --skip-brew            Don't run 'brew update/upgrade/cleanup'
  --brew-greedy          Also upgrade casks with 'auto_updates true' / 'version :latest'
                         (may prompt for sudo during cask postinstalls)
  --skip-devcaches       Don't clean npm/yarn/pnpm/pip/gem/go caches
  --skip-devtools        Shorthand: skip all dev-tool refresh steps below
                         (--skip-helm-plugins --skip-gcloud --skip-versions)
  --skip-helm-plugins    Don't run 'helm plugin update' for installed plugins
  --skip-gcloud          Don't run 'gcloud components update'
  --skip-versions        Don't print active pyenv/goenv/tfenv/tenv/helm/gcloud
                         versions
  --skip-docker          Don't prune Docker / OrbStack
  --skip-xcode           Don't clean Xcode Archives/DeviceSupport/simulators
  --skip-diagnostics     Don't remove crash / diagnostic reports

Log file: $LOG_FILE
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --pretty)          OUTPUT_MODE="pretty" ;;
    --plain)           OUTPUT_MODE="plain"; FORCE_PLAIN=1 ;;
    --log-file)
      shift
      [[ $# -gt 0 ]] || { err "--log-file requires a path"; echo; usage; exit 3; }
      LOG_ENABLED=1
      LOG_FILE="$1"
      ;;
    --no-log)
      LOG_ENABLED=0
      LOG_FILE=""
      ;;
    --dry-run)         DRY_RUN=1 ;;
    -y|--yes)          ASSUME_YES=1 ;;
    -v|--verbose)      VERBOSE=1 ;;
    --no-sudo)         USE_SUDO=0 ;;
    --skip-memory)     SKIP_MEMORY=1 ;;
    --skip-dns)        SKIP_DNS=1 ;;
    --skip-syscaches)  SKIP_SYSCACHES=1 ;;
    --skip-usercaches) SKIP_USERCACHES=1 ;;
    --skip-trash)      SKIP_TRASH=1 ;;
    --skip-brew)       SKIP_BREW=1 ;;
    --brew-greedy)     BREW_GREEDY=1 ;;
    --skip-devcaches)  SKIP_DEVCACHES=1 ;;
    --skip-devtools)   SKIP_DEVTOOLS=1 ;;
    --skip-helm-plugins) SKIP_HELM_PLUGINS=1 ;;
    --skip-gcloud)     SKIP_GCLOUD=1 ;;
    --skip-versions)   SKIP_VERSIONS=1 ;;
    --skip-docker)     SKIP_DOCKER=1 ;;
    --skip-xcode)      SKIP_XCODE=1 ;;
    --skip-diagnostics)SKIP_DIAGNOSTICS=1 ;;
    -h|--help)         usage; exit 0 ;;
    *)                 err "unknown option: $1"; echo; usage; exit 3 ;;
  esac
  shift
done

# Apply output styling overrides after argument parsing.
if (( FORCE_PLAIN )); then
  apply_plain_style
fi

if (( LOG_ENABLED )); then
  LOG_ERR_TARGET="$LOG_FILE"
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  : > "$LOG_FILE" || { err "cannot write log file: $LOG_FILE"; exit 2; }
fi

# --skip-devtools is a convenience; fan it out across the individual
# dev-tool refresh steps so the plan/summary accurately reflects what runs.
if (( SKIP_DEVTOOLS )); then
  SKIP_HELM_PLUGINS=1
  SKIP_GCLOUD=1
  SKIP_VERSIONS=1
fi

# ---------------------------------------------------------------------------
# utility helpers
# ---------------------------------------------------------------------------
human_duration() {
  local s="$1"
  if (( s < 60 )); then printf "%ds" "$s"
  else printf "%dm%02ds" $((s/60)) $((s%60))
  fi
}

# Convert a byte delta to a signed human-readable size (KB/MB/GB).
human_bytes() {
  local b="$1" sign=""
  if (( b < 0 )); then sign="-"; b=$(( -b )); fi
  if   (( b >= 1073741824 )); then printf "%s%.2fG" "$sign" "$(awk -v b="$b" 'BEGIN{printf "%.2f", b/1073741824}')"
  elif (( b >= 1048576    )); then printf "%s%.2fM" "$sign" "$(awk -v b="$b" 'BEGIN{printf "%.2f", b/1048576}')"
  elif (( b >= 1024       )); then printf "%s%.2fK" "$sign" "$(awk -v b="$b" 'BEGIN{printf "%.2f", b/1024}')"
  else                            printf "%s%dB"    "$sign" "$b"
  fi
}

# Disk free in bytes on /.
disk_free_bytes() {
  # df -k prints 1024-byte blocks
  df -k / | awk 'NR==2 {printf "%.0f", $4 * 1024}'
}

# Size of a path in bytes (0 if missing). Best-effort (ignores permission errors).
path_bytes() {
  local p="$1"
  [[ -e "$p" ]] || { echo 0; return; }
  du -sk "$p" 2>/dev/null | awk '{printf "%.0f", $1 * 1024}'
}

# Run a command; honor --dry-run and --verbose; log output to $LOG_FILE.
# Prints the human label so the console matches the log. Bumps STEP_WARN_COUNT
# on a non-zero exit so do_step can route to OK/WARN/FAIL accurately.
# Usage: run_cmd "human label" cmd args...
run_cmd() {
  local label="$1"; shift
  if (( DRY_RUN )); then
    if is_plain; then
      printf '    (dry-run) %s  # %s\n' "$*" "$label"
    else
      printf '        %s(dry-run)%s  %s  %s%s\n' \
        "$C_DIM" "$C_RESET" "$*" "$C_DIM" "$label" "$C_RESET"
    fi
    return 0
  fi
  if ! is_plain; then
    printf '        %s%s%s  %s\n' "$C_DIM" "$CHAR_TREE" "$C_CYAN" "$label$C_RESET"
  fi
  if (( LOG_ENABLED )); then
    echo "# $(date '+%H:%M:%S') [$label] >> $*" >>"$LOG_FILE"
  fi
  local rc=0
  if (( VERBOSE )); then
    if (( LOG_ENABLED )); then
      "$@" 2>&1 | tee -a "$LOG_FILE"
      rc="${PIPESTATUS[0]}"
    else
      "$@"
      rc=$?
    fi
  else
    if (( LOG_ENABLED )); then
      "$@" >>"$LOG_FILE" 2>&1
      rc=$?
    else
      "$@" >/dev/null 2>&1
      rc=$?
    fi
  fi
  if (( rc != 0 )); then
    STEP_WARN_COUNT=$(( STEP_WARN_COUNT + 1 ))
  fi
  return "$rc"
}

# Like run_cmd, but keeps the command attached to the controlling TTY so
# interactive prompts (e.g. sudo password, cask installer UI) are visible and
# answerable. Output is still teed to the log file.
# Usage: run_cmd_tty "human label" cmd args...
run_cmd_tty() {
  local label="$1"; shift
  if (( DRY_RUN )); then
    if is_plain; then
      printf '    (dry-run) %s  # %s\n' "$*" "$label"
    else
      printf '        %s(dry-run)%s  %s  %s%s\n' \
        "$C_DIM" "$C_RESET" "$*" "$C_DIM" "$label" "$C_RESET"
    fi
    return 0
  fi
  if ! is_plain; then
    printf '        %s%s%s  %s\n' "$C_DIM" "$CHAR_TREE" "$C_CYAN" "$label$C_RESET"
  fi
  if (( LOG_ENABLED )); then
    echo "# $(date '+%H:%M:%S') [$label] >> $*" >>"$LOG_FILE"
  fi
  local rc=0
  if [[ -r /dev/tty && -w /dev/tty ]]; then
    if (( LOG_ENABLED )); then
      "$@" </dev/tty 2>&1 | tee -a "$LOG_FILE"
      rc="${PIPESTATUS[0]}"
    else
      "$@" </dev/tty
      rc=$?
    fi
  else
    if (( LOG_ENABLED )); then
      "$@" 2>&1 | tee -a "$LOG_FILE"
      rc="${PIPESTATUS[0]}"
    else
      "$@"
      rc=$?
    fi
  fi
  if (( rc != 0 )); then
    STEP_WARN_COUNT=$(( STEP_WARN_COUNT + 1 ))
  fi
  return "$rc"
}

# Clear contents of a directory (not the dir itself), with before/after size.
# Uses sudo if $2 == "sudo".
# Usage: clear_dir <path> [sudo]
clear_dir() {
  local dir="$1" use_sudo="${2:-}" before_b after_b delta
  STEP_CLEANED=1
  # Safety rails: refuse obviously dangerous targets.
  if [[ -z "${dir:-}" || "$dir" == "/" || "$dir" == "$HOME" ]]; then
    warn "refusing to clear unsafe path: '${dir:-<empty>}'"
    STEP_WARN_COUNT=$(( STEP_WARN_COUNT + 1 ))
    return 1
  fi
  if [[ ! -d "$dir" ]]; then
    if ! is_plain || (( DRY_RUN )) || (( VERBOSE )); then
      printf '        %s%s%s  %s (missing)%s\n' "$C_DIM" "$CHAR_BULLET" "$C_RESET" "$dir" "$C_RESET"
    fi
    return 0
  fi
  before_b="$(path_bytes "$dir")"
  if ! is_plain || (( DRY_RUN )) || (( VERBOSE )); then
    printf '        %s%s%s  %s  %s(%s)%s\n' "$C_DIM" "$CHAR_BULLET" "$C_RESET" "$dir" "$C_DIM" "$(human_bytes "$before_b")" "$C_RESET"
  fi
  if (( DRY_RUN )); then
    if is_plain; then
      printf '    (dry-run) would clear %s\n' "$dir"
    else
      printf '        %s(dry-run)%s  would clear %s\n' "$C_DIM" "$C_RESET" "$dir"
    fi
    return 0
  fi
  if (( LOG_ENABLED )); then
    echo "# $(date '+%H:%M:%S') [clear_dir] $dir (sudo=${use_sudo:-no})" >>"$LOG_FILE"
  fi
  if [[ "$use_sudo" == "sudo" ]]; then
    sudo find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>>"$LOG_ERR_TARGET" || true
  else
    find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>>"$LOG_ERR_TARGET" || true
  fi
  after_b="$(path_bytes "$dir")"
  delta=$(( before_b - after_b ))
  (( delta > 0 )) && STEP_FREED_B=$(( STEP_FREED_B + delta ))
  if ! is_plain || (( VERBOSE )); then
    if (( USE_FANCY_CHARS )); then
      printf '        %s%s%s  freed %s  %s%s%s\n' "$C_GREEN" "$CHAR_CHECK" "$C_RESET" "$(human_bytes "$delta")" "$C_DIM" "$dir" "$C_RESET"
    else
      printf '        %s->%s freed %s from %s\n' "$C_GREEN" "$C_RESET" "$(human_bytes "$delta")" "$dir"
    fi
  fi
}

# ---------------------------------------------------------------------------
# preflight checks
# ---------------------------------------------------------------------------
masthead

section "Preflight"

if (( LOG_ENABLED )); then
  echo "stay_fresh.sh log - $(date)" >> "$LOG_FILE"
  info "log file: $C_DIM$LOG_FILE$C_RESET"
fi

# 1. macOS only
if [[ "$(uname -s)" != "Darwin" ]]; then
  err "This script is for macOS only (detected: $(uname -s))."
  exit 2
fi
OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo '?')"
OS_BUILD="$(sw_vers -buildVersion   2>/dev/null || echo '?')"
ARCH="$(uname -m)"
ok "macOS $OS_VERSION ($OS_BUILD) on $ARCH"

# 2. Not root
if [[ "$(id -u)" == "0" ]]; then
  err "Do NOT run stay_fresh.sh as root. Run as a normal user; it will ask for sudo."
  exit 2
fi
ok "running as user: $(id -un)"

# 3. Disk free before
FREE_BEFORE_B="$(disk_free_bytes)"
ok "disk free on /: $(human_bytes "$FREE_BEFORE_B")"

# 4. Homebrew check (only relevant if we aren't skipping it)
if (( SKIP_BREW == 0 )); then
  if command -v brew >/dev/null 2>&1; then
    ok "$(brew --version | head -n1) (prefix: $(brew --prefix))"
  else
    warn "Homebrew not installed — brew step will be skipped"
    SKIP_BREW=1
    STEPS_SKIP+=("brew (not installed)")
  fi
fi

# 4b. Docker check — auto-skip if no docker CLI
if (( SKIP_DOCKER == 0 )); then
  if ! command -v docker >/dev/null 2>&1; then
    info "Docker CLI not found — docker-prune step will be skipped"
    SKIP_DOCKER=1
  elif ! docker info >/dev/null 2>&1; then
    warn "Docker CLI present but daemon unreachable — docker-prune step will be skipped"
    SKIP_DOCKER=1
  else
    ok "Docker daemon reachable"
  fi
fi

# 4c. Xcode check — auto-skip if no ~/Library/Developer/Xcode and no xcrun simctl
if (( SKIP_XCODE == 0 )); then
  if [[ ! -d "$HOME/Library/Developer/Xcode" ]] && ! command -v xcrun >/dev/null 2>&1; then
    info "No Xcode data found — xcode-extras step will be skipped"
    SKIP_XCODE=1
  fi
fi

# 5. sudo availability
SUDO_AVAILABLE=0
NEEDS_SUDO=0
(( SKIP_MEMORY      == 0 )) && NEEDS_SUDO=1
(( SKIP_DNS         == 0 )) && NEEDS_SUDO=1
(( SKIP_SYSCACHES   == 0 )) && NEEDS_SUDO=1
(( SKIP_DIAGNOSTICS == 0 )) && NEEDS_SUDO=1

if (( USE_SUDO == 0 )); then
  warn "--no-sudo set: memory purge, DNS flush, system caches, and system diagnostics will be skipped"
  SKIP_MEMORY=1
  SKIP_DNS=1
  SKIP_SYSCACHES=1
  SKIP_DIAGNOSTICS_SYS=1
  NEEDS_SUDO=0
fi

if (( NEEDS_SUDO == 1 )) && (( DRY_RUN == 0 )); then
  info "some steps need sudo — you may be prompted once"
  if sudo -v; then
    SUDO_AVAILABLE=1
    ok "sudo authenticated"
    # keep-alive (disown so EXIT kill does not print bash job "Terminated: 15" noise)
    ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
    disown "$SUDO_KEEPALIVE_PID" 2>/dev/null || disown || true
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
          wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
  else
    err "sudo authentication failed — disabling sudo-requiring steps"
    SKIP_MEMORY=1
    SKIP_DNS=1
    SKIP_SYSCACHES=1
    SKIP_DIAGNOSTICS_SYS=1
  fi
elif (( DRY_RUN )); then
  info "(dry-run) would request sudo for memory/DNS/system-caches/diagnostics steps"
fi

SKIP_DIAGNOSTICS_SYS="${SKIP_DIAGNOSTICS_SYS:-0}"

# ---------------------------------------------------------------------------
# plan + confirmation
# ---------------------------------------------------------------------------
subsection "What will run"
plan_line() {
  local name="$1" active="$2" extra="${3:-}"
  if is_plain; then
    if (( active )); then
      printf '    - %s%s\n' "$name" "${extra:+ ($extra)}"
    else
      printf '    - %s (skip)\n' "$name"
    fi
    return 0
  fi
  if (( active )); then
    printf '        %s  %-38s  %s%-3s%s %s\n' "$CHAR_CHECK" "$name" "$C_GREEN" "On" "$C_RESET" "$extra"
  else
    printf '        %s  %-38s  %s%-3s%s %s\n' "$CHAR_RING" "$name" "$C_DIM" "Off" "$C_RESET" "$extra"
  fi
}
plan_line "purge inactive memory"             "$(( 1 - SKIP_MEMORY      ))" "sudo purge"
plan_line "flush DNS cache"                   "$(( 1 - SKIP_DNS         ))" "dscacheutil + mDNSResponder"
plan_line "clear system caches"               "$(( 1 - SKIP_SYSCACHES   ))" "/Library/Caches, /System/Library/Caches"
plan_line "clear user caches"                 "$(( 1 - SKIP_USERCACHES  ))" "~/Library/Caches, Logs, DerivedData, ..."
plan_line "empty trash"                       "$(( 1 - SKIP_TRASH       ))" "~/.Trash"
plan_line "dev-tool caches"                   "$(( 1 - SKIP_DEVCACHES   ))" "npm/yarn/pnpm/pip/gem/go"
plan_line "docker / orbstack prune"           "$(( 1 - SKIP_DOCKER      ))" "images, containers, volumes, builder"
plan_line "xcode extras"                      "$(( 1 - SKIP_XCODE       ))" "Archives, DeviceSupport, simulators"
plan_line "diagnostic / crash reports"        "$(( 1 - SKIP_DIAGNOSTICS ))" "user (+ system if sudo)"
plan_line "homebrew update/upgrade/cleanup"   "$(( 1 - SKIP_BREW        ))"
plan_line "helm plugin refresh"               "$(( 1 - SKIP_HELM_PLUGINS))" "helm plugin update <name>"
plan_line "gcloud components update"          "$(( 1 - SKIP_GCLOUD      ))" "non-brew gcloud components"
plan_line "report active versions"            "$(( 1 - SKIP_VERSIONS    ))" "pyenv/goenv/tfenv/tenv/helm/gcloud"
hr

if (( DRY_RUN )); then
  printf '\n    %sDry run — nothing will be changed.%s\n\n' "$C_YELLOW$C_BOLD" "$C_RESET"
fi

if (( ASSUME_YES == 0 )) && (( DRY_RUN == 0 )); then
  if [[ ! -t 0 ]]; then
    info "non-interactive stdin — auto-proceeding (use --yes to silence)"
  else
    printf '\n    %sContinue?%s  [y/N] ' "$C_BOLD" "$C_RESET"
    read -r answer
    case "$answer" in
      y|Y|yes|YES) ;;
      *) warn "aborted by user"; exit 0 ;;
    esac
  fi
fi

# ---------------------------------------------------------------------------
# step wrapper
# ---------------------------------------------------------------------------
# Usage: do_step "Label" step_function
#   rc != 0                      -> STEPS_FAIL
#   rc == 0 && STEP_WARN_COUNT>0 -> STEPS_WARN
#   otherwise                    -> STEPS_OK
# Appends per-step bytes freed to the bookkeeping entry when > 0.
do_step() {
  local label="$1" fn="$2" t_start t_end rc=0 dur freed_str="" entry
  STEP_WARN_COUNT=0
  STEP_FREED_B=0
  STEP_CLEANED=0
  t_start=$(date +%s)
  if "$fn"; then rc=0; else rc=$?; fi
  t_end=$(date +%s)
  dur="$(human_duration $(( t_end - t_start )))"
  if (( STEP_FREED_B > 0 )); then
    freed_str=" · freed $(human_bytes "$STEP_FREED_B")"
    TOTAL_FREED_B=$(( TOTAL_FREED_B + STEP_FREED_B ))
  fi
  entry="$label  (${dur}${freed_str})"
  if (( rc != 0 )); then
    if is_plain; then
      printf '==> %s  FAIL (%s)\n' "$label" "$dur"
    else
      err "$label failed in $dur$freed_str — see log"
    fi
    STEPS_FAIL+=("$entry")
  elif (( STEP_WARN_COUNT > 0 )); then
    if is_plain; then
      local extra=""
      if (( STEP_CLEANED )); then
        extra="${extra}${extra:+, }${C_CLEAN}cleaned${C_RESET}"
      fi
      if (( STEP_FREED_B > 0 )); then
        extra="${extra}${extra:+, }${C_REMOVE}removed $(human_bytes "$STEP_FREED_B")${C_RESET}"
      fi
      [[ -n "$extra" ]] && extra=", $extra"
      printf '==> %s  WARN (%s%s)\n' "$label" "$dur" "$extra"
    else
      warn "$label finished with $STEP_WARN_COUNT warning(s) in $dur$freed_str — see log"
    fi
    STEPS_WARN+=("$entry")
  else
    if is_plain; then
      local extra=""
      if (( STEP_CLEANED )); then
        extra="${extra}${extra:+, }${C_CLEAN}cleaned${C_RESET}"
      fi
      if (( STEP_FREED_B > 0 )); then
        extra="${extra}${extra:+, }${C_REMOVE}removed $(human_bytes "$STEP_FREED_B")${C_RESET}"
      fi
      [[ -n "$extra" ]] && extra=", $extra"
      printf '==> %s  OK (%s%s)\n' "$label" "$dur" "$extra"
    else
      ok "$label done in $dur$freed_str"
    fi
    STEPS_OK+=("$entry")
  fi
}

# ---------------------------------------------------------------------------
# steps
# ---------------------------------------------------------------------------
step_memory() {
  STEP_CLEANED=0
  run_cmd "purge memory" sudo purge
}

step_dns() {
  STEP_CLEANED=0
  run_cmd "flush DNS"            sudo dscacheutil -flushcache
  run_cmd "reload mDNSResponder" sudo killall -HUP mDNSResponder
}

step_syscaches() {
  STEP_CLEANED=1
  clear_dir "/Library/Caches"        sudo
  if [[ -d /System/Library/Caches ]]; then
    if ! is_plain || (( DRY_RUN )) || (( VERBOSE )); then
      printf '        %s%s%s  /System/Library/Caches (writable entries only)\n' "$C_DIM" "$CHAR_BULLET" "$C_RESET"
    fi
    if (( DRY_RUN == 0 )); then
      sudo find /System/Library/Caches -mindepth 1 -maxdepth 2 -writable -exec rm -rf {} + 2>>"$LOG_FILE" || true
    else
      if is_plain; then
        printf '    (dry-run) would clear writable entries in /System/Library/Caches\n'
      else
        printf '        %s(dry-run)%s  would clear writable entries in /System/Library/Caches\n' "$C_DIM" "$C_RESET"
      fi
    fi
  fi
}

step_usercaches() {
  STEP_CLEANED=1
  local targets=(
    "$HOME/Library/Caches"
    "$HOME/Library/Logs"
    "$HOME/Library/Saved Application State"
    "$HOME/Library/Developer/Xcode/DerivedData"
    "$HOME/Library/Application Support/Caches"
  )
  for d in "${targets[@]}"; do
    clear_dir "$d"
  done
}

step_trash() {
  STEP_CLEANED=1
  local trash="$HOME/.Trash"
  if [[ ! -d "$trash" ]]; then
    warn "~/.Trash not found"
    return 0
  fi
  clear_dir "$trash"
}

step_devcaches() {
  STEP_CLEANED=1
  local any=0

  if command -v npm >/dev/null 2>&1; then
    any=1
    local d="$HOME/.npm"
    if ! is_plain || (( DRY_RUN )) || (( VERBOSE )); then
      printf '        %s%s%s  npm cache  %s(%s)%s\n' "$C_DIM" "$CHAR_BULLET" "$C_RESET" "$C_DIM" "$(human_bytes "$(path_bytes "$d")")" "$C_RESET"
    fi
    run_cmd "npm cache clean --force" npm cache clean --force || warn "'npm cache clean' failed"
  fi

  if command -v yarn >/dev/null 2>&1; then
    any=1
    local d="$HOME/Library/Caches/Yarn"
    if ! is_plain || (( DRY_RUN )) || (( VERBOSE )); then
      printf '        %s%s%s  yarn cache  %s(%s)%s\n' "$C_DIM" "$CHAR_BULLET" "$C_RESET" "$C_DIM" "$(human_bytes "$(path_bytes "$d")")" "$C_RESET"
    fi
    run_cmd "yarn cache clean" yarn cache clean || warn "'yarn cache clean' failed"
  fi

  if command -v pnpm >/dev/null 2>&1; then
    any=1
    run_cmd "pnpm store prune" pnpm store prune || warn "'pnpm store prune' failed"
  fi

  if command -v pip3 >/dev/null 2>&1; then
    any=1
    run_cmd "pip3 cache purge" pip3 cache purge || warn "'pip3 cache purge' failed"
  elif command -v pip >/dev/null 2>&1; then
    any=1
    run_cmd "pip cache purge" pip cache purge || warn "'pip cache purge' failed"
  fi

  if command -v gem >/dev/null 2>&1; then
    any=1
    run_cmd "gem cleanup" gem cleanup || warn "'gem cleanup' failed"
  fi

  if command -v go >/dev/null 2>&1; then
    any=1
    run_cmd "go clean -cache -modcache -testcache" go clean -cache -modcache -testcache \
      || warn "'go clean' failed"
  fi

  if command -v cargo >/dev/null 2>&1 && command -v cargo-cache >/dev/null 2>&1; then
    any=1
    run_cmd "cargo cache --autoclean" cargo cache --autoclean || warn "'cargo cache' failed"
  fi

  if (( any == 0 )); then
    info "no known developer toolchains found — nothing to do"
  fi
}

step_docker() {
  STEP_CLEANED=1
  if ! command -v docker >/dev/null 2>&1; then
    warn "docker not on PATH"
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    warn "docker daemon not reachable"
    return 1
  fi

  # Size before
  local before
  before="$(docker system df --format '{{.Type}}\t{{.Size}}' 2>/dev/null | awk -F'\t' '{print $1": "$2}' | paste -sd ', ' - || echo 'unknown')"
  if ! is_plain || (( DRY_RUN )) || (( VERBOSE )); then
    printf '        %s%s%s  docker disk usage: %s%s%s\n' "$C_DIM" "$CHAR_BULLET" "$C_RESET" "$C_DIM" "$before" "$C_RESET"
  fi

  run_cmd "docker system prune -af --volumes" docker system prune -af --volumes \
    || warn "'docker system prune' failed"
  run_cmd "docker builder prune -af"          docker builder prune -af \
    || warn "'docker builder prune' failed"
}

step_xcode() {
  STEP_CLEANED=1
  local any=0
  local targets=(
    "$HOME/Library/Developer/Xcode/Archives"
    "$HOME/Library/Developer/Xcode/iOS DeviceSupport"
    "$HOME/Library/Developer/Xcode/watchOS DeviceSupport"
    "$HOME/Library/Developer/Xcode/tvOS DeviceSupport"
    "$HOME/Library/Developer/CoreSimulator/Caches"
  )
  for d in "${targets[@]}"; do
    if [[ -d "$d" ]]; then
      any=1
      clear_dir "$d"
    fi
  done

  if command -v xcrun >/dev/null 2>&1 && xcrun simctl help >/dev/null 2>&1; then
    any=1
    run_cmd "xcrun simctl delete unavailable" xcrun simctl delete unavailable \
      || warn "'simctl delete unavailable' failed"
  fi

  if (( any == 0 )); then
    info "no Xcode data to clean"
  fi
}

step_diagnostics() {
  STEP_CLEANED=1
  # User diagnostic / crash reports
  local user_dirs=(
    "$HOME/Library/Logs/DiagnosticReports"
    "$HOME/Library/DiagnosticReports"
  )
  for d in "${user_dirs[@]}"; do
    clear_dir "$d"
  done

  # System diagnostic reports (sudo)
  if (( SKIP_DIAGNOSTICS_SYS == 0 )); then
    local sys_dirs=(
      "/Library/Logs/DiagnosticReports"
      "/Library/Logs/CrashReporter"
    )
    for d in "${sys_dirs[@]}"; do
      clear_dir "$d" sudo
    done
  else
    info "skipping system diagnostic reports (--no-sudo or sudo unavailable)"
  fi
}

step_brew() {
  STEP_CLEANED=1
  if ! command -v brew >/dev/null 2>&1; then
    warn "brew not on PATH"
    return 1
  fi

  # Some casks (Docker, Karabiner, VirtualBox, ...) invoke sudo during their
  # postinstall. Re-prime the sudo timestamp right before we start so brew's
  # internal `sudo -n` calls find a valid credential.
  if (( USE_SUDO )) && (( SUDO_AVAILABLE )) && (( DRY_RUN == 0 )); then
    sudo -v 2>/dev/null || true
  fi

  # Avoid brew kicking off an extra `brew update` under each subcommand —
  # we call it explicitly below.
  export HOMEBREW_NO_AUTO_UPDATE=1
  # Make cask installs less chatty and less likely to open GUIs mid-run.
  export HOMEBREW_NO_ENV_HINTS=1

  run_cmd     "brew update"         brew update    || warn "'brew update' had issues"
  # Cask upgrades may prompt for sudo; run attached to the TTY so the prompt
  # is visible and the user can answer it.
  run_cmd_tty "brew upgrade"        brew upgrade   || warn "'brew upgrade' had issues"

  if (( BREW_GREEDY )); then
    run_cmd_tty "brew upgrade --cask --greedy" brew upgrade --cask --greedy \
      || warn "'brew upgrade --cask --greedy' had issues"
  else
    run_cmd_tty "brew upgrade --cask" brew upgrade --cask \
      || warn "'brew upgrade --cask' had issues"
    info "skipping '--greedy' cask upgrades; pass --brew-greedy to include them"
  fi

  run_cmd "brew cleanup -s"        brew cleanup -s             || warn "'brew cleanup' had issues"
  run_cmd "brew autoremove"        brew autoremove             || warn "'brew autoremove' had issues"
  if (( VERBOSE )); then
    run_cmd "brew doctor" brew doctor || warn "'brew doctor' reports issues — see log"
  fi
}

# The version managers themselves (pyenv/tfenv/goenv/tenv/helm,
# gcloud-cli cask) are already upgraded by the brew step above. The steps
# below refresh what sits on top of them; each is intentionally isolated so
# it can be skipped independently (and so failures don't mask each other).
# None of them auto-install new Python/Go/Terraform majors — that's an
# explicit action best left to install_devtools.sh.

# Helm plugins are outside of brew's world, so they go stale quickly.
# 'helm plugin update <name>' pulls the latest release for each one.
step_helm_plugins() {
  STEP_CLEANED=1
  if ! command -v helm >/dev/null 2>&1; then
    info "helm not installed — nothing to refresh"
    return 0
  fi
  local plugins
  plugins="$(helm plugin list 2>/dev/null | awk 'NR>1 && NF {print $1}')"
  if [[ -z "$plugins" ]]; then
    info "no helm plugins installed — nothing to refresh"
    return 0
  fi
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    run_cmd "helm plugin update $p" helm plugin update "$p" \
      || warn "'helm plugin update $p' failed"
  done <<< "$plugins"
}

# gcloud components (e.g. gke-gcloud-auth-plugin, kubectl, beta, alpha) that
# were installed via 'gcloud components install' live under the brew-cask
# SDK dir and aren't refreshed by 'brew upgrade'. Components installed via
# brew directly are already covered by the brew step.
step_gcloud() {
  STEP_CLEANED=1
  if ! command -v gcloud >/dev/null 2>&1; then
    info "gcloud not installed — nothing to refresh"
    return 0
  fi
  # Some gcloud builds disable the in-place component manager (e.g. when
  # installed from a distro package); in that case there's nothing to do.
  if ! gcloud components list --quiet >/dev/null 2>&1; then
    info "gcloud present but component manager unavailable — skipping components update"
    return 0
  fi
  run_cmd "gcloud components update --quiet" gcloud components update --quiet \
    || warn "'gcloud components update' had issues"
}

# Report currently-active managed versions so the user can see what's in use.
# Read-only: these tools don't self-update their installed language versions;
# the brew step keeps the managers fresh, re-run install_devtools.sh to move
# to a new Python/Go/Terraform minor.
step_versions() {
  STEP_CLEANED=0
  local any=0 line
  if command -v pyenv >/dev/null 2>&1; then
    any=1
    line="$(pyenv version-name 2>/dev/null || echo '?')"
    printf '        %s%s%s  pyenv   %s%s%s\n' "$C_DIM" "$CHAR_BULLET" "$C_RESET" "$C_DIM" "$line" "$C_RESET"
  fi
  if command -v goenv >/dev/null 2>&1; then
    any=1
    line="$(goenv version-name 2>/dev/null || echo '?')"
    printf '        %s%s%s  goenv   %s%s%s\n' "$C_DIM" "$CHAR_BULLET" "$C_RESET" "$C_DIM" "$line" "$C_RESET"
  fi
  if command -v tfenv >/dev/null 2>&1; then
    any=1
    line="$(tfenv version-name 2>/dev/null || echo '?')"
    printf '        %s%s%s  tfenv   %s%s%s\n' "$C_DIM" "$CHAR_BULLET" "$C_RESET" "$C_DIM" "$line" "$C_RESET"
  fi
  if command -v tenv >/dev/null 2>&1; then
    any=1
    line="$(tenv tf current 2>/dev/null || echo '?')"
    printf '        %s%s%s  tenv    %s%s%s\n' "$C_DIM" "$CHAR_BULLET" "$C_RESET" "$C_DIM" "$line" "$C_RESET"
  fi
  if command -v helm >/dev/null 2>&1; then
    any=1
    line="$(helm version --short 2>/dev/null | head -n1 || echo '?')"
    printf '        %s%s%s  helm    %s%s%s\n' "$C_DIM" "$CHAR_BULLET" "$C_RESET" "$C_DIM" "$line" "$C_RESET"
  fi
  if command -v gcloud >/dev/null 2>&1; then
    any=1
    line="$(gcloud version 2>/dev/null | head -n1 || echo '?')"
    printf '        %s%s%s  gcloud  %s%s%s\n' "$C_DIM" "$CHAR_BULLET" "$C_RESET" "$C_DIM" "$line" "$C_RESET"
  fi
  if (( any == 0 )); then
    info "no dev toolchain managers found (pyenv/goenv/tfenv/tenv/helm/gcloud) — nothing to report"
  fi
}

# ---------------------------------------------------------------------------
# execute
# ---------------------------------------------------------------------------
START_ALL=$(date +%s)

run_or_skip() {
  local label="$1" skip_flag="$2" fn="$3"
  if (( skip_flag )); then
    if is_plain; then
      printf '==> %s ... SKIP\n' "$label"
    else
      step "$label"
      if (( USE_FANCY_CHARS )); then
        printf '        %s%s%s  %sSkipped%s\n' "$C_DIM" "$CHAR_RING" "$C_RESET" "$C_DIM" "$C_RESET"
      else
        printf '        %sskipped%s\n' "$C_DIM" "$C_RESET"
      fi
    fi
    STEPS_SKIP+=("$label")
    return 0
  fi
  do_step "$label" "$fn"
}

run_or_skip "Purge inactive memory"                "$SKIP_MEMORY"      step_memory
run_or_skip "Flush DNS cache"                      "$SKIP_DNS"         step_dns
run_or_skip "Clear system caches"                  "$SKIP_SYSCACHES"   step_syscaches
run_or_skip "Clear user caches"                    "$SKIP_USERCACHES"  step_usercaches
run_or_skip "Empty trash"                          "$SKIP_TRASH"       step_trash
run_or_skip "Dev-tool caches"                      "$SKIP_DEVCACHES"   step_devcaches
run_or_skip "Docker / OrbStack prune"              "$SKIP_DOCKER"      step_docker
run_or_skip "Xcode extras"                         "$SKIP_XCODE"       step_xcode
run_or_skip "Diagnostic / crash reports"           "$SKIP_DIAGNOSTICS" step_diagnostics
run_or_skip "Homebrew update / upgrade / cleanup"  "$SKIP_BREW"         step_brew
run_or_skip "Helm plugin refresh"                  "$SKIP_HELM_PLUGINS" step_helm_plugins
run_or_skip "gcloud components update"             "$SKIP_GCLOUD"       step_gcloud
run_or_skip "Active tool versions"                 "$SKIP_VERSIONS"     step_versions

ELAPSED=$(( $(date +%s) - START_ALL ))
FREE_AFTER_B="$(disk_free_bytes)"
RECLAIMED_B=$(( FREE_AFTER_B - FREE_BEFORE_B ))

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
section "Summary"

kv_line "Elapsed" "$(human_duration "$ELAPSED")"
kv_line "Disk free (before → after)" \
  "$(human_bytes "$FREE_BEFORE_B") → $(human_bytes "$FREE_AFTER_B")"
kv_line "Reclaimed (df delta)" \
  "${C_GREEN}$(human_bytes "$RECLAIMED_B")${C_RESET}"
kv_line "Freed (step totals)" \
  "${C_GREEN}$(human_bytes "$TOTAL_FREED_B")${C_RESET} ${C_DIM}(sum of per-step clears; can differ from df)${C_RESET}"

printf '\n'
kv_line "Steps OK"    "${C_GREEN}${#STEPS_OK[@]}${C_RESET}"
kv_line "Warnings"   "${C_YELLOW}${#STEPS_WARN[@]}${C_RESET}"
kv_line "Skipped"    "${C_DIM}${#STEPS_SKIP[@]}${C_RESET}"
kv_line "Failed"     "${C_RED}${#STEPS_FAIL[@]}${C_RESET}"

print_group() {
  local title="$1" color="$2" bullet="$3"; shift 3
  (( $# == 0 )) && return 0
  if is_plain; then
    printf '\n%s\n' "$title"
    for item in "$@"; do printf '  - %s\n' "$item"; done
  else
    printf '\n    %s%s%s  %s%s%s\n' "$C_DIM" "$CHAR_CHEVRON" "$C_RESET" "$color" "$title" "$C_RESET"
    for item in "$@"; do printf '        %s  %s\n' "$bullet" "$item"; done
  fi
}

if (( USE_FANCY_CHARS )); then
  (( ${#STEPS_OK[@]}   > 0 )) && print_group "Completed" "$C_GREEN"  "✓" "${STEPS_OK[@]}"
  (( ${#STEPS_WARN[@]} > 0 )) && print_group "With warnings" "$C_YELLOW" "!" "${STEPS_WARN[@]}"
  (( ${#STEPS_SKIP[@]} > 0 )) && print_group "Skipped" "$C_DIM"    "○" "${STEPS_SKIP[@]}"
  (( ${#STEPS_FAIL[@]} > 0 )) && print_group "Failed"  "$C_RED"    "✗" "${STEPS_FAIL[@]}"
else
  (( ${#STEPS_OK[@]}   > 0 )) && print_group "Completed" "$C_GREEN"  "-" "${STEPS_OK[@]}"
  (( ${#STEPS_WARN[@]} > 0 )) && print_group "With warnings" "$C_YELLOW" "!" "${STEPS_WARN[@]}"
  (( ${#STEPS_SKIP[@]} > 0 )) && print_group "Skipped" "$C_DIM"    "-" "${STEPS_SKIP[@]}"
  (( ${#STEPS_FAIL[@]} > 0 )) && print_group "Failed"  "$C_RED"    "x" "${STEPS_FAIL[@]}"
fi

echo
info "full log: $C_DIM$LOG_FILE$C_RESET"

if (( ${#STEPS_FAIL[@]} > 0 )); then
  exit 1
fi

if (( USE_FANCY_CHARS )); then
  ok "All set — you're fresh. Reboot if the system still feels sluggish."
else
  ok "You're fresh. Consider a reboot if things still feel sluggish."
fi
