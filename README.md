# Pretty Useful Scripts

Helper scripts for setting up, maintaining, and working on the small set of
machines I touch regularly — currently macOS workstations and a MikroTik
router. The repository is intentionally small: each folder should be easy to
inspect, safe to run more than once, and focused on reducing repeat manual
work.

**Targets:**
- macOS 12+ (Apple Silicon and Intel) — scripts use `bash`, aliases use `zsh`.
- MikroTik RouterOS 7.22 — scripts are RouterOS scripting language (`.lua`
  extension is just for editor highlighting).

## Contents

- [Documentation map](#documentation-map)
- [What's here](#whats-here)
- [Quick start](#quick-start)
- [Script guidelines](#script-guidelines)
- [macOS setup at a glance](#macos-setup-at-a-glance)
- [MikroTik scripts at a glance](#mikrotik-scripts-at-a-glance)
- [Testing (Docker)](#testing-docker)

## Documentation map

| Read this | When you need |
| --- | --- |
| This file | One-page overview, quick start, and pointers into the two packages. |
| [`macos-initial-setup/README.md`](macos-initial-setup/README.md) | Full macOS runbook: every script, flags, exit codes, side effects, Docker checks. |
| [`mikrotik/README.md`](mikrotik/README.md) | RouterOS install, schedules, security lists, 7.22 gotchas. |
| [`mikrotik/tests/README.md`](mikrotik/tests/README.md) | CHR 7.22 Docker tests: requirements, env vars, troubleshooting. |

Script inventories in this file are summaries; the folder READMEs stay the
detailed, authoritative lists.

## What's here

| Folder | Purpose |
| --- | --- |
| [`macos-initial-setup/`](macos-initial-setup/) | Bootstrap a fresh macOS workstation, install common apps and developer tools, keep Homebrew/toolchains fresh, and load useful zsh aliases. |
| [`mikrotik/`](mikrotik/) | RouterOS 7.x scripts for backups, WiFi password rotation, WAN-state monitoring, health checks, and Telegram notifications. |

## Quick start

### macOS

For a new Mac, start with the macOS setup folder:

```bash
cd macos-initial-setup

./install_apps.sh     --dry-run --verbose
./install_devtools.sh --dry-run --verbose

./install_apps.sh
./install_devtools.sh --setup-shell

# Later: maintenance + audit (see macos-initial-setup README for flags)
./stay_fresh.sh --dry-run
./workstation_doctor.sh
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

## Script guidelines

- Prefer `--dry-run` before changing the machine (macOS scripts).
- Read the README inside each folder before running scripts there.
- Keep scripts executable with `chmod +x path/to/script.sh` if your clone
  dropped the exec bits.
- Run scripts from their own folder unless that script documents otherwise.
- Expect macOS scripts to log details under `${TMPDIR:-/tmp}` when they
  perform non-trivial work.
- For MikroTik scripts, treat all changes through the router's own
  `/log print` and Telegram notifications — there is no host-side logfile.

## macOS setup at a glance

The macOS package is [`macos-initial-setup/`](macos-initial-setup/):

- `install_apps.sh` installs Homebrew if needed, then installs desktop apps,
  platform/DevOps CLI formulae, and Google Cloud SDK components.
- `install_devtools.sh` installs Python, Terraform, Go, Helm, and optional shell
  initialization using version managers.
- `stay_fresh.sh` handles recurring maintenance: caches, Homebrew upgrades,
  Docker/OrbStack cleanup, Xcode extras, Helm plugins, `gcloud`, version
  reporting, and optional gated `softwareupdate` (off by default).
- `workstation_doctor.sh` is a read-only audit (security, Time Machine, logs,
  LaunchAgents, `brew doctor`, SSH/git).
- `Brewfile.example` documents an optional `brew bundle` workflow for forks.
- `stay_fresh.sh` can optionally trim aged `~/Library/Logs` files
  (`--trim-unified-old-logs`).
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
- `wan_link_flap_notify.lua` — Telegram on WAN interface `running` up/down
  transitions (L1 link), complementary to `detect-internet-state`.
- `cert_expiry_watch.lua` — alerts on expired certificates and on certs
  expiring within a configurable day window.
- `backup_file_cleanup.lua` — deletes stale `backup-*` files from `/file`
  after `RetentionDays` (no Telegram).
- `wireguard_watch.lua` / `netwatch_notify.lua` — WireGuard and Netwatch
  health Telegrams.
- `pull_router_backups.sh` — host-side `scp` of backups from the router.
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

Two folders ship **self-contained** Docker-based checks. You only need the
Docker Engine and Compose v2 on the host — no local Python, shellcheck, or
RouterOS install. Both wrappers accept **`--no-build`** to skip image builds
when layers are already cached.

| Package | What runs | How |
| --- | --- | --- |
| [`macos-initial-setup/`](macos-initial-setup/) | **Static** checks on the bash scripts and `zsh_aliases.zsh` (syntax, ShellCheck, `--help`, Linux “macOS only” preflight, zsh can source aliases). Does **not** install apps or run Homebrew — the scripts are macOS-only. | [`macos-initial-setup/README.md#development-docker-checks`](macos-initial-setup/README.md#development-docker-checks) — `./macos-initial-setup/tests/run.sh` |
| [`mikrotik/`](mikrotik/) | **Integration** tests against a real **RouterOS 7.22 CHR** in QEMU, API-driven `pytest`. | [`mikrotik/tests/README.md`](mikrotik/tests/README.md) — `./mikrotik/tests/run.sh` |
