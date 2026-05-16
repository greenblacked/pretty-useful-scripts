# Pretty Useful Scripts

Helper scripts for setting up, maintaining, and working on the small set of
machines I touch regularly — currently macOS workstations and a MikroTik
router, plus everyday Git helpers. The repository is intentionally small:
each folder should be easy to inspect, safe to run more than once, and focused
on reducing repeat manual work.

**Targets:**
- Git repositories on macOS or Linux — scripts use `bash`; aliases use `zsh`.
- macOS 12+ (Apple Silicon and Intel) — scripts use `bash`, aliases use `zsh`.
- MikroTik RouterOS 7.22 — scripts are RouterOS scripting language (`.lua`
  extension is just for editor highlighting).
- Chef Infra cookbooks — Test Kitchen + Cookstyle + ChefSpec + InSpec under
  [`test-env/chef/`](test-env/chef/) (Docker runner on the host).
- Python 3.12 sample package — Ruff, Ruff format, pytest, and mypy under
  [`test-env/python/`](test-env/python/) (Docker dev container).
- Go 1.23 sample module — `go test`, golangci-lint, goimports, govulncheck
  under [`test-env/go/`](test-env/go/) (Docker dev container).

All three test-envs also lint their own scaffolding (run.sh, Dockerfile,
compose YAML) via **shellcheck**, **hadolint**, and **yamllint** — surfaced
uniformly as `just lint-env`.

## Contents

