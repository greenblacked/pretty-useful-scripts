#!/usr/bin/env bash
# stay_fresh.sh
# Keep your macOS clean and up-to-date:
#   - purge inactive memory
#   - flush DNS caches
#   - clear /Library/Caches and writable /System/Library/Caches
#   - clear ~/Library caches (Caches, Logs, Saved State, Xcode DerivedData, ...)
#   - empty ~/.Trash
#   - clean developer tool caches (npm, yarn, pnpm, pip, gem, go, cargo)
#   - prune Docker / OrbStack (images, containers, volumes, builder cache)
#   - clean Xcode extras (Archives, DeviceSupport, stale simulators)
#   - clean diagnostic / crash reports (as user; system dirs if sudo)
#   - Homebrew: update, upgrade (formulae + casks), cleanup -s, autoremove
#     (snapshots a Brewfile beforehand when --brewfile-snapshot is set)
#   - check for pending macOS software updates (list-only by default; apply
#     with --install-updates) — result cached for 6 h to avoid repeat queries
#   - refresh App Store apps (mas), pipx, rustup, mise/asdf, VSCode/Cursor
#     extensions, helm plugins, gcloud components
#   - audit orphaned LaunchAgents (read-only)
#   - thin Time Machine local snapshots when disk is tight
#   - optionally reset Quick Look + Finder caches (--quicklook-reset)
#
# Logs & history:
#   Active log goes to $TMPDIR while running. On a clean run the log is
#   discarded; on warn/fail it is moved to ~/Library/Logs/stay_fresh/
#   (rotated, keep 10 most recent). Every completed run appends one line
#   to ~/Library/Logs/stay_fresh/history.csv. The previous run's outcome
#   is summarised at startup.
#
# Config:
#   Defaults can be set in $XDG_CONFIG_HOME/stay_fresh/config (or
#   ~/.config/stay_fresh/config). Plain shell `KEY=value` lines, sourced
#   before CLI parsing — anything you can set on the command line you can
#   set there. Run with --print-config to see the parsed result.
#
# Usage:
#   ./stay_fresh.sh [--dry-run] [--yes] [--verbose] [--summary-only]
#                   [--only step1,step2,...] [--skip-* ...] [--json]
#                   [--install-updates] [--refresh-updates]
#                   [--brewfile-snapshot] [--quicklook-reset]
#                   [--force] [--no-notify] [--no-sudo] [--history]
#                   [--print-config] [--help]
#
# Exit codes:
#   0   housekeeping finished (possibly with non-fatal warnings)
#   1   one or more steps hard-failed
#   2   preflight checks failed
#   3   bad CLI arguments
#   4   another stay_fresh.sh is already running (lock file held)

set -u
set -o pipefail

# ---------------------------------------------------------------------------
# constants — anything tunable lives here, in one place
# ---------------------------------------------------------------------------
LOG_DIR="${TMPDIR:-/tmp}"
LOG_BASENAME="stay_fresh"
LOG_FILE="$LOG_DIR/${LOG_BASENAME}-$(date +%Y%m%d-%H%M%S).log"
PERSISTENT_LOG_DIR="$HOME/Library/Logs/stay_fresh"
HISTORY_CSV="$PERSISTENT_LOG_DIR/history.csv"
MAX_PERSISTENT_LOGS=10
LOCK_FILE="$LOG_DIR/${LOG_BASENAME}.lock"

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/stay_fresh/config"

# softwareupdate --list is a slow network call; cache result for this long
SWU_CACHE_FILE="$LOG_DIR/${LOG_BASENAME}-swu-cache"
SWU_CACHE_TTL=$(( 6 * 60 * 60 ))     # 6 hours, in seconds

# preflight thresholds
MIN_FREE_BYTES_FOR_BREW=$(( 2 * 1024 * 1024 * 1024 ))    # 2 GiB
LOW_BATTERY_THRESHOLD=50                                  # %, warn below this on battery
TMUTIL_SNAPSHOT_TRIGGER_BYTES=$(( 15 * 1024 * 1024 * 1024 ))  # 15 GiB

PLAN_COL_WIDTH=34

# ---------------------------------------------------------------------------
# output helpers (TTY-aware colors)
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
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_MAGENTA='' C_CYAN=''
fi

bold()  { printf "%s%s%s\n" "$C_BOLD"    "$*" "$C_RESET"; }
info()  { printf "%s[info]%s %s\n"  "$C_BLUE"   "$C_RESET" "$*"; }
ok()    { printf "%s[ ok ]%s %s\n"  "$C_GREEN"  "$C_RESET" "$*"; }
warn()  { printf "%s[warn]%s %s\n"  "$C_YELLOW" "$C_RESET" "$*"; }
err()   { printf "%s[err ]%s %s\n"  "$C_RED"    "$C_RESET" "$*" 1>&2; }
step()  { printf "\n%s==>%s %s%s%s\n" "$C_CYAN" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }
hr()    { printf "%s%s%s\n" "$C_DIM" "--------------------------------------------------------------" "$C_RESET"; }

# ---------------------------------------------------------------------------
# defaults / CLI parsing
# ---------------------------------------------------------------------------
DRY_RUN=0
ASSUME_YES=0
VERBOSE=0
USE_SUDO=1
SUMMARY_ONLY=0
JSON_SUMMARY=0
NO_NOTIFY=0
FORCE=0
PRINT_HISTORY=0
PRINT_CONFIG=0
REFRESH_UPDATES=0

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
BREWFILE_SNAPSHOT=0
INSTALL_UPDATES=0
SKIP_UPDATES=0

# new steps (all auto-skip when their tools are missing)
SKIP_MAS=0
SKIP_PIPX=0
SKIP_RUSTUP=0
SKIP_MISE=0
SKIP_VSCODE=0
SKIP_SNAPSHOTS=0
SKIP_LAUNCHAGENTS=0
QUICKLOOK_RESET=0           # opt-in: cosmetic, only on demand

# --only filtering — populated after parsing
ONLY_LIST=""
ONLY_FILTER_ACTIVE=0

# ---------------------------------------------------------------------------
# config file — sourced after defaults, before CLI (flags override config)
# ---------------------------------------------------------------------------
if [[ -r "$CONFIG_FILE" ]]; then
  # Defensive sourcing: protect against a stray `exit` in the file. We can't
  # fully sandbox shell sourcing, but a clearly-scoped subshell test catches
  # the worst gotchas (set -u violations, bad redirection, syntax errors).
  if ! ( set -u; source "$CONFIG_FILE" ) >/dev/null 2>&1; then
    printf "warning: config file %s has issues — sourcing anyway, errors may follow\n" \
      "$CONFIG_FILE" >&2
  fi
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

# Registry: short key -> "SKIP_VAR step_function Step label"
# Order matters: it defines the execution order in run_or_skip below.
STEP_KEYS=(
  memory dns syscaches usercaches trash docker xcode diagnostics
  brew brewfile-snapshot updates devcaches mas pipx rustup mise vscode
  helm-plugins gcloud versions snapshots launchagents quicklook
)

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

