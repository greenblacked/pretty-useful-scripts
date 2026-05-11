#!/usr/bin/env bash
# Run from the Linux tester container; repo root is mounted at /repo.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/repo}"
M="$REPO_ROOT/macos-initial-setup"

if [[ ! -d "$M" ]]; then
  echo "expected macos-initial-setup at $M" >&2
  exit 1
fi

failures=0
ok()  { echo "[ ok ] $*"; }
err() { echo "[fail] $*" >&2; failures=$((failures + 1)); }

# --- bash -n (syntax) ---
sh_scripts=(
  "$M/install_apps.sh"
  "$M/install_devtools.sh"
  "$M/stay_fresh.sh"
  "$M/v1_stay_fresh.sh"
)
for f in "${sh_scripts[@]}"; do
  if bash -n "$f"; then
    ok "bash -n ${f#"$REPO_ROOT/"}"
  else
    err "bash -n ${f#"$REPO_ROOT/"}"
  fi
done

# --- shellcheck (errors only; warnings are too noisy for legacy/v1 script style) ---
for f in "${sh_scripts[@]}"; do
  rel="${f#"$REPO_ROOT/"}"
  if shellcheck --severity=error -x -s bash "$f"; then
    ok "shellcheck (bash) $rel"
  else
    err "shellcheck (bash) $rel"
  fi
done

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

# --- --help (must work before macOS preflight) ---
if "$M/install_apps.sh" --help >/dev/null; then ok "install_apps.sh --help"; else err "install_apps.sh --help"; fi
if "$M/install_devtools.sh" --help >/dev/null; then ok "install_devtools.sh --help"; else err "install_devtools.sh --help"; fi
if "$M/stay_fresh.sh" --help >/dev/null; then ok "stay_fresh.sh --help"; else err "stay_fresh.sh --help"; fi
if "$M/v1_stay_fresh.sh" --help >/dev/null; then ok "v1_stay_fresh.sh --help"; else err "v1_stay_fresh.sh --help"; fi

# --- unknown CLI -> exit 3 (parsed before preflight) ---
set +e
out_ia="$("$M/install_apps.sh" --definitely-not-a-valid-flag-12345 2>&1)"; rc_ia=$?
set -e
if [[ "$rc_ia" -eq 3 ]]; then
  ok "install_apps.sh unknown flag -> exit 3"
else
  err "install_apps.sh unknown flag: expected exit 3, got $rc_ia: $out_ia"
fi

# --- Linux / non-Darwin: preflight should reject (documented exit 2) ---
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
      ok "$script: Linux preflight -> exit 2 (macOS only)"
    fi
  done
else
  ok "skipping Linux preflight assertions (unusual host OS: $(uname -s))"
fi

# --- --skip-updates must be recognized (exit 2 on Linux, not exit 3) ---
if [[ "$(uname -s)" == "Linux" ]]; then
  set +e
  out_su="$("$M/stay_fresh.sh" --skip-updates --dry-run 2>&1)"; rc_su=$?
  set -e
  if [[ "$rc_su" -eq 2 ]]; then
    ok "stay_fresh.sh --skip-updates recognized (exit 2, not 3)"
  else
    err "stay_fresh.sh --skip-updates: expected exit 2 (macOS preflight), got $rc_su: $out_su"
  fi
fi

# --- new skip flags must all parse cleanly (exit 2 on Linux, not exit 3) ---
if [[ "$(uname -s)" == "Linux" ]]; then
  for flag in --skip-mas --skip-pipx --skip-rustup --skip-mise --skip-vscode \
              --skip-snapshots --skip-launchagents --quicklook-reset \
              --brewfile-snapshot --refresh-updates --force --summary-only --json; do
    set +e
    out="$("$M/stay_fresh.sh" "$flag" --dry-run 2>&1)"; rc=$?
    set -e
    if [[ "$rc" -eq 2 ]]; then
      ok "stay_fresh.sh $flag parsed (exit 2)"
    else
      err "stay_fresh.sh $flag: expected exit 2, got $rc"
    fi
  done
fi

# --- --print-config / --history short-circuit before preflight (exit 0) ---
if "$M/stay_fresh.sh" --print-config >/dev/null 2>&1; then
  ok "stay_fresh.sh --print-config -> exit 0"
else
  err "stay_fresh.sh --print-config: non-zero exit"
fi
if "$M/stay_fresh.sh" --history >/dev/null 2>&1; then
  ok "stay_fresh.sh --history -> exit 0"
else
  err "stay_fresh.sh --history: non-zero exit"
fi

# --- --only validation: unknown step -> exit 3 (CLI error) ---
set +e
out_only_bad="$("$M/stay_fresh.sh" --only definitely-not-a-step 2>&1)"; rc_only_bad=$?
set -e
if [[ "$rc_only_bad" -eq 3 ]]; then
  ok "stay_fresh.sh --only <bogus> -> exit 3"
else
  err "stay_fresh.sh --only <bogus>: expected exit 3, got $rc_only_bad"
fi

# --- --only with valid keys must parse (exit 2 on Linux preflight) ---
if [[ "$(uname -s)" == "Linux" ]]; then
  set +e
  out_only_ok="$("$M/stay_fresh.sh" --only memory,dns --dry-run 2>&1)"; rc_only_ok=$?
  set -e
  if [[ "$rc_only_ok" -eq 2 ]]; then
    ok "stay_fresh.sh --only memory,dns parsed (exit 2)"
  else
    err "stay_fresh.sh --only memory,dns: expected exit 2, got $rc_only_ok"
  fi
fi

# --- conflicting flags caught up front: --install-updates + --skip-updates -> exit 3 ---
set +e
out_conf="$("$M/stay_fresh.sh" --install-updates --skip-updates 2>&1)"; rc_conf=$?
set -e
if [[ "$rc_conf" -eq 3 ]]; then
  ok "stay_fresh.sh conflicting --install-updates/--skip-updates -> exit 3"
else
  err "stay_fresh.sh conflicting flags: expected exit 3, got $rc_conf"
fi

# --- zsh_aliases: must source cleanly in zsh (Linux) ---
if zsh -f -c "source '$M/zsh_aliases.zsh'"; then
  ok "zsh: source zsh_aliases.zsh"
else
  err "zsh: source zsh_aliases.zsh"
fi

if (( failures )); then
  echo "=== $failures test(s) failed ===" >&2
  exit 1
fi
echo "=== all macos-initial-setup (docker) checks passed ==="
exit 0