- [What's here](#whats-here)
- [Quick start](#quick-start)
- [Script guidelines](#script-guidelines)
- [Git scripts at a glance](#git-scripts-at-a-glance)
- [macOS setup at a glance](#macos-setup-at-a-glance)
- [MikroTik scripts at a glance](#mikrotik-scripts-at-a-glance)
- [Testing (Docker)](#testing-docker)
- [Chef cookbook test env](#chef-cookbook-test-env)
- [Python package test env](#python-package-test-env)
- [Go module test env](#go-module-test-env)

## What's here

| Folder | Purpose |
| --- | --- |
| [`git/`](git/) | Git helper scripts for author profiles, quick add/commit/push flows, status summaries, branch cleanup, and local Docker-based checks. |
| [`macos-initial-setup/`](macos-initial-setup/) | Bootstrap a fresh macOS workstation, install common apps and developer tools, keep Homebrew/toolchains fresh, and load useful zsh aliases. |
| [`mikrotik/`](mikrotik/) | RouterOS 7.x scripts for backups, WiFi password rotation, WAN-state monitoring, health checks, and Telegram notifications. |
| [`test-env/`](test-env/) | Sandboxed test harnesses — **[`chef/`](test-env/chef/)**, **[`python/`](test-env/python/)**, **[`go/`](test-env/go/)** (each has `run.sh`, optional `just`, `.devcontainer/`). Index: [`test-env/README.md`](test-env/README.md). |

## Quick start

### macOS

For a new Mac, start with the macOS setup folder:

```bash
cd macos-initial-setup

./install_apps.sh     --dry-run --verbose
./install_devtools.sh --dry-run --verbose

./install_apps.sh
./install_devtools.sh --setup-shell
```

Use dry runs first when trying a script on a machine you care about. All
scripts in this repository are designed to be idempotent, but they still
install or clean real software when run without `--dry-run`.

### MikroTik

These are RouterOS scripts, not shell scripts — paste each file into the
*Source* field of a `/system script` entry on the router (Winbox / WebFig →
**System → Scripts → Add (+)**). Set up `tg_send` first with your Telegram
bot token, then schedule the rest via `/system scheduler`. The full runbook,
policy bits, and suggested cadence live in
[`mikrotik/README.md`](mikrotik/README.md).

### Git

Start with the Git helpers for day-to-day repository work:

```bash
cd git

./gacp.sh --dry-run -m "preview commit"
./git_status_summary.sh

./set_git_profile.sh --name "Sergey" --email "your@email.com"
```

Optional zsh alias:

```zsh
source "$PWD/git_aliases.zsh"
gacp "update scripts"
```

## Script guidelines

- Prefer `--dry-run` before changing the machine or repository when a script
  supports it.
- Read the README inside each folder before running scripts there.
- Keep scripts executable with `chmod +x path/to/script.sh` if your clone
  dropped the exec bits.
- Run scripts from their own folder unless that script documents otherwise.
- Expect macOS scripts to log details under `${TMPDIR:-/tmp}` when they
  perform non-trivial work.
- For MikroTik scripts, treat all changes through the router's own
  `/log print` and Telegram notifications — there is no host-side logfile.

## Git scripts at a glance

The Git package is [`git/`](git/), tested in Docker against temporary local
repositories and local bare remotes:

- `gacp.sh` — stages all changes, commits with a required message, and pushes.
  Supports `--dry-run`, `--no-push`, and first-push options (`--remote`,
  `--branch`).
- `git_aliases.zsh` — defines `gacp` for zsh by pointing at `gacp.sh`.
- `set_git_profile.sh` — manages global `user.name` / `user.email`, plus
  named profiles stored under
  `${XDG_CONFIG_HOME:-$HOME/.config}/pretty-useful-scripts/git-profiles.conf`.
- `git_whoami.sh` — shows the effective Git identity for the current directory
  and the global fallback when it differs.
- `git_status_summary.sh` — prints branch, upstream, ahead/behind, and
  changed/staged/unstaged/untracked counts.
- `git_sync_default.sh` — fetches and fast-forwards the default branch; refuses
  to run with a dirty working tree and supports `--dry-run`.
- `git_cleanup_merged.sh` — deletes local branches already merged into a base
  branch; protects common branch names unless `--force` is passed.
- `git_recent_branches.sh` — lists local branches by recent activity and can
  switch by list index.
- `git_repo_root.sh` — prints the repository root path for the current Git
  working tree.
- `git_diff_branch.sh` — shows the diff or diffstat for changes unique to the
  current branch since it diverged from `main` or `master`.
- `git_undo_last_commit.sh` — undoes the latest commit with `--soft` by
  default, with explicit options for `--mixed` and forced `--hard`.
- `git_amend_last.sh` — amends the previous commit with staged changes, or
  stages everything first with `--add-all`.

See [`git/README.md`](git/README.md) for command examples, exit-code
conventions, alias setup, and Docker test details.

## macOS setup at a glance

The macOS package is [`macos-initial-setup/`](macos-initial-setup/):

- `install_apps.sh` installs Homebrew if needed, then installs desktop apps,
  platform/DevOps CLI formulae, and Google Cloud SDK components.
- `install_devtools.sh` installs Python, Terraform, Go, Helm, and optional shell
  initialization using version managers.
- `stay_fresh.sh` handles recurring maintenance: caches, Homebrew upgrades,
  Docker/OrbStack cleanup, Xcode extras, Helm plugins, `gcloud`, and version
  reporting.
- `v1_stay_fresh.sh` is a legacy, flag-free minimal maintenance flow kept for
  reference; prefer `stay_fresh.sh` for new use.
- `zsh_aliases.zsh` provides guarded aliases and helper functions for daily
  shell work.

See [`macos-initial-setup/README.md`](macos-initial-setup/README.md) for the
full runbook and all options.

## MikroTik scripts at a glance

The MikroTik package is [`mikrotik/`](mikrotik/), verified against
**RouterOS 7.22**:

- `tg_send.lua` — generic Telegram text helper used by every other script;
  reads `:global TG_BOT_TOKEN` / `TG_CHAT_ID` so secrets stay out of the
  script body, with retries and 4 KB truncation.
- `backup.lua` — daily binary + export backup; sends a Telegram confirmation
  with the resulting filename. Date-format-safe filenames.
- `change_WIFI_pw.lua` — rotates 2.4 GHz / 5 GHz WPA2 PSKs (legacy `wireless`
  or new `wifi`/WiFiWave2 stack) and posts the new credentials to Telegram.
- `health_check.lua` — CPU / RAM / disk / temperature watchdog; only alerts
  on threshold violations.
- `update_check.lua` — daily check against MikroTik's update server; pings
  Telegram once per new version.
- `wan_failover_notify.lua` — polls the built-in `detect-internet-state`
  property on the WAN interface and notifies only on transitions.
- `detect_internet.lua` — manual nudge that re-runs RouterOS WAN/LAN
  auto-detection (also enables it for `wan_failover_notify`).
- `reboot-and-flush.lua` — flushes DNS cache + connection tracking, then
  reboots. Pair with the README's optional `notify-boot` startup scheduler
  for a "back online" alert after each reboot.
- `dhcp_lease_watch.lua` — alerts on new MACs, duplicate hostnames, and
  lease churn; optionally tags new lease IPs into address-list
  `dhcp-watch-new`.
- `firewall_drift.lua` + `firewall_drift_baseline.lua` — snapshots
  `/ip firewall filter` and `nat` rule signatures and alerts on additions,
  removals, or critical-rule reordering; the helper script clears the
  baseline after intentional changes.
- `mac_allowlist_dhcp.lua` — flags (and optionally blocks via address-list
  + filter rule) DHCP leases whose MAC is not on `:global MAC_ALLOWLIST`.
  Fail-safe: refuses to act when the allowlist is empty.
- `rogue_dns_check.lua` — verifies upstream DNS sanity and detects clients
  using non-approved DNS resolvers; tags offenders into
  `rogue-dns-clients`.

See [`mikrotik/README.md`](mikrotik/README.md) for installation, policy
flags, suggested scheduler entries, and RouterOS 7.22-specific gotchas
(TLS CAs, `:global` lifetime, `wifi` vs `wireless`, etc.).

## Testing (Docker)

Several areas ship **Docker-based** or **container-assisted** checks. For the
Git and macOS folders you only need the Docker Engine and Compose v2 on the host
— no local Python, ShellCheck, or RouterOS install.

| Package | What runs | How |
| --- | --- | --- |
| [`git/`](git/) | **Static + behavior** checks for Git helper scripts (syntax, ShellCheck, `--help`, profile state, `gacp`, status, cleanup, recent branches, and sync against local temporary repos/remotes). | [`git/README.md#tests`](git/README.md#tests) — `./git/tests/run.sh` |
| [`macos-initial-setup/`](macos-initial-setup/) | **Static** checks on the bash scripts and `zsh_aliases.zsh` (syntax, ShellCheck, full CLI/config/`--only` parsing, Linux “macOS only” preflight, zsh can source aliases). Does **not** install apps or run Homebrew — the scripts are macOS-only. | [`macos-initial-setup/README.md#development--docker-checks`](macos-initial-setup/README.md#development--docker-checks) — `./macos-initial-setup/tests/run.sh` |
| [`mikrotik/`](mikrotik/) | **Integration** tests against a real **RouterOS 7.22 CHR** in QEMU, API-driven `pytest`. | [`mikrotik/tests/README.md`](mikrotik/tests/README.md) — `./mikrotik/tests/run.sh` |
| [`test-env/chef/`](test-env/chef/) | **Cookstyle + yamllint + ChefSpec + Test Kitchen (kitchen-dokken + InSpec)** from a Ruby image that mounts the host Docker socket (DinD-style sibling containers). | [`test-env/chef/README.md`](test-env/chef/README.md) — `cd test-env/chef && ./run.sh …` or `just …` |
| [`test-env/python/`](test-env/python/) | **Ruff (lint + format check) + pytest** from a Python 3.12 image; long-running `dev` service for fast `docker compose exec`. Optional **mypy** locally (`just typecheck`). | [`test-env/python/README.md`](test-env/python/README.md) — `cd test-env/python && ./run.sh …` or `just …` |
| [`test-env/go/`](test-env/go/) | **go vet + golangci-lint + go test -race + govulncheck** (and goimports check) from a Go 1.23 image; module/build caches in Compose volumes. | [`test-env/go/README.md`](test-env/go/README.md) — `cd test-env/go && ./run.sh …` or `just …` |

## Chef cookbook test env

The cookbook harness lives under **[`test-env/chef/`](test-env/chef/)**. Typical
flows:

```bash
cd test-env/chef
./run.sh cookstyle --display-cop-names cookbooks   # lint (same as CI)
./run.sh yamllint -c .yamllint .                   # YAML
./run.sh rspec cookbooks                           # ChefSpec (same as CI)
./run.sh kitchen verify                            # integration (Docker + socket)
```

Task shortcuts and the full layout are in
[`test-env/chef/README.md`](test-env/chef/README.md). The fast local gate is
`just ci` (lint-env + lint + yamllint + spec), and `kitchen verify` is intended
for machines with Docker socket access because dokken starts privileged sibling
containers.

## Python package test env

The Python harness lives under **[`test-env/python/`](test-env/python/)**. Typical
flows:

```bash
cd test-env/python
./run.sh up
./run.sh ruff check .
./run.sh ruff format --check .
./run.sh pytest -q
./run.sh mypy              # optional; not in CI today
```

Task shortcuts and the full layout are in
[`test-env/python/README.md`](test-env/python/README.md). Use `just ci` for the
local full gate: `lint-env`, `ruff check`, `ruff format --check`, `mypy`, and
`pytest`.

## Go module test env

The Go harness lives under **[`test-env/go/`](test-env/go/)**. Typical flows:

```bash
cd test-env/go
./run.sh up
./run.sh go test -race -count=1 ./...
./run.sh golangci-lint run
./run.sh govulncheck ./...
```

Task shortcuts and cache layout are in [`test-env/go/README.md`](test-env/go/README.md).
Use **`just ci`** for the full local gate (`go vet`, lint, format check, tests,
vulnerability scan).
