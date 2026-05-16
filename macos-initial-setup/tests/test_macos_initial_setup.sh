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

# Run a command; assert exit code. Extra args: label (for ok/err messages).
run_expect_rc() {
  local expected="$1" label="$2"; shift 2
  set +e
  local out rc
  out="$("$@" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -eq "$expected" ]]; then
    ok "$label -> exit $expected"
  else
    err "$label: expected exit $expected, got $rc: $out"
  fi
}

# stay_fresh.sh on Linux: flag must parse (exit 2), not unknown-option (exit 3).
stay_fresh_linux_parses() {
  local label="stay_fresh.sh $*"
  run_expect_rc 2 "$label" "$M/stay_fresh.sh" "$@" --dry-run
}

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
run_expect_rc 3 "install_apps.sh unknown flag" \
  "$M/install_apps.sh" --definitely-not-a-valid-flag-12345
run_expect_rc 3 "install_devtools.sh unknown flag" \
  "$M/install_devtools.sh" --definitely-not-a-valid-flag-12345
run_expect_rc 3 "stay_fresh.sh unknown flag" \
  "$M/stay_fresh.sh" --definitely-not-a-valid-flag-12345
run_expect_rc 3 "install_devtools.sh bad --manager" \
  "$M/install_devtools.sh" --manager definitely-not-valid

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

# --- stay_fresh: every documented flag must parse on Linux (exit 2, not 3) ---
if [[ "$(uname -s)" == "Linux" ]]; then
  for flag in \
    --skip-memory --skip-dns --skip-syscaches --skip-usercaches --skip-trash \
    --skip-docker --skip-xcode --skip-diagnostics --skip-brew --skip-updates \
    --skip-devcaches --skip-devtools --skip-helm-plugins --skip-gcloud \
    --skip-versions --skip-mas --skip-pipx --skip-rustup --skip-mise \
    --skip-vscode --skip-snapshots --skip-launchagents \
    --dry-run --yes -y -v --verbose --summary-only --json --no-sudo --no-notify \
    --force --install-updates --refresh-updates --brew-greedy \
    --brewfile-snapshot --quicklook-reset; do
    stay_fresh_linux_parses "$flag"
  done

  stay_fresh_linux_parses --only=docker,brew
fi

# --- --print-config / --history short-circuit before preflight (exit 0) ---
set +e
cfg_out="$("$M/stay_fresh.sh" --print-config 2>&1)"
cfg_rc=$?
hist_out="$("$M/stay_fresh.sh" --history 2>&1)"
hist_rc=$?
set -e
if [[ "$cfg_rc" -eq 0 ]] && grep -q 'parsed config' <<<"$cfg_out"; then
  ok "stay_fresh.sh --print-config -> exit 0 with banner"
else
  err "stay_fresh.sh --print-config: missing banner or non-zero exit (rc=$cfg_rc)"
fi
if [[ "$hist_rc" -eq 0 ]] && grep -qE 'no history yet|stay_fresh history' <<<"$hist_out"; then
  ok "stay_fresh.sh --history -> exit 0 with expected output"
else
  err "stay_fresh.sh --history: unexpected output or non-zero exit (rc=$hist_rc)"
fi

# --- --print-config reflects flags ---
pc="$("$M/stay_fresh.sh" --skip-docker --dry-run --print-config 2>&1)" || pc=""
if grep -q 'SKIP_DOCKER.*= 1' <<<"$pc" && grep -q 'DRY_RUN.*= 1' <<<"$pc"; then
  ok "stay_fresh.sh --print-config shows --skip-docker and --dry-run"
else
  err "stay_fresh.sh --print-config: expected SKIP_DOCKER=1 and DRY_RUN=1"
fi

pc_dt="$("$M/stay_fresh.sh" --skip-devtools --print-config 2>&1)" || pc_dt=""
devtools_ok=1
for v in SKIP_MAS SKIP_PIPX SKIP_RUSTUP SKIP_MISE SKIP_VSCODE \
         SKIP_HELM_PLUGINS SKIP_GCLOUD SKIP_VERSIONS; do
  if ! grep -q "${v}.*= 1" <<<"$pc_dt"; then
    devtools_ok=0
    break
  fi
done
if (( devtools_ok )); then
  ok "stay_fresh.sh --skip-devtools fans out to dev-tool skip flags"
else
  err "stay_fresh.sh --skip-devtools: not all dev skip flags set in --print-config"
fi

