# Pretty Useful Scripts

Helper scripts for setting up, maintaining, and working on macOS machines.
The repository is intentionally small: each folder should be easy to inspect,
safe to run more than once, and focused on reducing repeat manual work.

**Targets:** macOS 12+ (Apple Silicon and Intel). Scripts use `bash`; the
aliases file uses `zsh`.

## Contents

- [What's here](#whats-here)
- [Quick start](#quick-start)
- [Script guidelines](#script-guidelines)
- [macOS setup at a glance](#macos-setup-at-a-glance)

## What's here

| Folder | Purpose |
| --- | --- |
| [`macos-initial-setup/`](macos-initial-setup/) | Bootstrap a fresh macOS workstation, install common apps and developer tools, keep Homebrew/toolchains fresh, and load useful zsh aliases. |

## Quick start

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

## Script guidelines

- Prefer `--dry-run` before changing the machine.
- Read the README inside each folder before running scripts there.
- Keep scripts executable with `chmod +x path/to/script.sh` if your clone
  dropped the exec bits.
- Run scripts from their own folder unless that script documents otherwise.
- Expect scripts to log details under `${TMPDIR:-/tmp}` when they perform
  non-trivial work.

## macOS setup at a glance

The current main package is [`macos-initial-setup/`](macos-initial-setup/):

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
