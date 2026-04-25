# Pretty Useful Scripts

Helper scripts for setting up, maintaining, and working on macOS machines.
The repository is intentionally small: each folder should be easy to inspect,
safe to run more than once, and focused on reducing repeat manual work.

## What's Here

| Folder | Purpose |
| --- | --- |
| [`macos-initial-setup/`](macos-initial-setup/) | Bootstrap a fresh macOS workstation, install common apps and developer tools, keep Homebrew/toolchains fresh, and load useful zsh aliases. |

## Quick Start

For a new Mac, start with the macOS setup folder:

```bash
cd macos-initial-setup
chmod +x ./*.sh

./install_apps.sh --dry-run
./install_devtools.sh --dry-run

./install_apps.sh
./install_devtools.sh --setup-shell
```

Use dry runs first when trying a script on a machine you care about. Most
scripts in this repository are designed to be idempotent, but they still install
or clean real software when run without `--dry-run`.

## Script Guidelines

- Prefer `--dry-run` before changing the machine.
- Read the README inside each folder before running scripts there.
- Keep scripts executable with `chmod +x path/to/script.sh`.
- Run scripts from their own folder unless that script documents otherwise.
- Expect scripts to log details under `${TMPDIR:-/tmp}` when they perform
  non-trivial work.

## macOS Setup At A Glance

The current main package is [`macos-initial-setup/`](macos-initial-setup/):

- `install_apps.sh` installs Homebrew if needed, then installs desktop apps,
  platform/DevOps CLI formulae, and Google Cloud SDK components.
- `install_devtools.sh` installs Python, Terraform, Go, Helm, and optional shell
  initialization using version managers.
- `stay_fresh.sh` handles recurring maintenance: caches, Homebrew upgrades,
  Docker/OrbStack cleanup, Xcode extras, Helm plugins, `gcloud`, and version
  reporting.
- `zsh_aliases.zsh` provides guarded aliases and helper functions for daily
  shell work.

See [`macos-initial-setup/README.md`](macos-initial-setup/README.md) for the
full runbook and all options.