usage() {
  cat <<EOF
${C_BOLD}stay_fresh.sh${C_RESET} — macOS housekeeping in one script.

${C_BOLD}Usage:${C_RESET}
  $(basename "$0") [options]

${C_BOLD}General options:${C_RESET}
  --dry-run              Preview actions, change nothing
  --yes, -y              Don't prompt for confirmation
  --verbose, -v          Stream command output (default: captured to log)
  --summary-only         Suppress per-step output; print only the summary card
  --json                 Print a JSON summary in addition to the human card
  --no-sudo              Skip steps that require sudo
  --no-notify            Don't send a macOS notification at the end
  --force                Bypass non-critical preflight warnings (battery, disk,
                         CLT version mismatch, Rosetta)
  --history              Show recent run history from history.csv and exit
  --print-config         Show the parsed config + final flag values and exit
  --help, -h             Show this help

${C_BOLD}Step selection:${C_RESET}
  --only k1,k2,...       Only run the listed steps (negates all --skip-* flags).
                         Valid keys: $(IFS=, ; printf '%s' "${STEP_KEYS[*]}")

${C_BOLD}Step toggles (skip individual steps):${C_RESET}
  --skip-memory          Don't run 'sudo purge'
  --skip-dns             Don't flush DNS caches
  --skip-syscaches       Don't touch /Library/Caches or /System/Library/Caches
  --skip-usercaches      Don't clear ~/Library/Caches et al.
  --skip-trash           Don't empty ~/.Trash
  --skip-docker          Don't prune Docker / OrbStack
  --skip-xcode           Don't clean Xcode Archives/DeviceSupport/simulators
  --skip-diagnostics     Don't remove crash / diagnostic reports (see Notes)
  --skip-brew            Don't run Homebrew maintenance (see Notes)
  --brew-greedy          Also upgrade casks with 'auto_updates true' / 'version :latest'
  --brewfile-snapshot    Write \`brew bundle dump\` to ~/.Brewfile.YYYYMMDD before brew
  --skip-updates         Skip the macOS software update check
  --install-updates      Apply all pending macOS updates (default: list only)
  --refresh-updates      Bypass the 6-hour softwareupdate --list cache
  --skip-devcaches       Don't clean npm/yarn/pnpm/pip/gem/go/cargo caches
  --skip-mas             Don't run 'mas upgrade' (App Store updates)
  --skip-pipx            Don't run 'pipx upgrade-all'
  --skip-rustup          Don't run 'rustup update'
  --skip-mise            Don't run 'mise upgrade' / 'asdf update'
  --skip-vscode          Don't update VSCode / Cursor extensions
  --skip-helm-plugins    Don't run 'helm plugin update' for installed plugins
  --skip-gcloud          Don't run 'gcloud components update'
  --skip-versions        Don't print active pyenv/goenv/tfenv/tenv/helm/gcloud versions
  --skip-devtools        Shorthand: skip all dev-tool refresh steps
                         (helm-plugins, gcloud, versions, mas, pipx, rustup, mise, vscode)
  --skip-snapshots       Don't trim Time Machine local snapshots when disk is tight
  --skip-launchagents    Don't audit ~/Library/LaunchAgents for orphans
  --quicklook-reset      Reset Quick Look + Finder caches (cosmetic, opt-in)

${C_BOLD}Notes:${C_RESET}
  Diagnostic / crash reports: always runs as your user. With sudo (default), also
  clears /Library/Logs/DiagnosticReports and /Library/Logs/CrashReporter.
  --no-sudo skips only those system paths.

  Homebrew: runs brew update; brew upgrade (formulae, then casks); brew cleanup -s;
  brew autoremove; brew doctor only when --verbose. With --brewfile-snapshot a
  pre-run Brewfile snapshot is written so unwanted autoremoves can be undone.

  macOS Software Update: --install-updates runs 'softwareupdate --install --all',
  which may present a GUI authentication dialog and requires a reboot if any
  update is marked Restart: YES. Pass --refresh-updates to force a fresh network
  query (default cache TTL is 6 hours).

  Preflight refusals are recoverable with --force. Refuses cover: <2 GiB free on
  /, low battery on AC-detached laptops, CLT major version mismatched against
  macOS, and an x86_64 brew running under Rosetta on Apple Silicon.

${C_BOLD}Config:${C_RESET}
  Defaults: $CONFIG_FILE
  (Plain KEY=value; sourced before flag parsing. Run --print-config to inspect.)

${C_BOLD}Logs:${C_RESET}
  Active run:        $LOG_FILE
  Kept on warn/fail: $PERSISTENT_LOG_DIR (most recent $MAX_PERSISTENT_LOGS)
  History CSV:       $HISTORY_CSV
  Discarded on a clean run.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run)            DRY_RUN=1 ;;
    -y|--yes)             ASSUME_YES=1 ;;
    -v|--verbose)         VERBOSE=1 ;;
    --summary-only)       SUMMARY_ONLY=1 ;;
    --json)               JSON_SUMMARY=1 ;;
    --no-sudo)            USE_SUDO=0 ;;
    --no-notify)          NO_NOTIFY=1 ;;
    --force)              FORCE=1 ;;
    --history)            PRINT_HISTORY=1 ;;
    --print-config)       PRINT_CONFIG=1 ;;
    --only)               shift; ONLY_LIST="${1:-}"; ONLY_FILTER_ACTIVE=1 ;;
    --only=*)             ONLY_LIST="${1#--only=}"; ONLY_FILTER_ACTIVE=1 ;;
    --skip-memory)        SKIP_MEMORY=1 ;;
    --skip-dns)           SKIP_DNS=1 ;;
    --skip-syscaches)     SKIP_SYSCACHES=1 ;;
    --skip-usercaches)    SKIP_USERCACHES=1 ;;
    --skip-trash)         SKIP_TRASH=1 ;;
    --skip-brew)          SKIP_BREW=1 ;;
    --brew-greedy)        BREW_GREEDY=1 ;;
    --brewfile-snapshot)  BREWFILE_SNAPSHOT=1 ;;
    --skip-devcaches)     SKIP_DEVCACHES=1 ;;
    --skip-devtools)      SKIP_DEVTOOLS=1 ;;
    --skip-helm-plugins)  SKIP_HELM_PLUGINS=1 ;;
    --skip-gcloud)        SKIP_GCLOUD=1 ;;
    --skip-versions)      SKIP_VERSIONS=1 ;;
    --skip-docker)        SKIP_DOCKER=1 ;;
    --skip-xcode)         SKIP_XCODE=1 ;;
    --skip-diagnostics)   SKIP_DIAGNOSTICS=1 ;;
    --skip-updates)       SKIP_UPDATES=1 ;;
    --refresh-updates)    REFRESH_UPDATES=1 ;;
    --install-updates)    INSTALL_UPDATES=1 ;;
    --skip-mas)           SKIP_MAS=1 ;;
    --skip-pipx)          SKIP_PIPX=1 ;;
    --skip-rustup)        SKIP_RUSTUP=1 ;;
    --skip-mise)          SKIP_MISE=1 ;;
    --skip-vscode)        SKIP_VSCODE=1 ;;
    --skip-snapshots)     SKIP_SNAPSHOTS=1 ;;
    --skip-launchagents)  SKIP_LAUNCHAGENTS=1 ;;
    --quicklook-reset)    QUICKLOOK_RESET=1 ;;
    -h|--help)            usage; exit 0 ;;
    *)                    err "unknown option: $1"; echo; usage; exit 3 ;;
  esac
  shift
done

# --skip-devtools is a convenience; fan it out across the individual
# dev-tool refresh steps so the plan/summary accurately reflects what runs.
if (( SKIP_DEVTOOLS )); then
  SKIP_HELM_PLUGINS=1
  SKIP_GCLOUD=1
  SKIP_VERSIONS=1
  SKIP_MAS=1
  SKIP_PIPX=1
  SKIP_RUSTUP=1
  SKIP_MISE=1
  SKIP_VSCODE=1
fi

# ---------------------------------------------------------------------------
# step registry mapping (key -> SKIP_VAR + step_fn + label)
# Used by --only filtering, plan rendering, and the execute block.
# ---------------------------------------------------------------------------
step_var_for() {
  case "$1" in
    memory)            echo SKIP_MEMORY ;;
    dns)               echo SKIP_DNS ;;
    syscaches)         echo SKIP_SYSCACHES ;;
    usercaches)        echo SKIP_USERCACHES ;;
    trash)             echo SKIP_TRASH ;;
    docker)            echo SKIP_DOCKER ;;
    xcode)             echo SKIP_XCODE ;;
    diagnostics)       echo SKIP_DIAGNOSTICS ;;
    brew)              echo SKIP_BREW ;;
    brewfile-snapshot) echo __INV_BREWFILE_SNAPSHOT ;;     # opt-in
    updates)           echo SKIP_UPDATES ;;
    devcaches)         echo SKIP_DEVCACHES ;;
    mas)               echo SKIP_MAS ;;
    pipx)              echo SKIP_PIPX ;;
    rustup)            echo SKIP_RUSTUP ;;
    mise)              echo SKIP_MISE ;;
    vscode)            echo SKIP_VSCODE ;;
    helm-plugins)      echo SKIP_HELM_PLUGINS ;;
    gcloud)            echo SKIP_GCLOUD ;;
    versions)          echo SKIP_VERSIONS ;;
    snapshots)         echo SKIP_SNAPSHOTS ;;
    launchagents)      echo SKIP_LAUNCHAGENTS ;;
    quicklook)         echo __INV_QUICKLOOK_RESET ;;       # opt-in
    *)                 echo "" ;;
  esac
}

# Apply --only: turn ON the listed steps, turn OFF everything else.
# Opt-in steps (brewfile-snapshot, quicklook) are enabled by inclusion in --only.
if (( ONLY_FILTER_ACTIVE )); then
  declare -A _only_set=()
  IFS=, read -r -a _only_arr <<< "$ONLY_LIST"
  for k in "${_only_arr[@]}"; do
    k="${k// /}"   # strip whitespace
    [[ -z "$k" ]] && continue
    if [[ -z "$(step_var_for "$k")" ]]; then
      err "--only: unknown step key '$k' (valid: ${STEP_KEYS[*]})"
      exit 3
    fi
    _only_set["$k"]=1
  done
  for k in "${STEP_KEYS[@]}"; do
    var="$(step_var_for "$k")"
    if [[ "${_only_set[$k]:-}" == "1" ]]; then
      case "$var" in
        __INV_BREWFILE_SNAPSHOT) BREWFILE_SNAPSHOT=1 ;;
        __INV_QUICKLOOK_RESET)   QUICKLOOK_RESET=1 ;;
        *) eval "$var=0" ;;
      esac
    else
      case "$var" in
        __INV_BREWFILE_SNAPSHOT) BREWFILE_SNAPSHOT=0 ;;
        __INV_QUICKLOOK_RESET)   QUICKLOOK_RESET=0 ;;
        *) eval "$var=1" ;;
      esac
    fi
  done
  unset _only_set _only_arr
fi

# Flag combo validation
if (( SKIP_BREW == 1 )) && (( BREW_GREEDY == 1 || BREWFILE_SNAPSHOT == 1 )); then
  err "--brew-greedy / --brewfile-snapshot require --skip-brew to be off"
  exit 3
fi
if (( SKIP_UPDATES == 1 )) && (( INSTALL_UPDATES == 1 )); then
  err "--install-updates and --skip-updates are mutually exclusive"
  exit 3
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
    printf "  %s(dry-run)%s %s %s[%s]%s\n" \
      "$C_DIM" "$C_RESET" "$*" "$C_DIM" "$label" "$C_RESET"
    return 0
  fi
  printf "  %s->%s %s\n" "$C_CYAN" "$C_RESET" "$label"
  echo "# $(date '+%H:%M:%S') [$label] >> $*" >>"$LOG_FILE"
  local rc=0
  if (( VERBOSE )); then
    "$@" 2>&1 | tee -a "$LOG_FILE"
    rc="${PIPESTATUS[0]}"
  else
    "$@" >>"$LOG_FILE" 2>&1
    rc=$?
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
    printf "  %s(dry-run)%s %s %s[%s]%s\n" \
      "$C_DIM" "$C_RESET" "$*" "$C_DIM" "$label" "$C_RESET"
    return 0
  fi
  printf "  %s->%s %s\n" "$C_CYAN" "$C_RESET" "$label"
  echo "# $(date '+%H:%M:%S') [$label] >> $*" >>"$LOG_FILE"
  local rc=0
  if [[ -r /dev/tty && -w /dev/tty ]]; then
    "$@" </dev/tty 2>&1 | tee -a "$LOG_FILE"
    rc="${PIPESTATUS[0]}"
  else
    "$@" 2>&1 | tee -a "$LOG_FILE"
    rc="${PIPESTATUS[0]}"
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
  if [[ ! -d "$dir" ]]; then
    printf "  %s- %s (missing, skipped)%s\n" "$C_DIM" "$dir" "$C_RESET"
    return 0
  fi
  before_b="$(path_bytes "$dir")"
  printf "  clearing %s %s(%s)%s\n" "$dir" "$C_DIM" "$(human_bytes "$before_b")" "$C_RESET"
  if (( DRY_RUN )); then
    printf "  %s(dry-run) would remove contents of %s%s\n" "$C_DIM" "$dir" "$C_RESET"
    return 0
  fi
  if [[ "$use_sudo" == "sudo" ]]; then
    sudo find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>>"$LOG_FILE" || true
  else
    find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>>"$LOG_FILE" || true
  fi
  after_b="$(path_bytes "$dir")"
  delta=$(( before_b - after_b ))
  (( delta > 0 )) && STEP_FREED_B=$(( STEP_FREED_B + delta ))
  printf "  %s->%s freed %s from %s\n" "$C_GREEN" "$C_RESET" "$(human_bytes "$delta")" "$dir"
}

# ---------------------------------------------------------------------------
# softwareupdate --list cache
# ---------------------------------------------------------------------------
# Cache the (slow) "softwareupdate --list" output for SWU_CACHE_TTL seconds so
# repeated runs in a day don't repeatedly hit Apple's CDN. --refresh-updates
# bypasses the cache and rewrites it.
swu_cache_age() {
  [[ -r "$SWU_CACHE_FILE" ]] || { echo 999999999; return; }
  local now mt
  now="$(date +%s)"
  mt="$(stat -f %m "$SWU_CACHE_FILE" 2>/dev/null || echo 0)"
  echo $(( now - mt ))
}
swu_cache_valid() {
  (( REFRESH_UPDATES )) && return 1
  local age; age="$(swu_cache_age)"
  (( age < SWU_CACHE_TTL ))
}
swu_cache_write() { printf '%s\n' "$1" > "$SWU_CACHE_FILE" 2>/dev/null || true; }
swu_cache_read()  { cat "$SWU_CACHE_FILE" 2>/dev/null; }

# ---------------------------------------------------------------------------
# top cache offenders — peeks inside ~/Library/Caches and prints the N largest
# entries so the user sees what gets reclaimed before clear_dir wipes them.
# ---------------------------------------------------------------------------
top_cache_offenders() {
  local dir="$1" n="${2:-5}"
  [[ -d "$dir" ]] || return 0
  printf "  %stop %d offenders under %s:%s\n" "$C_DIM" "$n" "$dir" "$C_RESET"
  # du -sk on visible children, sort numeric descending, take top N.
  # `2>/dev/null` swallows EACCES on protected entries; `|| true` tolerates an
  # empty caches dir (du then exits 1).
  ( cd "$dir" 2>/dev/null && du -sk -- */ .[!.]*/ 2>/dev/null ) \
    | sort -rn | head -n "$n" \
    | awk -v c_dim="$C_DIM" -v c_reset="$C_RESET" '
        { k=$1; $1=""; sub(/^ /,"");
          unit="K"; v=k;
          if (v>=1048576) { v=v/1048576; unit="G" }
          else if (v>=1024) { v=v/1024; unit="M" }
          printf "    %s%6.1f%s %s%s\n", c_dim, v, unit, $0, c_reset
        }' || true
}

# ---------------------------------------------------------------------------
# macOS notification (optional, end-of-run)
# ---------------------------------------------------------------------------
notify_user() {
  (( NO_NOTIFY )) && return 0
  command -v osascript >/dev/null 2>&1 || return 0
  local title="$1" message="$2"
  # Quote-safety: osascript single-quote handling is finicky. Escape backslashes
  # and double-quotes so display notification doesn't choke on user paths.
  local t_esc m_esc
  t_esc="${title//\\/\\\\}"; t_esc="${t_esc//\"/\\\"}"
  m_esc="${message//\\/\\\\}"; m_esc="${m_esc//\"/\\\"}"
  osascript -e "display notification \"$m_esc\" with title \"$t_esc\"" \
    >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# history CSV — one row per completed run for trend reporting
# ---------------------------------------------------------------------------
write_history_row() {
  local elapsed="$1" freed="$2" ok_n="$3" warn_n="$4" fail_n="$5" skip_n="$6" rc="$7"
  mkdir -p "$PERSISTENT_LOG_DIR" 2>/dev/null || return 0
  if [[ ! -f "$HISTORY_CSV" ]]; then
    echo "timestamp,elapsed_sec,freed_bytes,ok,warn,fail,skip,exit_code" >"$HISTORY_CSV"
  fi
  printf '%s,%d,%d,%d,%d,%d,%d,%d\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$elapsed" "$freed" \
    "$ok_n" "$warn_n" "$fail_n" "$skip_n" "$rc" >>"$HISTORY_CSV"
}

print_history() {
  if [[ ! -r "$HISTORY_CSV" ]]; then
    info "no history yet at $HISTORY_CSV"
    return 0
  fi
  bold "=== stay_fresh history (most recent 15) ==="
  printf "  %-22s %8s %10s %3s %4s %4s %4s %4s\n" \
    "WHEN (UTC)" "ELAPSED" "FREED" "OK" "WARN" "FAIL" "SKIP" "RC"
  tail -n +2 "$HISTORY_CSV" | tail -n 15 \
    | awk -F, -v c_dim="$C_DIM" -v c_reset="$C_RESET" '
        {
          el=$2; fb=$3
          fh=fb
          unit="B"
          if (fh>=1073741824) { fh=fh/1073741824; unit="G" }
          else if (fh>=1048576) { fh=fh/1048576; unit="M" }
          else if (fh>=1024) { fh=fh/1024; unit="K" }
          if (el>=60) { em=int(el/60); es=el-em*60; eldisp=sprintf("%dm%02ds",em,es) }
          else        { eldisp=sprintf("%ds",el) }
          printf "  %-22s %8s %9.2f%s %3d %4d %4d %4d %4d\n", $1, eldisp, fh, unit, $4, $5, $6, $7, $8
        }'
}

print_config() {
  bold "=== stay_fresh: parsed config ==="
  printf "  config file:           %s%s\n" \
    "$CONFIG_FILE" \
    "$( [[ -r "$CONFIG_FILE" ]] && echo "" || echo " (not present)" )"
  printf "  log file:              %s\n" "$LOG_FILE"
  printf "  persistent log dir:    %s\n" "$PERSISTENT_LOG_DIR"
  printf "  history csv:           %s\n" "$HISTORY_CSV"
  printf "  swu cache:             %s (ttl %ds)\n" "$SWU_CACHE_FILE" "$SWU_CACHE_TTL"
  printf "  min free for brew:     %s\n" "$(human_bytes "$MIN_FREE_BYTES_FOR_BREW")"
  printf "  low battery threshold: %d%%\n" "$LOW_BATTERY_THRESHOLD"
  echo
  bold "  Mode flags:"
  for v in DRY_RUN ASSUME_YES VERBOSE SUMMARY_ONLY JSON_SUMMARY NO_NOTIFY \
           FORCE USE_SUDO REFRESH_UPDATES INSTALL_UPDATES BREW_GREEDY \
           BREWFILE_SNAPSHOT QUICKLOOK_RESET; do
    printf "    %-22s = %s\n" "$v" "${!v}"
  done
  echo
  bold "  Skip flags:"
  for v in SKIP_MEMORY SKIP_DNS SKIP_SYSCACHES SKIP_USERCACHES SKIP_TRASH \
           SKIP_DOCKER SKIP_XCODE SKIP_DIAGNOSTICS SKIP_BREW SKIP_UPDATES \
           SKIP_DEVCACHES SKIP_MAS SKIP_PIPX SKIP_RUSTUP SKIP_MISE SKIP_VSCODE \
           SKIP_HELM_PLUGINS SKIP_GCLOUD SKIP_VERSIONS \
           SKIP_SNAPSHOTS SKIP_LAUNCHAGENTS; do
    printf "    %-22s = %s\n" "$v" "${!v}"
  done
  echo
  if (( ONLY_FILTER_ACTIVE )); then
    printf "  --only filter active:  %s\n" "$ONLY_LIST"
  fi
}

# Handle --history / --print-config now: read-only, exit before side effects.
if (( PRINT_HISTORY )); then
  print_history
  exit 0
fi
if (( PRINT_CONFIG )); then
  print_config
  exit 0
fi

# ---------------------------------------------------------------------------
# lock file — prevent concurrent runs from clobbering each other's logs / brew
# ---------------------------------------------------------------------------
acquire_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    local pid
    pid="$(cat "$LOCK_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      err "another stay_fresh.sh is already running (pid $pid, lock $LOCK_FILE)"
      err "if that's wrong, remove the lock file and retry"
      exit 4
    fi
    # Stale lock — owner gone. Reclaim.
    rm -f "$LOCK_FILE"
  fi
  echo "$$" >"$LOCK_FILE"
}
release_lock() {
  [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]] \
    && rm -f "$LOCK_FILE"
}

# ---------------------------------------------------------------------------
# signal handling — ensure lock is released and partial summary is offered
# ---------------------------------------------------------------------------
INTERRUPTED=0
on_signal() {
  INTERRUPTED=1
  printf '\n'
  warn "received SIG$1 — finishing the current step and bailing out"
  # Don't exit here: let the current step finish naturally so its log entry is
  # complete. The next run_or_skip will see INTERRUPTED=1 and short-circuit.
}
on_exit() {
  local rc="$1"
  # Kill any sudo keepalive started by preflight.
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  fi
  release_lock
  # If interrupted before the normal summary path ran, leave a short marker
  # so the user knows the log is incomplete.
  if (( INTERRUPTED == 1 )) && [[ -w "$LOG_FILE" ]]; then
    echo "# interrupted by user at $(date)" >> "$LOG_FILE" 2>/dev/null || true
  fi
  return "$rc"
}

# ---------------------------------------------------------------------------
# preflight checks
# ---------------------------------------------------------------------------
bold "=== stay_fresh: preflight checks ==="

mkdir -p "$LOG_DIR"
: > "$LOG_FILE"
echo "stay_fresh.sh log - $(date)" >> "$LOG_FILE"
info "log file: $C_DIM$LOG_FILE$C_RESET"

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

# 2a. Concurrency lock — only after we know we're on macOS and not root.
acquire_lock
trap 'on_exit "$?"' EXIT
trap 'on_signal INT'  INT
trap 'on_signal TERM' TERM

# 3. Disk free before
FREE_BEFORE_B="$(disk_free_bytes)"
ok "disk free on /: $(human_bytes "$FREE_BEFORE_B")"

# 3a. Disk-pressure preflight — refuse heavyweight brew run on a near-full disk.
if (( SKIP_BREW == 0 )) && (( FREE_BEFORE_B < MIN_FREE_BYTES_FOR_BREW )); then
  if (( FORCE )); then
    warn "only $(human_bytes "$FREE_BEFORE_B") free on / — brew may fail; --force overrides"
  else
    err "only $(human_bytes "$FREE_BEFORE_B") free on / (< $(human_bytes "$MIN_FREE_BYTES_FOR_BREW")); refusing brew step"
    err "free up disk space, pass --skip-brew, or re-run with --force"
    SKIP_BREW=1
    STEPS_SKIP+=("brew (disk too full)")
  fi
fi

# 3b. Battery preflight — warn if low and not on AC.
if command -v pmset >/dev/null 2>&1; then
  ps_out="$(pmset -g ps 2>/dev/null || true)"
  if grep -q "Battery Power" <<<"$ps_out"; then
    pct="$(grep -oE '[0-9]+%' <<<"$ps_out" | head -n1 | tr -d %)"
    if [[ -n "${pct:-}" ]] && (( pct < LOW_BATTERY_THRESHOLD )); then
      if (( FORCE )); then
        warn "on battery ($pct%) — proceeding because --force was set"
      else
        warn "on battery ($pct%); long upgrades can drain the laptop. Plug in or pass --force"
        # Not fatal — keep going. The warn is enough.
      fi
    else
      ok "battery: $pct% (on battery, threshold $LOW_BATTERY_THRESHOLD%)"
    fi
  fi
fi

# 3c. Rosetta detection — Apple Silicon running x86_64 Homebrew is almost
# always a mistake (creates a stale /usr/local/bin shadow tree).
if [[ "$(uname -m)" == "arm64" ]] && (( SKIP_BREW == 0 )) && command -v brew >/dev/null 2>&1; then
  brew_prefix="$(brew --prefix 2>/dev/null || echo '')"
  if [[ "$brew_prefix" == "/usr/local"* ]]; then
    if (( FORCE )); then
      warn "Apple Silicon Mac but brew is at $brew_prefix (Rosetta?) — --force overrides"
    else
      err "Apple Silicon Mac but brew is at $brew_prefix — likely running under Rosetta"
      err "install native brew (/opt/homebrew), pass --skip-brew, or --force to proceed"
      SKIP_BREW=1
      STEPS_SKIP+=("brew (wrong arch)")
    fi
  fi
fi

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

# 4a. Xcode Command Line Tools check (Homebrew frequently depends on them).
# We can't perfectly predict "too outdated", but we can catch missing CLT and
# flag obvious mismatches (e.g. macOS major != CLT major).
if (( SKIP_BREW == 0 )); then
  if xcode-select -p >/dev/null 2>&1; then
    clt_ver="$(pkgutil --pkg-info com.apple.pkg.CLTools_Executables 2>/dev/null | awk -F': ' '/^version:/ {print $2}' | head -n1)"
    if [[ -n "$clt_ver" ]]; then
      os_major="${OS_VERSION%%.*}"
      clt_major="${clt_ver%%.*}"
      if [[ "$os_major" != "?" ]] && [[ "$clt_major" != "?" ]] && [[ "$os_major" != "$clt_major" ]]; then
        if (( FORCE )); then
          warn "Xcode CLT ($clt_ver) does not match macOS major ($OS_VERSION) — brew upgrades may fail; --force overrides"
        else
          err "Xcode CLT ($clt_ver) does not match macOS major ($OS_VERSION); refusing brew step (Homebrew upgrades historically corrupt here)"
          err "fix: System Settings → Software Update, or 'sudo rm -rf /Library/Developer/CommandLineTools && sudo xcode-select --install'"
          err "(re-run with --force to proceed anyway)"
          SKIP_BREW=1
          STEPS_SKIP+=("brew (CLT mismatch)")
        fi
      else
        ok "Xcode Command Line Tools: $clt_ver"
      fi
    else
      ok "Xcode Command Line Tools: present"
    fi
  else
    warn "Xcode Command Line Tools not detected — Homebrew upgrades may fail (install via 'xcode-select --install')"
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
  # Use an existing valid timestamp if present — avoids the prompt entirely on
  # repeated runs within the same sudo session window.
  if sudo -n true 2>/dev/null; then
    SUDO_AVAILABLE=1
    ok "sudo session already active — no password needed"
  else
    info "some steps need sudo — you will be prompted once"
    if sudo -v; then
      SUDO_AVAILABLE=1
      ok "sudo authenticated"
    else
      err "sudo authentication failed — disabling sudo-requiring steps"
      SKIP_MEMORY=1
      SKIP_DNS=1
      SKIP_SYSCACHES=1
      SKIP_DIAGNOSTICS_SYS=1
    fi
  fi
  if (( SUDO_AVAILABLE )); then
    # Keep-alive: refresh every 30 s so the timestamp never expires mid-run.
    # Disown so EXIT kill does not print bash job "Terminated: 15" noise.
    ( while true; do sudo -n true; sleep 30; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
    disown "$SUDO_KEEPALIVE_PID" 2>/dev/null || disown || true
    # Note: on_exit (already trapped) kills $SUDO_KEEPALIVE_PID for us.
  fi
elif (( DRY_RUN )); then
  info "(dry-run) would request sudo for memory/DNS/system-caches/diagnostics steps"
fi

SKIP_DIAGNOSTICS_SYS="${SKIP_DIAGNOSTICS_SYS:-0}"

# ---------------------------------------------------------------------------
# last-run banner — show the most recent history row so users see continuity
# ---------------------------------------------------------------------------
if [[ -r "$HISTORY_CSV" ]]; then
  last_row="$(tail -n 1 "$HISTORY_CSV" 2>/dev/null || true)"
  if [[ -n "$last_row" && "$last_row" != "timestamp,"* ]]; then
    IFS=, read -r lr_ts lr_el lr_fb lr_ok lr_warn lr_fail lr_skip lr_rc <<<"$last_row"
    # Approximate "days ago" without dateutil. Best-effort.
    days_ago="?"
    if command -v python3 >/dev/null 2>&1; then
      days_ago="$(python3 -c "
import datetime, sys
try:
  t=datetime.datetime.strptime('$lr_ts','%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc)
  d=(datetime.datetime.now(datetime.timezone.utc)-t).days
  print(d if d>=0 else 0)
except Exception:
  print('?')
" 2>/dev/null || echo '?')"
    fi
    case "$lr_rc" in
      0) badge="${C_GREEN}clean${C_RESET}" ;;
      *) badge="${C_RED}failed${C_RESET}" ;;
    esac
    (( lr_warn > 0 )) && [[ "$lr_rc" == "0" ]] && badge="${C_YELLOW}warned${C_RESET}"
    info "previous run: $badge $lr_ts (${days_ago}d ago) · $(human_bytes "$lr_fb") freed · ok=$lr_ok warn=$lr_warn fail=$lr_fail skip=$lr_skip"
  fi
fi

# ---------------------------------------------------------------------------
# plan + confirmation
# ---------------------------------------------------------------------------
hr
bold "Plan:"
printf "  %-${PLAN_COL_WIDTH}s %s\n" "STEP" "STATUS"
printf "  %-${PLAN_COL_WIDTH}s %s\n" "----" "------"
plan_line() {
  local name="$1" active="$2" extra="${3:-}"
  if (( active )); then
    printf "  %-${PLAN_COL_WIDTH}s %brun%b %s\n" "$name" "$C_GREEN" "$C_RESET" "$extra"
  else
    printf "  %-${PLAN_COL_WIDTH}s %bskip%b %s\n" "$name" "$C_DIM" "$C_RESET" "$extra"
  fi
}
plan_line "purge inactive memory"             "$(( 1 - SKIP_MEMORY      ))" "sudo purge"
plan_line "flush DNS cache"                   "$(( 1 - SKIP_DNS         ))" "dscacheutil + mDNSResponder"
plan_line "clear system caches"               "$(( 1 - SKIP_SYSCACHES   ))" "/Library/Caches, /System/Library/Caches"
plan_line "clear user caches"                 "$(( 1 - SKIP_USERCACHES  ))" "~/Library/Caches, Logs, DerivedData, ..."
plan_line "empty trash"                       "$(( 1 - SKIP_TRASH       ))" "~/.Trash"
plan_line "docker / orbstack prune"           "$(( 1 - SKIP_DOCKER      ))" "images, containers, volumes, builder"
plan_line "xcode extras"                      "$(( 1 - SKIP_XCODE       ))" "Archives, DeviceSupport, simulators"
plan_line "diagnostic / crash reports"        "$(( 1 - SKIP_DIAGNOSTICS ))" "user (+ system if sudo)"
plan_line "brewfile snapshot"                 "$BREWFILE_SNAPSHOT" "~/.Brewfile.YYYYMMDD"
plan_line "homebrew update/upgrade/cleanup"   "$(( 1 - SKIP_BREW        ))" "brew update · upgrade · cleanup -s · autoremove"
_swu_extra="softwareupdate --list"
(( INSTALL_UPDATES )) && _swu_extra="softwareupdate --install --all"
plan_line "macOS software update"             "$(( 1 - SKIP_UPDATES     ))" "$_swu_extra"
plan_line "dev-tool caches"                   "$(( 1 - SKIP_DEVCACHES   ))" "npm/yarn/pnpm/pip/gem/go/cargo"
plan_line "App Store updates (mas)"           "$(( 1 - SKIP_MAS         ))" "mas upgrade"
plan_line "pipx upgrade-all"                  "$(( 1 - SKIP_PIPX        ))" "pipx upgrade-all"
plan_line "rustup update"                     "$(( 1 - SKIP_RUSTUP      ))" "rustup update stable"
plan_line "mise / asdf self-update"           "$(( 1 - SKIP_MISE        ))" "mise upgrade · asdf update"
plan_line "VSCode / Cursor extensions"        "$(( 1 - SKIP_VSCODE      ))" "code --update-extensions"
plan_line "helm plugin refresh"               "$(( 1 - SKIP_HELM_PLUGINS))" "helm plugin update <name>"
plan_line "gcloud components update"          "$(( 1 - SKIP_GCLOUD      ))" "non-brew gcloud components"
plan_line "report active versions"            "$(( 1 - SKIP_VERSIONS    ))" "pyenv/goenv/tfenv/tenv/helm/gcloud"
plan_line "thin Time Machine snapshots"       "$(( 1 - SKIP_SNAPSHOTS   ))" "tmutil deletelocalsnapshots (when disk tight)"
plan_line "audit launch agents"               "$(( 1 - SKIP_LAUNCHAGENTS))" "~/Library/LaunchAgents orphans"
plan_line "quicklook + finder reset"          "$QUICKLOOK_RESET" "qlmanage -r cache; killall Finder"
hr

if (( DRY_RUN )); then
  bold "Dry run — no changes will be made."
fi

if (( ASSUME_YES == 0 )) && (( DRY_RUN == 0 )); then
  if [[ ! -t 0 ]]; then
    info "non-interactive stdin — auto-proceeding (use --yes to silence)"
  else
    printf "%sProceed? [y/N]%s " "$C_BOLD" "$C_RESET"
    read -r answer
    case "$answer" in
      y|Y|yes|YES) ;;
      *) warn "aborted by user"; exit 0 ;;
    esac
  fi
fi

# --summary-only: route stdout to log only (stderr stays on the user's terminal
# for warn/err messages). FD 3 saves the original stdout so we can restore it
# before printing the final summary card.
if (( SUMMARY_ONLY )); then
  exec 3>&1
  exec >>"$LOG_FILE"
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
  step "$label"
  STEP_WARN_COUNT=0
  STEP_FREED_B=0
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
    err "$label failed in $dur$freed_str — see log"
    STEPS_FAIL+=("$entry")
  elif (( STEP_WARN_COUNT > 0 )); then
    warn "$label finished with $STEP_WARN_COUNT warning(s) in $dur$freed_str — see log"
    STEPS_WARN+=("$entry")
  else
    ok "$label done in $dur$freed_str"
    STEPS_OK+=("$entry")
  fi
}

# ---------------------------------------------------------------------------
# steps
# ---------------------------------------------------------------------------
step_memory() {
  run_cmd "purge memory" sudo purge
}

step_dns() {
  run_cmd "flush DNS"            sudo dscacheutil -flushcache
  run_cmd "reload mDNSResponder" sudo killall -HUP mDNSResponder
}

step_syscaches() {
  clear_dir "/Library/Caches"        sudo
  if [[ -d /System/Library/Caches ]]; then
    printf "  /System/Library/Caches: removing writable entries only\n"
    if (( DRY_RUN == 0 )); then
      # BSD find on macOS does not consistently support -writable; use -perm instead.
      sudo find /System/Library/Caches -mindepth 1 -maxdepth 2 \
        \( -perm -u+w -o -perm -g+w -o -perm -o+w \) \
        -exec rm -rf {} + 2>>"$LOG_FILE" || true
    else
      printf "  %s(dry-run) would remove writable entries in /System/Library/Caches%s\n" "$C_DIM" "$C_RESET"
    fi
  fi
}

step_usercaches() {
  local targets=(
    "$HOME/Library/Caches"
    "$HOME/Library/Logs"
    "$HOME/Library/Saved Application State"
    "$HOME/Library/Developer/Xcode/DerivedData"
    "$HOME/Library/Application Support/Caches"
  )
  # Surface the biggest offenders in ~/Library/Caches before wiping, so the
  # user knows which app's cache is responsible for the freed bytes.
  top_cache_offenders "$HOME/Library/Caches" 5
  for d in "${targets[@]}"; do
    clear_dir "$d"
  done
}

step_trash() {
  local trash="$HOME/.Trash"
  if [[ ! -d "$trash" ]]; then
    warn "~/.Trash not found"
    return 0
  fi
  local before_b after_b delta
  before_b="$(path_bytes "$trash")"
  printf "  %s %s(%s)%s\n" "$trash" "$C_DIM" "$(human_bytes "$before_b")" "$C_RESET"
  if (( DRY_RUN )); then
    printf "  %s(dry-run) would empty ~/.Trash%s\n" "$C_DIM" "$C_RESET"
    return 0
  fi
  # -mindepth 1 skips $trash itself; -delete handles hidden files and avoids the
  # '.' / '..' issues that 'rm -rf "$trash"/.*' produces.
  find "$trash" -mindepth 1 -delete 2>>"$LOG_FILE" || true
  after_b="$(path_bytes "$trash")"
  delta=$(( before_b - after_b ))
  (( delta > 0 )) && STEP_FREED_B=$(( STEP_FREED_B + delta ))
  printf "  %s->%s freed %s from ~/.Trash\n" "$C_GREEN" "$C_RESET" "$(human_bytes "$delta")"
}

step_devcaches() {
  local any=0
  local node_ok=0
  if command -v node >/dev/null 2>&1 && node -v >/dev/null 2>&1; then
    node_ok=1
  fi

  if command -v npm >/dev/null 2>&1; then
    any=1
    local d="$HOME/.npm"
    printf "  npm cache %s(%s)%s\n" "$C_DIM" "$(human_bytes "$(path_bytes "$d")")" "$C_RESET"
    if (( node_ok )); then
      run_cmd "npm cache clean --force" npm cache clean --force || warn "'npm cache clean' failed"
    else
      warn "node is not runnable; skipping npm cache clean (try: brew reinstall node)"
    fi
  fi

  if command -v yarn >/dev/null 2>&1; then
    any=1
    local d="$HOME/Library/Caches/Yarn"
    printf "  yarn cache %s(%s)%s\n" "$C_DIM" "$(human_bytes "$(path_bytes "$d")")" "$C_RESET"
    if (( node_ok )); then
      run_cmd "yarn cache clean" yarn cache clean || warn "'yarn cache clean' failed"
    else
      warn "node is not runnable; skipping yarn cache clean (try: brew reinstall node)"
    fi
  fi

  if command -v pnpm >/dev/null 2>&1; then
    any=1
    if (( node_ok )); then
      run_cmd "pnpm store prune" pnpm store prune || warn "'pnpm store prune' failed"
    else
      warn "node is not runnable; skipping pnpm store prune (try: brew reinstall node)"
    fi
  fi

  if command -v pip3 >/dev/null 2>&1; then
    any=1
    # pip may print "WARNING: No matching packages" even with -q; filter that noise from the
    # terminal while keeping full output in the log.
    if (( DRY_RUN )); then
      run_cmd "pip3 cache purge" pip3 cache purge -q || warn "'pip3 cache purge' failed"
    else
      echo "# $(date '+%H:%M:%S') [pip3 cache purge] >> pip3 cache purge -q" >>"$LOG_FILE"
      local rc=0
      pip3 cache purge -q 2>&1 \
        | tee -a "$LOG_FILE" \
        | awk '!/^WARNING: No matching packages$/'
      rc="${PIPESTATUS[0]}"
      if (( rc != 0 )); then STEP_WARN_COUNT=$(( STEP_WARN_COUNT + 1 )); fi
    fi
  elif command -v pip >/dev/null 2>&1; then
    any=1
    if (( DRY_RUN )); then
      run_cmd "pip cache purge" pip cache purge -q || warn "'pip cache purge' failed"
    else
      echo "# $(date '+%H:%M:%S') [pip cache purge] >> pip cache purge -q" >>"$LOG_FILE"
      local rc=0
      pip cache purge -q 2>&1 \
        | tee -a "$LOG_FILE" \
        | awk '!/^WARNING: No matching packages$/'
      rc="${PIPESTATUS[0]}"
      if (( rc != 0 )); then STEP_WARN_COUNT=$(( STEP_WARN_COUNT + 1 )); fi
    fi
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
  if ! command -v docker >/dev/null 2>&1; then
    warn "docker not on PATH"
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    warn "docker daemon not reachable"
    return 1
  fi

  # Safety: avoid pruning a remote Docker context.
  local ctx host
  ctx="$(docker context show 2>/dev/null || true)"
  host="$(docker context inspect "${ctx:-default}" --format '{{ (index .Endpoints "docker").Host }}' 2>/dev/null || true)"
  if [[ -n "$host" ]] && [[ "$host" != unix://* ]]; then
    warn "docker context '${ctx:-?}' points to non-local host (${host}) — skipping prune"
    return 0
  fi

  # Size before
  local before after
  before="$(docker system df --format '{{.Type}}\t{{.Size}}' 2>/dev/null | awk -F'\t' '{print $1": "$2}' | paste -sd ', ' - || echo 'unknown')"
  printf "  docker disk usage: %s%s%s\n" "$C_DIM" "$before" "$C_RESET"

  # Keep tagged images, remove only dangling (<none>) ones.
  run_cmd "docker container prune -f" docker container prune -f \
    || warn "'docker container prune' failed"
  run_cmd "docker network prune -f" docker network prune -f \
    || warn "'docker network prune' failed"
  run_cmd "docker volume prune -f" docker volume prune -f \
    || warn "'docker volume prune' failed"
  run_cmd "docker image prune -f" docker image prune -f \
    || warn "'docker image prune' failed"
  run_cmd "docker builder prune -af"          docker builder prune -af \
    || warn "'docker builder prune' failed"

  after="$(docker system df --format '{{.Type}}\t{{.Size}}' 2>/dev/null | awk -F'\t' '{print $1": "$2}' | paste -sd ', ' - || echo 'unknown')"
  printf "  docker disk usage after: %s%s%s\n" "$C_DIM" "$after" "$C_RESET"
}

step_xcode() {
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

# Snapshot the current Homebrew state to a dated Brewfile so accidental
# `brew autoremove` casualties can be rebuilt: `brew bundle --file=~/.Brewfile.YYYYMMDD`.
step_brewfile_snapshot() {
  if ! command -v brew >/dev/null 2>&1; then
    warn "brew not on PATH — cannot snapshot"
    STEP_WARN_COUNT=$(( STEP_WARN_COUNT + 1 ))
    return 0
  fi
  local target="$HOME/.Brewfile.$(date +%Y%m%d)"
  if [[ -e "$target" ]] && (( DRY_RUN == 0 )); then
    info "Brewfile snapshot already exists today: $target — skipping"
    return 0
  fi
  run_cmd "brew bundle dump -> $target" brew bundle dump --force --file="$target" \
    || warn "'brew bundle dump' failed"
  if [[ -r "$target" ]]; then
    printf "  %ssaved%s %s%s%s\n" "$C_GREEN" "$C_RESET" "$C_DIM" "$target" "$C_RESET"
  fi
}

step_brew() {
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
  if ! run_cmd_tty "brew upgrade" brew upgrade; then
    warn "'brew upgrade' had issues"
    if grep -q "Command Line Tools are too outdated" "$LOG_FILE" 2>/dev/null; then
      warn "Homebrew reports Xcode Command Line Tools are outdated. Update via System Settings → Software Update, or: sudo rm -rf /Library/Developer/CommandLineTools && sudo xcode-select --install"
    fi
  fi

  if (( BREW_GREEDY )); then
    run_cmd_tty "brew upgrade --cask --greedy" brew upgrade --cask --greedy \
      || warn "'brew upgrade --cask --greedy' had issues"
  else
    run_cmd_tty "brew upgrade --cask" brew upgrade --cask \
      || warn "'brew upgrade --cask' had issues"
    info "skipping '--greedy' cask upgrades; pass --brew-greedy to include them"
  fi

  # brew cleanup may emit "Warning: Skipping <formula>: most recent version ... not installed"
  # in verbose mode; it's harmless and noisy, so filter it from the terminal while keeping
  # the full output in the log.
  if (( VERBOSE )); then
    echo "# $(date '+%H:%M:%S') [brew cleanup -s] >> brew cleanup -s" >>"$LOG_FILE"
    local rc=0
    brew cleanup -s 2>&1 \
      | tee -a "$LOG_FILE" \
      | awk '!/^Warning: Skipping .*most recent version .* not installed$/'
    rc="${PIPESTATUS[0]}"
    if (( rc != 0 )); then STEP_WARN_COUNT=$(( STEP_WARN_COUNT + 1 )); fi
  else
    run_cmd "brew cleanup -s" brew cleanup -s || warn "'brew cleanup' had issues"
  fi
  run_cmd "brew autoremove"        brew autoremove             || warn "'brew autoremove' had issues"
  if (( VERBOSE )); then
    run_cmd "brew doctor" brew doctor || warn "'brew doctor' reports issues — see log"
  fi
}

step_softwareupdate() {
  if ! command -v softwareupdate >/dev/null 2>&1; then
    warn "softwareupdate not found on PATH — skipping"
    STEP_WARN_COUNT=$(( STEP_WARN_COUNT + 1 ))
    return 0
  fi

  local su_out rc=0 cache_used=0
  if swu_cache_valid; then
    su_out="$(swu_cache_read)"
    cache_used=1
    info "using cached softwareupdate --list ($(swu_cache_age)s old, ttl ${SWU_CACHE_TTL}s; --refresh-updates to bypass)"
  else
    info "checking for macOS software updates (network call, may be slow)..."
    su_out="$(softwareupdate --list 2>&1)" || rc=$?
    echo "# softwareupdate --list output" >>"$LOG_FILE"
    printf '%s\n' "$su_out" >>"$LOG_FILE"
    (( rc == 0 )) && swu_cache_write "$su_out"
  fi
  (( cache_used )) && { echo "# softwareupdate --list (cached)" >>"$LOG_FILE"; printf '%s\n' "$su_out" >>"$LOG_FILE"; }

  if (( rc != 0 )); then
    warn "softwareupdate --list exited $rc — cannot determine update status"
    STEP_WARN_COUNT=$(( STEP_WARN_COUNT + 1 ))
    return 0
  fi

  # Both wordings have shipped: "No new software available." (modern) and
  # "No new software updates available." (older releases).
  if grep -qE "No new software( updates)? available" <<< "$su_out"; then
    ok "macOS is up to date"
    return 0
  fi

  local update_count restart_required=0
  # BSD grep on macOS may not honor \s; use the POSIX class explicitly. The
  # `|| true` keeps `set -o pipefail` happy if grep matches zero lines.
  update_count="$(grep -c '^[[:space:]]*\*' <<< "$su_out" || true)"
  grep -q "Restart: YES" <<< "$su_out" && restart_required=1

  local title_w=44 ver_w=12 size_w=9
  printf "  %sPending updates (%d):%s\n" "$C_YELLOW" "$update_count" "$C_RESET"
  printf "  %s    %-*s  %-*s  %-*s  %s%s\n" \
    "$C_DIM" "$title_w" "TITLE" "$ver_w" "VERSION" "$size_w" "SIZE" "RESTART" "$C_RESET"

  local in_entry=0 parsed_any=0 title version size_str size_kib size_human restart_tag title_trunc
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*\*[[:space:]] ]]; then
      in_entry=1
    elif (( in_entry )) && [[ "$line" == *Title:* ]]; then
      in_entry=0; parsed_any=1
      title="$(  sed -E 's/.*Title: ([^,]+).*/\1/'   <<< "$line")"
      version="$(sed -E 's/.*Version: ([^,]+).*/\1/' <<< "$line")"
      size_str="$(sed -E 's/.*Size: ([^,]+).*/\1/'   <<< "$line")"
      if [[ "$size_str" =~ ^([0-9]+)KiB$ ]]; then
        size_kib="${BASH_REMATCH[1]}"
        size_human="$(human_bytes $(( size_kib * 1024 )))"
      else
        size_human="$size_str"
      fi
      if (( ${#title} > title_w )); then
        title_trunc="${title:0:$(( title_w - 1 ))}…"
      else
        title_trunc="$title"
      fi
      restart_tag=""
      [[ "$line" == *'Restart: YES'* ]] && restart_tag="${C_YELLOW}↺ restart${C_RESET}"
      printf "  %s•%s  %-*s  %s%-*s%s  %s%-*s%s  %s\n" \
        "$C_CYAN" "$C_RESET" \
        "$title_w" "$title_trunc" \
        "$C_DIM" "$ver_w"  "$version"    "$C_RESET" \
        "$C_DIM" "$size_w" "$size_human" "$C_RESET" \
        "$restart_tag"
    else
      in_entry=0
    fi
  done <<< "$su_out"

  # Fallback for older softwareupdate output formats that omit the
  # "Title: ..., Version: ..., Size: ..." line entirely.
  if (( parsed_any == 0 )); then
    while IFS= read -r line; do
      [[ "$line" =~ ^[[:space:]]*\* ]] || continue
      printf "  %s%s%s\n" "$C_DIM" "$line" "$C_RESET"
    done <<< "$su_out"
  fi

  (( restart_required )) && warn "one or more updates require a restart"

  if (( INSTALL_UPDATES == 0 )); then
    info "to install: run with --install-updates or: sudo softwareupdate --install --all"
    return 0
  fi

  if ! run_cmd_tty "softwareupdate --install --all" softwareupdate --install --all; then
    warn "softwareupdate --install --all exited non-zero — check log"
    return 1
  fi

  if (( restart_required )); then
    warn "updates installed — a restart is required to complete the process"
  else
    ok "all updates installed"
  fi
}

# The version managers themselves (pyenv/tfenv/goenv/tenv/helm,
# gcloud-cli cask) are already upgraded by the brew step above. The steps
# below refresh what sits on top of them; each is intentionally isolated so
# it can be skipped independently (and so failures don't mask each other).
# None of them auto-install new Python/Go/Terraform majors — that's an
# explicit action best left to install_devtools.sh.

# App Store updates via `mas`. Skip cleanly if mas is missing or the user
# isn't signed in (mas list exits non-zero in that case).
step_mas() {
  if ! command -v mas >/dev/null 2>&1; then
    info "mas not installed — App Store updates skipped"
    return 0
  fi
  if ! mas list >/dev/null 2>&1; then
    warn "mas present but App Store sign-in not detected — skipping"
    STEP_WARN_COUNT=$(( STEP_WARN_COUNT + 1 ))
    return 0
  fi
  local outdated
  outdated="$(mas outdated 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$outdated" == "0" ]]; then
    ok "App Store apps are up to date"
    return 0
  fi
  printf "  %s%s outdated App Store app(s):%s\n" "$C_YELLOW" "$outdated" "$C_RESET"
  mas outdated 2>/dev/null | sed "s/^/    /" || true
  run_cmd "mas upgrade" mas upgrade || warn "'mas upgrade' failed"
}

# pipx-installed CLIs (poetry, ansible, pre-commit, etc.) drift behind PyPI;
# `pipx upgrade-all` is the canonical fix.
step_pipx() {
  if ! command -v pipx >/dev/null 2>&1; then
    info "pipx not installed — skipping"
    return 0
  fi
  run_cmd "pipx upgrade-all" pipx upgrade-all || warn "'pipx upgrade-all' failed"
}

# rustup's own self-update + the active toolchain.
step_rustup() {
  if ! command -v rustup >/dev/null 2>&1; then
    info "rustup not installed — skipping"
    return 0
  fi
  run_cmd "rustup self update"     rustup self update    || warn "'rustup self update' failed"
  run_cmd "rustup update stable"   rustup update stable  || warn "'rustup update stable' failed"
}

# mise / asdf — the multi-language version managers. We only self-update them
# here (their installed languages are an explicit user decision).
step_mise() {
  local touched=0
  if command -v mise >/dev/null 2>&1; then
    touched=1
    run_cmd "mise self-update" mise self-update || warn "'mise self-update' failed"
    run_cmd "mise upgrade"     mise upgrade     || warn "'mise upgrade' failed"
  fi
  if command -v asdf >/dev/null 2>&1; then
    touched=1
    run_cmd "asdf update"        asdf update                   || warn "'asdf update' failed"
    run_cmd "asdf plugin update --all" asdf plugin update --all || warn "'asdf plugin update --all' failed"
  fi
  if (( touched == 0 )); then info "mise / asdf not installed — skipping"; fi
}

# Update extensions for VSCode / Cursor / VSCodium when their CLIs are present.
step_vscode_extensions() {
  local touched=0
  for cli in code cursor codium; do
    if command -v "$cli" >/dev/null 2>&1; then
      touched=1
      run_cmd "$cli --update-extensions" "$cli" --update-extensions \
        || warn "'$cli --update-extensions' failed"
    fi
  done
  if (( touched == 0 )); then info "no VSCode-family CLI on PATH — skipping"; fi
}

# Time Machine keeps "local snapshots" on / that are invisible to du and can
# eat tens of gigabytes. Trim them when free space dropped below the trigger.
step_tmutil_snapshots() {
  if ! command -v tmutil >/dev/null 2>&1; then
    info "tmutil not on PATH — skipping"
    return 0
  fi
  local free_now snaps
  free_now="$(disk_free_bytes)"
  snaps="$(tmutil listlocalsnapshots / 2>/dev/null || true)"
  if [[ -z "$snaps" ]]; then
    info "no local Time Machine snapshots on /"
    return 0
  fi
  local count
  count="$(grep -c . <<<"$snaps" || true)"
  printf "  %s%d local snapshots on /%s\n" "$C_DIM" "$count" "$C_RESET"

  if (( free_now >= TMUTIL_SNAPSHOT_TRIGGER_BYTES )); then
    info "free space $(human_bytes "$free_now") above trigger $(human_bytes "$TMUTIL_SNAPSHOT_TRIGGER_BYTES") — leaving snapshots in place"
    return 0
  fi
  warn "disk is tight ($(human_bytes "$free_now") free) — thinning local snapshots"
  # Try the modern thin path first; fall back to deletelocalsnapshots if needed.
  if (( DRY_RUN )); then
    printf "  %s(dry-run) would run: tmutil thinlocalsnapshots / %d 4%s\n" \
      "$C_DIM" "$TMUTIL_SNAPSHOT_TRIGGER_BYTES" "$C_RESET"
    return 0
  fi
  if ! run_cmd "tmutil thinlocalsnapshots / $TMUTIL_SNAPSHOT_TRIGGER_BYTES 4" \
       tmutil thinlocalsnapshots / "$TMUTIL_SNAPSHOT_TRIGGER_BYTES" 4; then
    warn "'tmutil thinlocalsnapshots' had issues — falling back to deletelocalsnapshots"
    # Delete each snapshot's datestamp suffix. tmutil expects YYYY-MM-DD-HHMMSS.
    while IFS= read -r line; do
      local ts="${line##*com.apple.TimeMachine.}"
      ts="${ts%.local}"
      [[ -n "$ts" ]] || continue
      run_cmd "tmutil deletelocalsnapshots $ts" tmutil deletelocalsnapshots "$ts" \
        || warn "delete failed for $ts"
    done <<<"$snaps"
  fi
}

# Read-only audit: list ~/Library/LaunchAgents entries whose target binary is
# missing. Don't touch anything; just flag what the user should clean up by hand.
step_launchagents_audit() {
  local dir="$HOME/Library/LaunchAgents"
  if [[ ! -d "$dir" ]]; then
    info "$dir does not exist — nothing to audit"
    return 0
  fi
  shopt -s nullglob
  local plists=( "$dir"/*.plist ) target found=0
  shopt -u nullglob
  if (( ${#plists[@]} == 0 )); then
    info "no plists in $dir"
    return 0
  fi
  printf "  %sscanning %d launch agent(s)%s\n" "$C_DIM" "${#plists[@]}" "$C_RESET"
  for p in "${plists[@]}"; do
    # First non-empty <string> after a <key>Program</key> or first <string>
    # under <key>ProgramArguments</key>. Best-effort plistlib-free extraction.
    target="$(/usr/libexec/PlistBuddy -c 'Print :Program' "$p" 2>/dev/null || true)"
    if [[ -z "$target" ]]; then
      target="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$p" 2>/dev/null || true)"
    fi
    if [[ -n "$target" ]] && [[ ! -e "$target" ]]; then
      found=$(( found + 1 ))
      printf "  %sorphan:%s %s%s%s -> %smissing %s%s\n" \
        "$C_YELLOW" "$C_RESET" "$C_BOLD" "$(basename "$p")" "$C_RESET" \
        "$C_DIM" "$target" "$C_RESET"
    fi
  done
  if (( found > 0 )); then
    warn "$found orphan launch agent(s) in $dir — remove the plist or reinstall the app"
    STEP_WARN_COUNT=$(( STEP_WARN_COUNT + 1 ))
  else
    ok "no orphan launch agents"
  fi
}

# Cosmetic: invalidate Quick Look + Finder thumbnail caches. Cheap; opt-in.
step_quicklook_reset() {
  run_cmd "qlmanage -r"        qlmanage -r        || warn "'qlmanage -r' failed"
  run_cmd "qlmanage -r cache"  qlmanage -r cache  || warn "'qlmanage -r cache' failed"
  run_cmd "killall Finder"     killall Finder     || warn "Finder restart failed (may not have been running)"
}

# Helm plugins are outside of brew's world, so they go stale quickly.
# 'helm plugin update <name>' pulls the latest release for each one.
step_helm_plugins() {
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

  # Some gcloud installs on macOS require a separate Python/runtime update step.
  # Best-effort: if it exists, run it to avoid the recurring warning.
  if gcloud help components update-macos-python >/dev/null 2>&1; then
    run_cmd "gcloud components update-macos-python" gcloud components update-macos-python --quiet \
      || warn "'gcloud components update-macos-python' had issues"
  fi
}

# Report currently-active managed versions so the user can see what's in use.
# Read-only: these tools don't self-update their installed language versions;
# the brew step keeps the managers fresh, re-run install_devtools.sh to move
# to a new Python/Go/Terraform minor.
step_versions() {
  local any=0 line
  if command -v pyenv >/dev/null 2>&1; then
    any=1
    line="$(pyenv version-name 2>/dev/null || echo '?')"
    printf "  pyenv active:  %s%s%s\n" "$C_DIM" "$line" "$C_RESET"
  fi
  if command -v goenv >/dev/null 2>&1; then
    any=1
    line="$(goenv version-name 2>/dev/null || echo '?')"
    printf "  goenv active:  %s%s%s\n" "$C_DIM" "$line" "$C_RESET"
  fi
  if command -v tfenv >/dev/null 2>&1; then
    any=1
    line="$(tfenv version-name 2>/dev/null || echo '?')"
    printf "  tfenv active:  %s%s%s\n" "$C_DIM" "$line" "$C_RESET"
  fi
  if command -v tenv >/dev/null 2>&1; then
    any=1
    line="$(tenv tf current 2>/dev/null || echo '?')"
    printf "  tenv   active: %s%s%s\n" "$C_DIM" "$line" "$C_RESET"
  fi
  if command -v helm >/dev/null 2>&1; then
    any=1
    line="$(helm version --short 2>/dev/null | head -n1 || echo '?')"
    printf "  helm:          %s%s%s\n" "$C_DIM" "$line" "$C_RESET"
  fi
  if command -v gcloud >/dev/null 2>&1; then
    any=1
    line="$(gcloud version 2>/dev/null | head -n1 || echo '?')"
    printf "  gcloud:        %s%s%s\n" "$C_DIM" "$line" "$C_RESET"
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
  if (( INTERRUPTED )); then
    step "$label"
    printf "  %sskipped (interrupted)%s\n" "$C_YELLOW" "$C_RESET"
    STEPS_SKIP+=("$label (interrupted)")
    return 0
  fi
  if (( skip_flag )); then
    step "$label"
    printf "  %sskipped%s\n" "$C_DIM" "$C_RESET"
    STEPS_SKIP+=("$label")
    return 0
  fi
  # Restart the keep-alive if it died (e.g. system sleep, background SIGPIPE)
  # so sudo calls within the step never see an expired timestamp.
  if (( SUDO_AVAILABLE )) && [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
    if ! kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
      ( while true; do sudo -n true; sleep 30; kill -0 "$$" 2>/dev/null || exit; done ) &
      SUDO_KEEPALIVE_PID=$!
      disown "$SUDO_KEEPALIVE_PID" 2>/dev/null || disown || true
    fi
  fi
  do_step "$label" "$fn"
}

# Order: cheap & local first, then heavy network steps. Opt-in steps
# (brewfile-snapshot, quicklook-reset) use their own boolean directly because
# their "skip flag" is the inverse of the action flag.
run_or_skip "Purge inactive memory"                "$SKIP_MEMORY"          step_memory
run_or_skip "Flush DNS cache"                      "$SKIP_DNS"             step_dns
run_or_skip "Clear system caches"                  "$SKIP_SYSCACHES"       step_syscaches
run_or_skip "Clear user caches"                    "$SKIP_USERCACHES"      step_usercaches
run_or_skip "Empty trash"                          "$SKIP_TRASH"           step_trash
run_or_skip "Docker / OrbStack prune"              "$SKIP_DOCKER"          step_docker
run_or_skip "Xcode extras"                         "$SKIP_XCODE"           step_xcode
run_or_skip "Diagnostic / crash reports"           "$SKIP_DIAGNOSTICS"     step_diagnostics
run_or_skip "Brewfile snapshot"                    "$(( 1 - BREWFILE_SNAPSHOT ))" step_brewfile_snapshot
run_or_skip "Homebrew update / upgrade / cleanup"  "$SKIP_BREW"            step_brew
run_or_skip "macOS software update"                "$SKIP_UPDATES"         step_softwareupdate
run_or_skip "Dev-tool caches"                      "$SKIP_DEVCACHES"       step_devcaches
run_or_skip "App Store updates (mas)"              "$SKIP_MAS"             step_mas
run_or_skip "pipx upgrade-all"                     "$SKIP_PIPX"            step_pipx
run_or_skip "rustup update"                        "$SKIP_RUSTUP"          step_rustup
run_or_skip "mise / asdf self-update"              "$SKIP_MISE"            step_mise
run_or_skip "VSCode / Cursor extensions"           "$SKIP_VSCODE"          step_vscode_extensions
run_or_skip "Helm plugin refresh"                  "$SKIP_HELM_PLUGINS"    step_helm_plugins
run_or_skip "gcloud components update"             "$SKIP_GCLOUD"          step_gcloud
run_or_skip "Active tool versions"                 "$SKIP_VERSIONS"        step_versions
run_or_skip "Thin Time Machine snapshots"          "$SKIP_SNAPSHOTS"       step_tmutil_snapshots
run_or_skip "Launch agents audit"                  "$SKIP_LAUNCHAGENTS"    step_launchagents_audit
run_or_skip "Quick Look + Finder reset"            "$(( 1 - QUICKLOOK_RESET ))"   step_quicklook_reset

ELAPSED=$(( $(date +%s) - START_ALL ))
FREE_AFTER_B="$(disk_free_bytes)"
RECLAIMED_B=$(( FREE_AFTER_B - FREE_BEFORE_B ))

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
# Restore stdout if we redirected it for --summary-only so the user sees the
# card on their terminal.
if (( SUMMARY_ONLY )); then
  exec 1>&3 3>&-
fi

hr
bold "=== stay_fresh: summary ==="
printf "  elapsed:     %s\n" "$(human_duration "$ELAPSED")"
printf "  disk free:   %s -> %s  %s(%s reclaimed)%s\n" \
  "$(human_bytes "$FREE_BEFORE_B")" \
  "$(human_bytes "$FREE_AFTER_B")" \
  "$C_GREEN" "$(human_bytes "$RECLAIMED_B")" "$C_RESET"
printf "  steps freed: %s%s%s %s(sum of per-step deltas; more precise than df)%s\n" \
  "$C_GREEN" "$(human_bytes "$TOTAL_FREED_B")" "$C_RESET" "$C_DIM" "$C_RESET"
printf "  ok steps:    %s%d%s\n" "$C_GREEN"  "${#STEPS_OK[@]}"   "$C_RESET"
printf "  warn steps:  %s%d%s\n" "$C_YELLOW" "${#STEPS_WARN[@]}" "$C_RESET"
printf "  skipped:     %s%d%s\n" "$C_DIM"    "${#STEPS_SKIP[@]}" "$C_RESET"
printf "  failed:      %s%d%s\n" "$C_RED"    "${#STEPS_FAIL[@]}" "$C_RESET"

print_group() {
  local title="$1" color="$2"; shift 2
  (( $# == 0 )) && return 0
  printf "\n%s%s:%s\n" "$color" "$title" "$C_RESET"
  for item in "$@"; do printf "  - %s\n" "$item"; done
}

(( SUMMARY_ONLY == 0 )) && {
  (( ${#STEPS_OK[@]}   > 0 )) && print_group "OK"      "$C_GREEN"  "${STEPS_OK[@]}"
  (( ${#STEPS_WARN[@]} > 0 )) && print_group "Warned"  "$C_YELLOW" "${STEPS_WARN[@]}"
  (( ${#STEPS_SKIP[@]} > 0 )) && print_group "Skipped" "$C_DIM"    "${STEPS_SKIP[@]}"
  (( ${#STEPS_FAIL[@]} > 0 )) && print_group "Failed"  "$C_RED"    "${STEPS_FAIL[@]}"
}

# JSON summary — emit between the human card and the log-persistence message
# so machine parsers can pick it up without filtering colored output.
if (( JSON_SUMMARY )); then
  json_array() {
    local first=1; printf '['
    for s in "$@"; do
      (( first )) || printf ','
      first=0
      # escape: backslash, double-quote
      local esc="${s//\\/\\\\}"; esc="${esc//\"/\\\"}"
      printf '"%s"' "$esc"
    done
    printf ']'
  }
  printf '\n'
  printf '{'
  printf '"started_at":"%s",'   "$(date -u -r "$START_ALL" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")"
  printf '"ended_at":"%s",'     "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '"elapsed_seconds":%d,' "$ELAPSED"
  printf '"disk_free_before_bytes":%s,' "$FREE_BEFORE_B"
  printf '"disk_free_after_bytes":%s,'  "$FREE_AFTER_B"
  printf '"reclaimed_bytes":%s,'        "$RECLAIMED_B"
  printf '"total_freed_bytes":%s,'      "$TOTAL_FREED_B"
  printf '"interrupted":%s,'    "$( (( INTERRUPTED )) && echo true || echo false )"
  printf '"steps":{'
  printf '"ok":';   json_array "${STEPS_OK[@]}";   printf ','
  printf '"warn":'; json_array "${STEPS_WARN[@]}"; printf ','
  printf '"fail":'; json_array "${STEPS_FAIL[@]}"; printf ','
  printf '"skip":'; json_array "${STEPS_SKIP[@]}"
  printf '}}'
  printf '\n'
fi

# Write one row to history.csv for trend reporting.
EXIT_RC=0
(( ${#STEPS_FAIL[@]} > 0 )) && EXIT_RC=1
write_history_row "$ELAPSED" "$TOTAL_FREED_B" \
  "${#STEPS_OK[@]}" "${#STEPS_WARN[@]}" "${#STEPS_FAIL[@]}" "${#STEPS_SKIP[@]}" "$EXIT_RC"

echo
if (( ${#STEPS_FAIL[@]} > 0 || ${#STEPS_WARN[@]} > 0 )); then
  mkdir -p "$PERSISTENT_LOG_DIR"
  SAVED_LOG="$PERSISTENT_LOG_DIR/$(basename "$LOG_FILE")"
  if mv "$LOG_FILE" "$SAVED_LOG" 2>/dev/null; then
    :
  elif cp "$LOG_FILE" "$SAVED_LOG" 2>/dev/null; then
    rm -f "$LOG_FILE"
  else
    SAVED_LOG="$LOG_FILE"
  fi
  find "$PERSISTENT_LOG_DIR" -name 'stay_fresh-*.log' -type f \
    | sort -r | tail -n +"$(( MAX_PERSISTENT_LOGS + 1 ))" \
    | xargs rm -f 2>/dev/null || true
  warn "log saved: $SAVED_LOG"
  printf "  %sTo inspect:%s tail -80 '%s'\n" "$C_DIM" "$C_RESET" "$SAVED_LOG"
else
  rm -f "$LOG_FILE"
  info "run clean — log discarded"
fi

# macOS notification — fire-and-forget; controlled by --no-notify.
if (( ${#STEPS_FAIL[@]} > 0 )); then
  notify_user "stay_fresh: failures" \
    "${#STEPS_FAIL[@]} failed, ${#STEPS_WARN[@]} warned. Log: $PERSISTENT_LOG_DIR/"
elif (( ${#STEPS_WARN[@]} > 0 )); then
  notify_user "stay_fresh: warnings" \
    "${#STEPS_WARN[@]} step(s) warned. $(human_bytes "$TOTAL_FREED_B") freed."
else
  notify_user "stay_fresh: clean" \
    "$(human_bytes "$TOTAL_FREED_B") freed in $(human_duration "$ELAPSED")."
fi

if (( EXIT_RC != 0 )); then
  exit "$EXIT_RC"
fi

ok "You're fresh. Consider a reboot if things still feel sluggish."
