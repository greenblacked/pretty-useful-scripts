# macOS Initial Setup

> Opinionated, idempotent shell scripts for provisioning and maintaining
> a macOS workstation.

This folder is the macOS setup package inside the broader helper-scripts
repository. It turns the normal "fresh Mac checklist" — install apps, wire
up language toolchains, keep caches and Homebrew under control — into a set
of small, composable scripts that are safe to run today, next month, and on
the next machine. Every change is previewable with `--dry-run`, written to a
log in `$TMPDIR` while running, and opt-out at a per-feature level.
`stay_fresh.sh` discards its log on a clean run and only persists it
(`~/Library/Logs/stay_fresh/`, keeping the 10 most recent) when a step warns
or fails.

**Platform:** macOS 12+ (Monterey through the current release) on Apple
Silicon and Intel. **Shell:** `bash` for scripts (`#!/usr/bin/env bash`),
`zsh` for the aliases file.

## Table of contents

- [TL;DR](#tldr)
- [Folder map](#folder-map)
- [Lifecycle: when to run what](#lifecycle-when-to-run-what)
- [Design principles](#design-principles)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [`install_apps.sh`](#install_appssh)
- [`install_devtools.sh`](#install_devtoolssh)
- [`stay_fresh.sh`](#stay_freshsh)
- [`v1_stay_fresh.sh`](#v1_stay_freshsh)
- [`zsh_aliases.zsh`](#zsh_aliaseszsh)
- [What this changes on your machine](#what-this-changes-on-your-machine)
- [Development: Docker checks](#development--docker-checks)

## TL;DR

For returning users. Every command is idempotent.

```bash
# First run on a new machine
./install_apps.sh                        # cask apps + DevOps CLIs + Google Cloud SDK
./install_devtools.sh --setup-shell      # Python, Terraform, Go, Helm

# Regular maintenance (weekly is a good cadence)
./stay_fresh.sh                          # purge, cleanup, upgrade, report
./stay_fresh.sh --dry-run                # preview without changes

# One-off previews
./install_apps.sh     --dry-run --verbose
./install_devtools.sh --dry-run --verbose
```

After linking `zsh_aliases.zsh`, the same three are available as
`install-apps`, `install-devtools`, and `stay-fresh`.

## Folder map

| File | Use it for |
| --- | --- |
| `install_apps.sh` | Day-one workstation apps, Homebrew casks/formulae, platform CLIs, and Google Cloud SDK. |
| `install_devtools.sh` | Language and infrastructure toolchains: Python, Terraform, Go, Helm, and version managers. |
| `stay_fresh.sh` | Recurring maintenance: cleanup, updates, cache pruning, and version reporting. |
| `v1_stay_fresh.sh` | Legacy minimal maintenance flow kept for reference and simple one-off runs. |
| `zsh_aliases.zsh` | Optional interactive-shell aliases and helper functions. |
| `tests/` | Docker-based **static** checks (ShellCheck, `bash -n`, CLI/config smoke tests, ~100 assertions). See [Development: Docker checks](#development--docker-checks). |

## Lifecycle: when to run what

The repository is organized around the life of a workstation. Each
script fills a distinct slot — understanding which slot matters more
than memorizing flags.

| Phase | Script | Typical cadence | What it touches |
| --- | --- | --- | --- |
| **Bootstrap** | `install_apps.sh` | Once per machine | `/Applications`, Homebrew Cask + formulae (e.g. `k9s`, `awscli`), Google Cloud SDK |
| **Bootstrap** | `install_devtools.sh` | Once per machine (+ version bumps) | `~/.pyenv`, `~/.goenv`, `$(brew --prefix)/bin`, optionally `~/.zshrc` |
| **Ambient** | `zsh_aliases.zsh` | Sourced on every interactive shell (after wiring into `~/.zshrc`) | Your shell only — no disk writes |
| **Recurring** | `stay_fresh.sh` | Weekly / on demand | Caches, Homebrew, Docker, Xcode, toolchains |
| **Legacy** | `v1_stay_fresh.sh` | On demand | Minimal subset of the above; no flags |

The two bootstrap scripts are independent — you can run either one
first. `stay_fresh.sh` assumes Homebrew is installed but degrades
gracefully if optional tools (Docker, `mise`, `gcloud`, etc.) are
missing.

## Design principles

These are the invariants every script upholds. They explain why the
code looks the way it does.

| Principle | What it means in practice |
| --- | --- |
| **Idempotent** | Re-running a script upgrades in place. No duplicate installs, no appended shell-rc blocks, no runaway cache. |
| **Fail-soft** | One failing step never aborts the rest of the run. Missing tools are skipped with a note, not treated as errors. |
| **Dry-run first** | `--dry-run` is supported on every script that mutates state (except the explicitly minimal `v1_stay_fresh.sh`). No `sudo` prompt is triggered in dry-run. |
| **Logged** | Every non-trivial script writes a timestamped log to `$TMPDIR` (`stay_fresh.sh` rescues it to `~/Library/Logs/stay_fresh/` on warn/fail, and discards it on a clean run). `--verbose` also streams to the terminal. |
| **No hidden writes** | Shell rc files are modified only when you pass `--setup-shell`. Every such block is bracketed by markers so it can be found and removed. |
| **Opt-out, not opt-in** | `stay_fresh.sh` has a skip flag for every step, plus a positive `--only k1,k2,...` for when you want just one or two. Defaults can be parked in `~/.config/stay_fresh/config`. `install_apps.sh` honors `--only`/`--skip` for casks, `--skip-cli-ops` / `--skip-formulae` for CLI brew packages, and gcloud component flags. |
| **Concurrency-safe** | `stay_fresh.sh` holds a PID lock file for the duration of the run and bails with exit 4 if a second invocation tries to start. Run history (with disk freed and step counts) is appended to `~/Library/Logs/stay_fresh/history.csv` for trend tracking. |
| **Sudo only when needed** | Scripts request `sudo` once at startup, keep it warm for the run, and release it on exit. Running as `root` is refused. |

## Requirements

- macOS 12 (Monterey) or newer, on Apple Silicon or Intel.
- Administrator password for a single interactive `sudo` prompt (used
  by `purge` and by Homebrew installs where applicable).
- Xcode Command Line Tools (`xcode-select --install`).
- At least 5 GB of free disk space on `/`.
- An active internet connection to `formulae.brew.sh` and GitHub.

`install_apps.sh` installs Homebrew automatically if it is missing.
The other scripts assume Homebrew is already on `PATH` — run
`install_apps.sh` first on a fresh machine, or install Homebrew
manually from <https://brew.sh>.

## Quick start

On a fresh machine:

```bash
git clone https://github.com/greenblacked/pretty-useful-scripts.git
cd pretty-useful-scripts/macos-initial-setup

./install_apps.sh     --dry-run --verbose
./install_devtools.sh --dry-run --verbose

./install_apps.sh                        # 1. cask apps + DevOps CLIs + Google Cloud SDK
./install_devtools.sh --setup-shell      # 2. language toolchains

ln -sfn "$PWD/zsh_aliases.zsh" "$HOME/.zsh_aliases.zsh"
grep -qsF '.zsh_aliases.zsh' ~/.zshrc \
  || echo '[[ -f "$HOME/.zsh_aliases.zsh" ]] && source "$HOME/.zsh_aliases.zsh"' \
       >> ~/.zshrc
exec zsh                                 # 3. reload shell with aliases + shims
```

The preflight output of `install_apps.sh` looks like this on a healthy
machine:

```text
=== install_apps: preflight checks ===
[info] log file: /tmp/install_apps-20260421-093014.log
[ok  ] macOS 14.5 (23F79) on arm64
[ok  ] bash 3.2.57(1)-release
[ok  ] running as user: szolotov
[ok  ] internet reachable (formulae.brew.sh)
[ok  ] Xcode Command Line Tools: /Library/Developer/CommandLineTools
[ok  ] free disk space: 184G on /
[ok  ] Homebrew 4.3.8 (prefix: /opt/homebrew)
```

If any preflight check fails, the script exits with code `2` and
prints a pointed message explaining what to fix.

---

## `install_apps.sh`

Installs desktop applications via Homebrew **Cask**, a batch of **CLI
formulae** for Kubernetes and platform work (including **`k9s`**), then
the Google Cloud SDK (`gcloud-cli`) with common components. Cask apps
already present in `/Applications` but not managed by Homebrew are
**adopted** (`brew install --cask --force`) so that future upgrades flow
through `brew` instead of each vendor's auto-updater.

### Usage

```bash
./install_apps.sh                        # full install (interactive)
./install_apps.sh --dry-run --verbose    # preview and stream details
./install_apps.sh --yes                  # non-interactive
```

### Options

| Flag | Purpose |
| --- | --- |
| `--dry-run` | Show the plan; change nothing. |
| `-y`, `--yes` | Skip confirmation prompts. |
| `-v`, `--verbose` | Stream `brew` output live (also runs `brew doctor` into the log). |
| `--only a,b,c` | Install only the listed casks. |
| `--skip a,b,c` | Install everything except the listed casks. |
| `--skip-upgrade` | Do not upgrade already-installed casks or formulae. |
| `--no-cleanup` | Skip `brew cleanup` at the end of the run. |
| `--skip-gcloud` | Omit the Google Cloud SDK entirely. |
| `--skip-cli-ops` | Skip the entire Homebrew **formula** batch (see below). |
| `--skip-formulae a,b,c` | Skip individual formula names (comma-separated). |
| `--gcloud-components a,b,c` | Override the default component set. |
| `--no-gcloud-components` | Install `gcloud` core only (no components). |
| `-h`, `--help` | Show the built-in help (lists every cask and formula). |

### Bundled cask applications

**General use:** `brave-browser`, `visual-studio-code`, `cursor`,
`orbstack`, `slack`, `zoom`, `telegram`, `spotify`.

**DevOps and platform engineering (GUI):** `iterm2`, `raycast`, `github`,
`lens`, `postman`, `drawio`, `wireshark-app`, `dbeaver-community`,
`google-chrome`, `1password`, `microsoft-teams`, `notion`, `tailscale-app`,
`cloudflare-warp`, `ngrok`, `rectangle`, `alt-tab`, `maccy`, `zed`,
`sublime-text`, `jetbrains-toolbox`, `fork`, `gitkraken`,
`azure-data-studio`, `postico`, `redisinsight`, `cyberduck`, `proxyman`,
`linear-linear`, `discord`.

Pass `--skip a,b,c` to omit casks your organization provisions elsewhere.
The `ngrok` cask installs a **binary only** (no `.app`).

### Bundled CLI formulae (`brew install`)

Installed after the cask loop unless you pass `--skip-cli-ops`. Includes
**`k9s`**, **`stern`**, **`kubectx`**, **`kind`**, **`minikube`**, **`skaffold`**,
**`kustomize`**, **`helm`**, **`helmfile`**, **`krew`**, **`eksctl`**, **`argocd`**,
**`velero`**, **`cilium-cli`**, **`awscli`**, **`azure-cli`**, **`grpcurl`**,
**`terraform-docs`**, **`tflint`**, **`terragrunt`**, **`infracost`**, **`conftest`**,
**`opa`**, **`cosign`**, **`crane`**, **`dive`**, **`lazydocker`**, **`popeye`**,
**`kubescape`**, **`grype`**, **`trivy`**, **`jq`**, **`yq`**, **`httpie`**, **`hey`**,
**`vegeta`**.

Homebrew's core formula named **`flux`** is the Influx query language, not
Flux CD; for the Flux CD CLI use `brew install fluxcd/tap/flux` separately if
you need it. **`helm`** is also installed by `install_devtools.sh` — running
both scripts is safe (idempotent).

### Google Cloud SDK components

By default the script installs `gke-gcloud-auth-plugin` and `kubectl`.
It prefers `brew install <component>` and falls back to
`gcloud components install <component>` when the component is not
packaged as a Homebrew formula.

```bash
./install_apps.sh --gcloud-components gke-gcloud-auth-plugin,kubectl,beta
./install_apps.sh --no-gcloud-components
```

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Completed successfully. |
| `1` | One or more installs failed. |
| `2` | Preflight checks failed. |
| `3` | Invalid arguments. |

---

## `install_devtools.sh`

Installs developer toolchains using version managers so that multiple
versions can coexist on the same machine. The script requires Homebrew —
run `install_apps.sh` first on a fresh machine, or install Homebrew
manually.

### Which manager should I pick?

| `--manager` | Best for | Installs |
| --- | --- | --- |
| `native` *(default)* | Maximum ecosystem fidelity — each tool uses its canonical version manager. | `pyenv` + `tfenv` + `goenv` + Homebrew `helm` |
| `tenv` | Teams that also need OpenTofu or Terragrunt alongside Terraform. | `pyenv` + `tenv` + `goenv` + Homebrew `helm` |
| `mise` | A single binary for all language runtimes; fastest switching. | `mise` (Python, Terraform, Go) + Homebrew `helm` |

If you are unsure, `native` is the safest choice: each tool behaves
exactly as its upstream documentation expects.

### Usage

```bash
./install_devtools.sh                      # native managers, latest versions (interactive)
./install_devtools.sh --dry-run            # preview changes
./install_devtools.sh --yes --setup-shell  # non-interactive; wire ~/.zshrc
```

### Options

| Flag | Purpose |
| --- | --- |
| `--dry-run` | Show the plan; change nothing. |
| `-y`, `--yes` | Skip confirmation prompts. |
| `-v`, `--verbose` | Stream `brew`, `pyenv`, and builder output live. |
| `--setup-shell` | Append initialization lines to `~/.zshrc` or `~/.bashrc`. |
| `--manager native\|tenv\|mise` | Select a manager stack (default: `native`). |
| `--python-version V` | Pin Python (default: latest stable 3.x). |
| `--terraform-version V` | Pin Terraform (default: latest). |
| `--go-version V` | Pin Go (default: latest). |
| `--helm-version V` | Pin Helm (default: latest from Homebrew). |
| `--skip-python` | Do not install Python. |
| `--skip-terraform` | Do not install Terraform. |
| `--skip-go` | Do not install Go. |
| `--skip-helm` | Do not install Helm. |
| `--helm-plugins a,b,c` | Override the plugin set (default: `helm-diff`). |
| `--no-helm-plugins` | Do not install any Helm plugins. |
| `-h`, `--help` | Show the built-in help. |

Known Helm plugin shorthands (`helm-diff`, `helm-secrets`, `helm-git`)
resolve to their canonical Git URLs; full `https://…` URLs are also
accepted.

### Shell configuration

With `--setup-shell`, the script appends the required initialization
lines to `~/.zshrc` (or `~/.bashrc`). Each block is bracketed by a
marker comment so re-running is idempotent and the block can be located
and removed by hand:

- `pyenv init` + `pyenv virtualenv-init`
- `goenv init`
- `tenv` PATH shims (not needed for `tfenv`, which lives under
  `$(brew --prefix)/bin`)
- `eval "$(mise activate <shell>)"` when `--manager mise` is used

Without `--setup-shell`, the script prints the exact block to copy into
your shell configuration yourself.

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Completed successfully. |
| `1` | One or more installs failed. |
| `2` | Preflight checks failed. |
| `3` | Invalid arguments. |

---

## `stay_fresh.sh`

End-to-end macOS housekeeping. Each step is independent, measures the
disk space freed, and degrades gracefully when a tool is missing or a
path is protected by System Integrity Protection. Concurrent runs are
prevented by a PID lock file in `$TMPDIR`; SIGINT/SIGTERM finish the
current step and print a partial summary.

### Steps

Execution order matches the script (`run_or_skip`):

1. Purge inactive memory (`sudo purge`).
2. Flush the DNS cache (`dscacheutil`, `mDNSResponder`).
3. Clear system caches (`/Library/Caches` and writable entries under
   `/System/Library/Caches`).
4. Clear user caches (`~/Library/Caches`, Logs, Saved State, Xcode
   DerivedData, and related paths). Prints the **top 5 cache offenders**
   first so you see which app is responsible for the reclaimed bytes.
5. Empty `~/.Trash`.
6. Prune Docker / OrbStack (containers, networks, volumes, builder
   cache, and **dangling images only** — tagged images are kept).
7. Clean Xcode extras (Archives, DeviceSupport, obsolete simulators).
8. Remove diagnostic and crash reports (user and system).
9. **Brewfile snapshot** (opt-in via `--brewfile-snapshot`): writes
   `brew bundle dump` to `~/.Brewfile.YYYYMMDD` so an accidental
   `brew autoremove` is recoverable with `brew bundle --file=...`.
10. Update and upgrade Homebrew (formulae and casks), run `cleanup` and
    `autoremove`.
11. Check for **macOS software updates** (`softwareupdate --list`). The
    result is **cached for 6 hours** (`--refresh-updates` to bypass).
    Pending updates render as a compact table (title, version, size, and
    a `↺ restart` badge for updates that require a reboot) and count as a
    **warning** until you opt in with `--install-updates`, which runs
    `softwareupdate --install --all` (may show a GUI authentication
    dialog; some updates require a reboot when marked `Restart: YES`).

    Sample output when updates are pending:

    ```text
    ==> macOS software update
    [info] checking for macOS software updates (network call, may be slow)...
      Pending updates (2):
          TITLE                                         VERSION       SIZE       RESTART
      •   macOS Sonoma 14.7.5                           14.7.5        3.67G      ↺ restart
      •   Command Line Tools for Xcode                  16.3          690.0M
    [warn] one or more updates require a restart
    [info] pass --install-updates to apply these updates
    ```
12. Clean developer-tool caches (`npm`, `yarn`, `pnpm`, `pip`, `gem`,
    `go`, `cargo`).
13. **App Store** updates via `mas` (`mas upgrade`).
14. **`pipx upgrade-all`** for pipx-installed CLIs.
15. **`rustup self update` + `rustup update stable`**.
16. **`mise` / `asdf` self-update** (does not change installed language versions).
17. **VSCode / Cursor / VSCodium extension updates** (`<editor> --update-extensions`).
18. Update installed Helm plugins.
19. Run `gcloud components update`.
20. Report active versions of `pyenv`, `goenv`, `tfenv`, `tenv`, `helm`, `gcloud`.
21. **Thin Time Machine local snapshots** with `tmutil` when free space
    on `/` is below 15 GiB. Otherwise a no-op (snapshots are left alone).
22. **Audit `~/Library/LaunchAgents`** for plists whose target binary is
    missing. Reports orphans; never deletes anything.
23. **Quick Look + Finder reset** (opt-in via `--quicklook-reset`):
    `qlmanage -r` + `qlmanage -r cache` + `killall Finder`.

Every dev-tool step (mas, pipx, rustup, mise, vscode, helm-plugins,
gcloud) auto-skips silently when its CLI is not installed.

### Preflight refusals

Some failure modes are bad enough that the script refuses the offending
step (typically `brew`) rather than risking damage. All of these are
recoverable with `--force`:

| Refusal | Reason |
| --- | --- |
| Disk-tight (`<` 2 GiB free on `/`) | Homebrew upgrades on a near-full disk routinely corrupt their own cache. |
| CLT major mismatch (e.g. CLT 15 on macOS 14) | Homebrew CLT-dependent builds reliably fail here. |
| Apple-Silicon Mac with `brew` at `/usr/local` (Rosetta) | Creates a stale `/usr/local/bin` shadow that's easy to install onto and hard to remove. |
| Low battery, on battery power (`<` 50%) | Long upgrades risk a mid-run shutdown — warning only, run continues. |

### Usage

```bash
./stay_fresh.sh                   # interactive, full run
./stay_fresh.sh --dry-run         # preview the plan
./stay_fresh.sh --yes --verbose   # non-interactive; stream output live
./stay_fresh.sh --brew-greedy     # also upgrade :latest / auto_updates casks
./stay_fresh.sh --no-sudo         # skip every step that requires sudo
./stay_fresh.sh --only memory,dns,trash         # run just three steps
./stay_fresh.sh --skip-devtools --skip-docker   # mix-and-match exclusions
./stay_fresh.sh --install-updates --brewfile-snapshot
./stay_fresh.sh --summary-only --yes --json     # cron-friendly, machine-readable
./stay_fresh.sh --history                       # show the run-history table
./stay_fresh.sh --print-config                  # show parsed config + flag state
```

### Options

| Flag | Purpose |
| --- | --- |
| **General** | |
| `--dry-run` | Show the plan; change nothing. |
| `-y`, `--yes` | Skip confirmation prompts. |
| `-v`, `--verbose` | Stream per-step output live. |
| `--summary-only` | Suppress per-step output; print only the summary card. |
| `--json` | Append a JSON summary after the human card. |
| `--no-sudo` | Skip `purge`, DNS flush, system caches, and system diagnostics. |
| `--no-notify` | Don't post a macOS notification at end of run. |
| `--force` | Bypass non-critical preflight refusals (disk, battery, CLT, Rosetta). |
| `--history` | Show the run-history table and exit. |
| `--print-config` | Print parsed config and final flag values, then exit. |
| `-h`, `--help` | Show the built-in help. |
| **Step selection** | |
| `--only k1,k2,...` | Run only the listed step keys. Negates all `--skip-*`. |
| `--skip-memory` | Skip the `sudo purge` step. |
| `--skip-dns` | Skip the DNS cache flush. |
| `--skip-syscaches` | Skip system-cache cleanup. |
| `--skip-usercaches` | Skip user-cache cleanup. |
| `--skip-trash` | Skip emptying `~/.Trash`. |
| `--skip-docker` | Skip Docker / OrbStack prune. |
| `--skip-xcode` | Skip Xcode extras cleanup. |
| `--skip-diagnostics` | Skip diagnostic and crash-report cleanup. |
| `--skip-brew` | Skip Homebrew update/upgrade/cleanup. |
| `--brew-greedy` | Upgrade casks that self-update (`auto_updates true`, `:latest`). |
| `--brewfile-snapshot` | Dump `brew bundle` to `~/.Brewfile.YYYYMMDD` before brew runs. |
| `--skip-updates` | Skip the macOS software update step. |
| `--install-updates` | Run `softwareupdate --install --all` instead of just listing. |
| `--refresh-updates` | Bypass the 6 h `softwareupdate --list` cache. |
| `--skip-devcaches` | Skip `npm`/`yarn`/`pnpm`/`pip`/`gem`/`go`/`cargo` cache cleanup. |
| `--skip-mas` | Skip App Store updates (`mas`). |
| `--skip-pipx` | Skip `pipx upgrade-all`. |
| `--skip-rustup` | Skip `rustup update`. |
| `--skip-mise` | Skip `mise` / `asdf` self-update. |
| `--skip-vscode` | Skip `code`/`cursor`/`codium` extension updates. |
| `--skip-helm-plugins` | Skip Helm plugin updates. |
| `--skip-gcloud` | Skip `gcloud components update`. |
| `--skip-versions` | Skip the final version report. |
| `--skip-devtools` | Shorthand: skip all dev-tool refreshes (helm-plugins, gcloud, versions, mas, pipx, rustup, mise, vscode). |
| `--skip-snapshots` | Don't trim Time Machine local snapshots when disk is tight. |
| `--skip-launchagents` | Don't audit `~/Library/LaunchAgents` for orphans. |
| `--quicklook-reset` | Reset Quick Look + Finder caches (cosmetic, opt-in). |

Valid keys for `--only`: `memory`, `dns`, `syscaches`, `usercaches`, `trash`,
`docker`, `xcode`, `diagnostics`, `brew`, `brewfile-snapshot`, `updates`,
`devcaches`, `mas`, `pipx`, `rustup`, `mise`, `vscode`, `helm-plugins`,
`gcloud`, `versions`, `snapshots`, `launchagents`, `quicklook`.

### Config file

Persistent defaults live in `$XDG_CONFIG_HOME/stay_fresh/config` (falls
back to `~/.config/stay_fresh/config`). The file is plain `KEY=value`.
Load order is: **built-in defaults → config file → CLI flags** (flags win).
Anything you can set as a flag you can set in the config. Run
`./stay_fresh.sh --print-config` to see the parsed result.

```bash
# ~/.config/stay_fresh/config — example
SKIP_DOCKER=1            # this machine has no Docker
SKIP_XCODE=1             # not an iOS dev
BREW_GREEDY=1            # always upgrade :latest casks
LOW_BATTERY_THRESHOLD=30 # I trust this MacBook's battery, lower the warn floor
```

### Output

The script prints a per-step plan, runs each step with OK / WARN / FAIL
accounting, and closes with a summary that includes:

- Elapsed wall-clock time.
- `df` delta on `/`.
- Sum of per-step deltas (more precise than `df` alone).
- Which steps passed, warned, were skipped, or failed.
- Path to the full log file (only when warnings or failures occurred).

A **last-run banner** at startup shows the most recent row from
`history.csv` (status, when, disk freed, step counts) so you see
continuity across runs without typing `--history`.

A **macOS notification** is posted at the end of every run (success,
warning, or failure) so long runs you tabbed away from still ping you.
Use `--no-notify` to silence.

### Logs & history

| When | Where | Why |
| --- | --- | --- |
| During the run | `$TMPDIR/stay_fresh-YYYYMMDD-HHMMSS.log` | Always written; captured command output goes here. |
| Clean run | *Discarded* | Successful housekeeping leaves no log clutter behind. |
| Warning / failure | `~/Library/Logs/stay_fresh/stay_fresh-YYYYMMDD-HHMMSS.log` | Rescued so you can `tail` it later. The 10 most recent files are kept; older ones are rotated out. |
| Every completed run | `~/Library/Logs/stay_fresh/history.csv` | One row per run: timestamp, elapsed, freed bytes, OK/WARN/FAIL/SKIP counts, exit code. |
| softwareupdate cache | `$TMPDIR/stay_fresh-swu-cache` | Last `softwareupdate --list` output. TTL 6 h. `--refresh-updates` bypasses. |

`./stay_fresh.sh --history` prints the most recent 15 rows formatted as
a table.

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Completed (possibly with warnings). |
| `1` | One or more steps hard-failed. |
| `2` | Preflight checks failed. |
| `3` | Invalid arguments. |
| `4` | Another `stay_fresh.sh` is already running (PID lock in `$TMPDIR`). |

---

## `v1_stay_fresh.sh`

The original housekeeping sequence (previously shipped as
`old_stay_fresh.sh`), preserved for users who prefer the simpler flow.
It has been modernized to run stand-alone: there is no dependency on
`~/scripts/functions`, and the `step`/`next`/`try` reporting helpers are
inlined. Prefer `stay_fresh.sh` unless you specifically need this
minimal runner.

### Steps

1. Refresh Quick Look and Finder caches.
2. Purge inactive memory (`sudo purge`).
3. Clear history leftovers (`~/.lesshst`, `~/.mysql_history`).
4. Clear user caches (`~/Library/Caches`, Xcode Archives and
   DerivedData, `composer clearcache`).
5. Update Homebrew taps.
6. Upgrade Homebrew formulae.
7. Clean Homebrew caches (`brew cleanup --prune=3 -s`, remove
   `brew --cache`, `brew tap --repair`).
8. Update Terraform via `tfenv`.
9. Update Helm via the upstream `get-helm-3` installer.
10. Update Python via `pyenv` (3.x only).
11. Update Go via `gvm`.
12. Run `gcloud components update`.
13. Print the AWS CLI version.
14. Print free space on `/`.

The invoking user's home directory is resolved via `dscl` (using
`$SUDO_USER` or `id -un`), so cache paths still target the correct user
when the script is launched from a sanitized environment such as `sudo`
or `launchd`.

### Usage

```bash
./v1_stay_fresh.sh              # prompts once for sudo, then runs everything
./v1_stay_fresh.sh --help       # show the built-in help
```

The complete flag surface is `-h` / `--help`. There is no `--dry-run`,
`--yes`, `--no-sudo`, or skip flag — use `stay_fresh.sh` if any of those
are required. A failing step never aborts the remainder of the run.

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Completed normally, including `--help`. Per-step failures are reported in the output but do not change this. |
| `1` | Bootstrap failure: cannot determine a usable home directory. |
| `2` | Invalid arguments. |

If you need hard-fail semantics on per-step failures, use
`stay_fresh.sh` instead.

---

## `zsh_aliases.zsh`

A curated set of zsh aliases and helper functions. Every optional
dependency (`eza`, `bat`, `fd`, `rg`, `docker`, `kubectl`, `helm`,
`terraform`, `pyenv`, `goenv`, and so on) is guarded behind
`command -v`, so the file is safe to source on any machine regardless
of which tools are installed.

### Installation

```bash
ln -sfn "$PWD/zsh_aliases.zsh" "$HOME/.zsh_aliases.zsh"
grep -qsF '.zsh_aliases.zsh' ~/.zshrc \
  || echo '[[ -f "$HOME/.zsh_aliases.zsh" ]] && source "$HOME/.zsh_aliases.zsh"' \
       >> ~/.zshrc
exec zsh
```

Re-running the block is safe: `ln -sfn` overwrites the symlink in place,
and the `grep` guard ensures the `source` line is appended to `~/.zshrc`
only once.

### What you get

| Category | Highlights |
| --- | --- |
| Safety | `cp`, `mv`, `rm` default to `-i` (use `\rm` to bypass). |
| Navigation | `..`, `...`, `....`, `.....`, `-`, `~`, `mkcd`, `up N`. |
| Listing | `ls`, `l`, `ll`, `la`, `lt` prefer `eza` when available. |
| Modern replacements | `cat`→`bat`, `find`→`fd`, `grep`→`rg`, `top`→`htop`, `df`→`duf`, `du`→`dust`. |
| Git | `gs`, `gaa`, `gcm`, `gco`, `gcb`, `gp`, `gpl`, `gl`, plus `gwip` (stage + checkpoint) and `gprune` (delete merged branches). |
| Docker / Compose | `d`, `dps`, `dprune`, `dc`, `dcu`, `dcd`, `dcl`. |
| Kubernetes | `k`, `kg`, `kd`, `kl`, `kx`, `kns`. |
| Homebrew | `brewup` (`update` + `upgrade --greedy` + `cleanup` + `autoremove`). |
| Python | Auto-inits `pyenv` + `pyenv-virtualenv`; `venv` creates and activates a local `.venv`. |
| Go | Auto-inits `goenv`, adds `$GOPATH/bin` to `PATH`; `gor`, `gob`, `got`. |
| Terraform / OpenTofu / Helm | `tf*`, `to*`, `h*` shortcuts. |
| Script shortcuts | `stay-fresh`, `install-apps`, `install-devtools` when the scripts are present next to this file. |
| macOS helpers | `flushdns`, `purgemem`, `showfiles`/`hidefiles`, `lock`, `ejectall`, `localip`, `myip`, `pbj`. |
| Functions | `mkcd`, `extract`, `up N`, `mkbackup`, `weather [city]`. |

The `_ZSH_ALIASES_DIR` variable resolves the directory of this file, so
the script shortcuts keep working regardless of where the repository is
cloned. The file is designed to be read top to bottom — comment out
anything you do not want, or append your own additions at the end.

---

## Development: Docker checks

These scripts target macOS, but a **small Linux container** can still verify
syntax, ShellCheck, CLI parsing, config loading, the documented exit codes,
and that `zsh_aliases.zsh` sources cleanly in `zsh`. You need **Docker**
with the **Compose v2** plugin; nothing else on the host.

From the **repository root**:

```bash
./macos-initial-setup/tests/run.sh
```

Same thing without the wrapper:

```bash
docker compose -f macos-initial-setup/tests/docker-compose.yml run --rm tester
```

The `tester` image (`tests/tester/Dockerfile`) installs `bash`, `shellcheck`,
and `zsh`, mounts the repo read-only at `/repo`, and runs
`tests/test_macos_initial_setup.sh` (~100 `[ ok ]` lines when everything
passes).

### What the harness checks

| Area | Notes |
| --- | --- |
| `bash -n` | All `*.sh` in this directory. |
| ShellCheck | `--severity=error` for the bash scripts. Debian’s stock ShellCheck may not ship a `zsh` dialect — the harness then **skips** `zsh` ShellCheck but still **sources** `zsh_aliases.zsh` in `zsh`. |
| `--help` / `-h` | Succeeds for `install_*.sh`, `stay_fresh.sh`, and `v1_stay_fresh.sh`. |
| Unknown flags | `install_apps.sh`, `install_devtools.sh`, and `stay_fresh.sh` return exit **3** before preflight. `install_devtools.sh --manager bogus` also exits **3**. |
| Platform guard | On Linux, `install_*.sh` and `stay_fresh.sh` exit **2** with a “macOS only” message even with `--dry-run` (preflight runs after parse). |
| `stay_fresh.sh` flags | Every documented `--skip-*`, mode flag, and short option (`-y`, `-v`) parses on Linux (exit **2**, not **3**). Includes `--only=docker,brew` form. |
| `install_apps.sh` / `install_devtools.sh` flags | Representative skip/setup flags parse on Linux (exit **2**); `install_devtools.sh --manager mise` included. |
| `stay_fresh.sh --print-config` / `--history` | Exit **0** on Linux (short-circuit before macOS preflight). Output must include the config banner or history header. |
| `--print-config` semantics | `--skip-docker` / `--dry-run` reflected in output; `--skip-devtools` fans out to dev-tool skip flags; `--only quicklook` enables the opt-in step. |
| Config file | With `XDG_CONFIG_HOME` pointing at a temp dir, `KEY=value` lines load after defaults; CLI flags override config (`DRY_RUN` tested). |
| `--only` | Unknown step → exit **3**. Each valid step key tested individually. `--only brewfile-snapshot` alone → exit **3** (brew must run); `--only brew,brewfile-snapshot` → exit **2**. |
| Conflicting flags | Exit **3** at parse time: `--install-updates` + `--skip-updates`; `--skip-brew` + `--brew-greedy` or `--brewfile-snapshot`. |
| `zsh_aliases.zsh` | `zsh -f -c "source …"` must not error. |

### What Docker does *not* cover

This is **not** a substitute for `--dry-run` on a real Mac: there is no
Homebrew, no installs, and no execution of `stay_fresh` maintenance steps.
For RouterOS script integration tests in the same repository, see
[`mikrotik/tests/README.md`](../mikrotik/tests/README.md).

---

## What this changes on your machine

A plain-language audit trail of every side effect, grouped by the
script responsible. Everything below is reversible with standard
Homebrew / `pyenv` / `goenv` commands.

### `install_apps.sh`

- Installs Homebrew at `/opt/homebrew` (Apple Silicon) or `/usr/local`
  (Intel) if it is missing.
- Installs the casks listed under *Bundled applications*; existing
  unmanaged apps in `/Applications` are adopted into Homebrew.
- Installs the `gcloud-cli` cask and the components listed with
  `--gcloud-components`.
- Writes `/tmp/install_apps-YYYYMMDD-HHMMSS.log`.
- Runs `brew cleanup` at the end unless `--no-cleanup` is passed.
- Does **not** modify any shell configuration files.

### `install_devtools.sh`

- Installs the selected version manager(s): `pyenv`,
  `pyenv-virtualenv`, `tfenv` or `tenv`, `goenv`, and/or `mise` via
  Homebrew.
- Installs Python build dependencies:
  `openssl readline sqlite3 xz zlib tcl-tk`.
- Installs the pinned (or latest) versions of Python, Terraform, Go,
  and Helm under each manager's usual directory (`~/.pyenv`,
  `~/.goenv`, `$(brew --prefix)/bin`).
- Installs the configured Helm plugins (default: `helm-diff`).
- Appends one bracketed block per tool to `~/.zshrc` or `~/.bashrc`
  **only when `--setup-shell` is passed**. Each block is marked so it
  can be located and removed by hand.
- Writes `/tmp/install_devtools-YYYYMMDD-HHMMSS.log`.

### `stay_fresh.sh`

- Deletes cache contents (not the directories themselves) under
  `/Library/Caches`, writable entries of `/System/Library/Caches`,
  `~/Library/Caches`, Logs, Saved State, Xcode DerivedData, and related
  paths.
- Empties `~/.Trash`.
- Clears developer-tool caches (`npm`, `yarn`, `pnpm`, `pip`, `gem`,
  `go`, `cargo`).
- Prunes Docker resources when Docker is available:
  - Containers (`docker container prune -f`)
  - Networks (`docker network prune -f`)
  - Volumes (`docker volume prune -f`)
  - **Dangling images only** (`docker image prune -f`) — keeps tagged images
  - Builder cache (`docker builder prune -af`)
  - Skips pruning entirely when the active Docker context points to a non-local
    daemon (non-`unix://…` host), to avoid cleaning a remote engine by mistake.
- Upgrades Homebrew formulae and casks (greedy upgrade only with
  `--brew-greedy`).
- Calls `softwareupdate --list` (and optionally `softwareupdate --install --all`
  with `--install-updates`); skip entirely with `--skip-updates`. The list
  output is cached in `$TMPDIR/stay_fresh-swu-cache` for 6 h.
- Updates Helm plugins and `gcloud` components when those tools are installed.
- Runs **App Store** (`mas`), **pipx**, **rustup**, **mise/asdf**, and
  **VSCode/Cursor extension** updates when those CLIs are on `PATH`.
- **Reads** `~/Library/LaunchAgents` to audit for orphan plists. Never
  deletes anything in this directory.
- **Thins** Time Machine local snapshots (`tmutil thinlocalsnapshots /`)
  when `/` has less than 15 GiB free.
- Optionally resets Quick Look + Finder caches (`--quicklook-reset`).
- Optionally writes a Brewfile snapshot to `~/.Brewfile.YYYYMMDD` before
  the Homebrew step (`--brewfile-snapshot`).
- Writes a run log in `$TMPDIR`. On a clean run the log is deleted; if any
  step warns or fails, the log is moved to
  `~/Library/Logs/stay_fresh/` (most recent 10 kept, older rotated out).
- Appends one row to `~/Library/Logs/stay_fresh/history.csv` per
  completed run.
- Holds a PID lock file (`$TMPDIR/stay_fresh.lock`) for the duration of
  the run to prevent concurrent invocations.
- Reads (but does not write) `$XDG_CONFIG_HOME/stay_fresh/config` for
  persistent defaults.
- Posts a macOS notification at end of run unless `--no-notify` is set.
- Does **not** modify any shell configuration files.

### `v1_stay_fresh.sh`

- Runs the subset of cleanup and toolchain updates listed in its
  *Steps* section.
- Deletes `~/.lesshst` and `~/.mysql_history` if present.
- Writes no log file by default; redirect yourself with `tee` if a
  transcript is needed:

  ```bash
  ./v1_stay_fresh.sh 2>&1 | tee /tmp/v1_stay_fresh.log
  ```

### `zsh_aliases.zsh`

- Affects interactive shells only. Sourcing the file adds aliases and
  functions to the current shell; it does not write anything to disk
  and does not modify system files.

### Privileged operations

The three top-level scripts request `sudo` only for the operations
below. They refuse to run as `root`, prompt once at the start, and
release the credential on exit.

| Script | Uses `sudo` for |
| --- | --- |
| `install_apps.sh` | Cask installs that require admin approval (Homebrew invokes `sudo` internally; the script itself does not escalate). |
| `install_devtools.sh` | Same as above, only via Homebrew where required. |
| `stay_fresh.sh` | `purge`, DNS flush, `/Library/Caches` cleanup, system diagnostic cleanup. Pass `--no-sudo` to skip all of these. |
| `v1_stay_fresh.sh` | `purge`. No way to opt out — use `stay_fresh.sh --no-sudo` instead. |
