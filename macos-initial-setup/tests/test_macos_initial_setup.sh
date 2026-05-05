#!/usr/bin/env bash
# Run from the Linux tester container; repo root is mounted at /repo.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/repo}"
M="$REPO_ROOT/macos-initial-setup"
MT="$REPO_ROOT/mikrotik"
VERBOSE="${VERBOSE:-0}"

if [[ ! -d "$M" ]]; then
  echo "expected macos-initial-setup at $M" >&2
  exit 1
fi

SECONDS=0
failures=0
passed=0
ok()  { ((++passed)); echo "[ ok ] $*"; }
err() { ((++failures)); echo "[fail] $*" >&2; }

phase() {
  echo ""
  echo "=== $* ==="
}

if [[ "$VERBOSE" == "1" ]]; then
  phase "environment"
  bash --version | head -n 1
  shellcheck --version | head -n 1
  zsh --version
fi

# Every *.sh directly under macos-initial-setup/ (not subfolders).
sh_scripts=()
while IFS= read -r -d '' f; do
  sh_scripts+=("$f")
done < <(find "$M" -maxdepth 1 -type f -name '*.sh' -print0 | sort -z)

if ((${#sh_scripts[@]} == 0)); then
  err "no *.sh found in $M"
  echo "=== $failures test(s) failed ===" >&2
  exit 1
fi

phase "bash -n (syntax)"
for f in "${sh_scripts[@]}"; do
  if bash -n "$f"; then
    ok "bash -n ${f#"$REPO_ROOT/"}"
  else
    err "bash -n ${f#"$REPO_ROOT/"}"
  fi
done

if [[ -f "$MT/pull_router_backups.sh" ]]; then
  if bash -n "$MT/pull_router_backups.sh"; then
    ok "bash -n ${MT#"$REPO_ROOT/"}/pull_router_backups.sh"
  else
    err "bash -n ${MT#"$REPO_ROOT/"}/pull_router_backups.sh"
  fi
else
  err "missing $MT/pull_router_backups.sh"
fi

phase "shellcheck (severity error)"
for f in "${sh_scripts[@]}"; do
  rel="${f#"$REPO_ROOT/"}"
  if shellcheck --severity=error -x -s bash "$f"; then
    ok "shellcheck (bash) $rel"
  else
    err "shellcheck (bash) $rel"
  fi
done

if [[ -f "$MT/pull_router_backups.sh" ]]; then
  rel="${MT#"$REPO_ROOT/"}/pull_router_backups.sh"
  if shellcheck --severity=error -x -s bash "$MT/pull_router_backups.sh"; then
    ok "shellcheck (bash) $rel"
  else
    err "shellcheck (bash) $rel"
  fi
fi

zsh_file="$M/zsh_aliases.zsh"
if [[ -f "$zsh_file" ]]; then
  set +e
  sc_err="$(shellcheck --severity=error -s zsh "$zsh_file" 2>&1)"
  sc_rc=$?
  set -e
  if [[ "$sc_rc" -eq 0 ]]; then
    ok "shellcheck (zsh) ${zsh_file#"$REPO_ROOT/"}"
  elif grep -q "Unknown shell" <<<"$sc_err"; then
    ok "shellcheck (zsh) skipped (no zsh in this shellcheck build)"
  else
    echo "$sc_err" >&2
    err "shellcheck (zsh) ${zsh_file#"$REPO_ROOT/"}"
  fi
else
  err "missing $zsh_file"
fi

phase "--help (before macOS preflight)"
if "$M/install_apps.sh" --help >/dev/null; then ok "install_apps.sh --help"; else err "install_apps.sh --help"; fi
if "$M/install_devtools.sh" --help >/dev/null; then ok "install_devtools.sh --help"; else err "install_devtools.sh --help"; fi
if "$M/stay_fresh.sh" --help >/dev/null; then ok "stay_fresh.sh --help"; else err "stay_fresh.sh --help"; fi
if "$M/v1_stay_fresh.sh" --help >/dev/null; then ok "v1_stay_fresh.sh --help"; else err "v1_stay_fresh.sh --help"; fi
if "$M/workstation_doctor.sh" --help >/dev/null; then ok "workstation_doctor.sh --help"; else err "workstation_doctor.sh --help"; fi

if [[ -f "$MT/pull_router_backups.sh" ]]; then
  if "$MT/pull_router_backups.sh" --help >/dev/null; then ok "pull_router_backups.sh --help"; else err "pull_router_backups.sh --help"; fi
  if "$MT/pull_router_backups.sh" -h >/dev/null; then ok "pull_router_backups.sh -h"; else err "pull_router_backups.sh -h"; fi
fi

phase "unknown CLI flags (parsed before preflight)"
set +e
out_ia="$("$M/install_apps.sh" --definitely-not-a-valid-flag-12345 2>&1)"; rc_ia=$?
set -e
if [[ "$rc_ia" -eq 3 ]]; then
  ok "install_apps.sh unknown flag -> exit 3"
else
  err "install_apps.sh unknown flag: expected exit 3, got $rc_ia: $out_ia"
fi

set +e
out_id="$("$M/install_devtools.sh" --definitely-not-a-valid-flag-99999 2>&1)"; rc_id=$?
set -e
if [[ "$rc_id" -eq 3 ]]; then
  ok "install_devtools.sh unknown flag -> exit 3"
else
  err "install_devtools.sh unknown flag: expected exit 3, got $rc_id: $out_id"
fi

set +e
out_sf="$("$M/stay_fresh.sh" --definitely-not-a-valid-flag-abcde 2>&1)"; rc_sf=$?
set -e
if [[ "$rc_sf" -eq 3 ]]; then
  ok "stay_fresh.sh unknown flag -> exit 3"
else
  err "stay_fresh.sh unknown flag: expected exit 3, got $rc_sf: $out_sf"
fi

set +e
out_v1="$("$M/v1_stay_fresh.sh" --definitely-not-a-valid-flag-v1 2>&1)"; rc_v1=$?
set -e
if [[ "$rc_v1" -eq 2 ]]; then
  ok "v1_stay_fresh.sh unknown flag -> exit 2"
else
  err "v1_stay_fresh.sh unknown flag: expected exit 2, got $rc_v1: $out_v1"
fi

set +e
out_wd="$("$M/workstation_doctor.sh" --definitely-not-a-valid-flag-xyz 2>&1)"; rc_wd=$?
set -e
if [[ "$rc_wd" -eq 3 ]]; then
  ok "workstation_doctor.sh unknown flag -> exit 3"
else
  err "workstation_doctor.sh unknown flag: expected exit 3, got $rc_wd: $out_wd"
fi

phase "Linux preflight (exit 2, macOS only)"
if [[ "$(uname -s)" == "Linux" ]]; then
  for script in install_apps.sh install_devtools.sh stay_fresh.sh; do
    set +e
    out="$("$M/$script" --dry-run 2>&1)"; rc=$?
    set -e
    if [[ "$rc" -ne 2 ]]; then
      err "$script: expected exit 2 on Linux, got $rc"
    elif ! grep -q "macOS" <<<"$out"; then
      err "$script: expected 'macOS' in stderr on Linux"
    else
      ok "$script --dry-run: Linux preflight -> exit 2 (macOS only)"
    fi
  done
  # workstation_doctor has no --dry-run; unknown flags exit 3 before preflight.
  set +e
  out_wd_linux="$("$M/workstation_doctor.sh" 2>&1)"; rc_wd_linux=$?
  set -e
  if [[ "$rc_wd_linux" -ne 2 ]]; then
    err "workstation_doctor.sh: expected exit 2 on Linux, got $rc_wd_linux"
  elif ! grep -q "macOS" <<<"$out_wd_linux"; then
    err "workstation_doctor.sh: expected 'macOS' in stderr on Linux"
  else
    ok "workstation_doctor.sh: Linux preflight -> exit 2 (macOS only)"
  fi
else
  ok "skipping Linux preflight assertions (unusual host OS: $(uname -s))"
fi

phase "zsh_aliases.zsh"
if zsh -f -c "source '$M/zsh_aliases.zsh'"; then
  ok "zsh: source zsh_aliases.zsh"
else
  err "zsh: source zsh_aliases.zsh"
fi

echo ""
if (( failures )); then
  echo "=== failed: $failures  passed: $passed  time: ${SECONDS}s ===" >&2
  exit 1
fi
echo "=== all macos-initial-setup (docker) checks passed ($passed ok, ${SECONDS}s) ==="
exit 0