pc_only="$("$M/stay_fresh.sh" --only quicklook --print-config 2>&1)" || pc_only=""
if grep -q 'QUICKLOOK_RESET.*= 1' <<<"$pc_only" \
   && grep -q -- '--only filter active:.*quicklook' <<<"$pc_only"; then
  ok "stay_fresh.sh --only quicklook enables opt-in step in --print-config"
else
  err "stay_fresh.sh --only quicklook: QUICKLOOK_RESET or --only banner missing"
fi

# --- config file defaults (XDG_CONFIG_HOME), overridable by CLI ---
cfg_root="$(mktemp -d)"
mkdir -p "$cfg_root/stay_fresh"
printf '%s\n' 'SKIP_MEMORY=1' 'DRY_RUN=0' >"$cfg_root/stay_fresh/config"
pc_cfg="$(
  XDG_CONFIG_HOME="$cfg_root" "$M/stay_fresh.sh" --print-config 2>&1
)" || pc_cfg=""
rm -rf "$cfg_root"
if grep -q 'SKIP_MEMORY.*= 1' <<<"$pc_cfg" && grep -q 'DRY_RUN.*= 0' <<<"$pc_cfg"; then
  ok "stay_fresh.sh loads KEY=value from config file"
else
  err "stay_fresh.sh config file: SKIP_MEMORY=1 / DRY_RUN=0 not reflected in --print-config"
fi

cfg_root="$(mktemp -d)"
mkdir -p "$cfg_root/stay_fresh"
printf '%s\n' 'DRY_RUN=0' >"$cfg_root/stay_fresh/config"
pc_override="$(
  XDG_CONFIG_HOME="$cfg_root" "$M/stay_fresh.sh" --dry-run --print-config 2>&1
)" || pc_override=""
rm -rf "$cfg_root"
if grep -q 'DRY_RUN.*= 1' <<<"$pc_override"; then
  ok "stay_fresh.sh CLI flag overrides config file (DRY_RUN)"
else
  err "stay_fresh.sh config + CLI: --dry-run should set DRY_RUN=1 over config DRY_RUN=0"
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

# --- conflicting flags caught up front -> exit 3 ---
run_expect_rc 3 "stay_fresh.sh --install-updates + --skip-updates" \
  "$M/stay_fresh.sh" --install-updates --skip-updates
run_expect_rc 3 "stay_fresh.sh --skip-brew + --brew-greedy" \
  "$M/stay_fresh.sh" --skip-brew --brew-greedy
run_expect_rc 3 "stay_fresh.sh --skip-brew + --brewfile-snapshot" \
  "$M/stay_fresh.sh" --skip-brew --brewfile-snapshot

# --- every --only step key is accepted (Linux preflight after parse) ---
if [[ "$(uname -s)" == "Linux" ]]; then
  step_keys=(
    memory dns syscaches usercaches trash docker xcode diagnostics
    brew brewfile-snapshot updates devcaches mas pipx rustup mise vscode
    helm-plugins gcloud versions snapshots launchagents quicklook
  )
  for k in "${step_keys[@]}"; do
    if [[ "$k" == "brewfile-snapshot" ]]; then
      # Opt-in snapshot step requires brew to run; --only brewfile-snapshot alone
      # leaves SKIP_BREW=1 and trips flag validation (exit 3).
      run_expect_rc 3 "stay_fresh.sh --only brewfile-snapshot (needs brew)" \
        "$M/stay_fresh.sh" --only brewfile-snapshot --dry-run
      stay_fresh_linux_parses --only brew,brewfile-snapshot
    else
      stay_fresh_linux_parses --only "$k"
    fi
  done
fi

# --- install_apps / install_devtools flags parse on Linux ---
if [[ "$(uname -s)" == "Linux" ]]; then
  for flag in --skip-gcloud --skip-cli-ops --skip-upgrade --no-cleanup \
              --no-gcloud-components; do
    run_expect_rc 2 "install_apps.sh $flag" \
      "$M/install_apps.sh" "$flag" --dry-run
  done
  for flag in --skip-python --skip-terraform --skip-go --skip-helm \
              --no-helm-plugins --setup-shell; do
    run_expect_rc 2 "install_devtools.sh $flag" \
      "$M/install_devtools.sh" "$flag" --dry-run
  done
  run_expect_rc 2 "install_devtools.sh --manager mise" \
    "$M/install_devtools.sh" --manager mise --dry-run
fi

# --- short -h exits 0 before preflight ---
run_expect_rc 0 "stay_fresh.sh -h" "$M/stay_fresh.sh" -h

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
