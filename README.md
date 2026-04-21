# macos-initial-setup

A small collection of scripts to take a fresh (or tired) macOS machine from
zero to productive — install apps, wire up developer toolchains, and keep it
clean over time.

All scripts are idempotent: re-running them upgrades in place rather than
duplicating work. Every script writes a full log to `$TMPDIR` and supports
`--dry-run` so you can preview the plan before touching anything.

## Contents


| Script                                       | What it does                                                                                                                                   |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `[install_apps.sh](#install_appssh)`         | Install a curated set of desktop apps (Brave, VS Code, Cursor, OrbStack, Slack, Zoom, Telegram, Spotify) + Google Cloud SDK via Homebrew Cask. |
| `[install_devtools.sh](#install_devtoolssh)` | Install Python / Terraform / Go / Helm via best-practice version managers (pyenv, tfenv, goenv; or `mise` / `tenv`).                           |
| `[stay_fresh.sh](#stay_freshsh)`             | Modern macOS housekeeping: purge memory, flush caches, prune Docker, refresh Homebrew + dev toolchains.                                        |
| `[old_stay_fresh.sh](#old_stay_freshsh)`     | Legacy step list (kernel caches -> brew -> tfenv -> helm -> pyenv -> gvm -> gcloud -> aws), modernized and self-contained.                     |
| `[zsh_aliases.zsh](#zsh_aliaseszsh)`         | Opinionated zsh aliases + helper functions, auto-wires pyenv/goenv, and adds shortcuts for the scripts above.                                  |


## Recommended order

On a fresh Mac:

```bash
git clone https://github.com/<you>/macos-initial-setup.git ~/scripts/macos-initial-setup
cd ~/scripts/macos-initial-setup
chmod +x ./*.sh

./install_apps.sh                 # 1. apps + gcloud-cli
./install_devtools.sh --setup-shell   # 2. dev toolchains (also wires ~/.zshrc)
ln -s "$PWD/zsh_aliases.zsh" "$HOME/.zsh_aliases.zsh"
echo '[[ -f "$HOME/.zsh_aliases.zsh" ]] && source "$HOME/.zsh_aliases.zsh"' >> ~/.zshrc
exec zsh                          # 3. pick up aliases + pyenv/goenv shims
```

After that, run `./stay_fresh.sh` (or `stay-fresh`, aliased) whenever things
feel sluggish or you want to catch up on upgrades.

---

## `install_apps.sh`

Installs a curated set of desktop apps via Homebrew Cask, plus the Google
Cloud SDK (`gcloud-cli` cask) with the common components (`kubectl`,
`gke-gcloud-auth-plugin`).

**Preflight** checks: macOS only, not-root, internet reachable, Xcode CLT
present, at least 5 GB free, Homebrew installed (installs it if missing).

### Quick start

```bash
./install_apps.sh                 # install everything, interactive
./install_apps.sh --dry-run       # preview plan, change nothing
./install_apps.sh --yes           # non-interactive
```

### Filter which apps

```bash
./install_apps.sh --only cursor,slack        # only these
./install_apps.sh --skip zoom,telegram       # everything except these
./install_apps.sh --skip-upgrade             # don't upgrade already-installed casks
./install_apps.sh --skip-gcloud              # skip Google Cloud SDK entirely
```

### Google Cloud SDK components

The script installs `gke-gcloud-auth-plugin` and `kubectl` by default. It
tries `brew install <component>` first and falls back to `gcloud components install <component>` if the component isn't a brew formula.

```bash
./install_apps.sh --gcloud-components gke-gcloud-auth-plugin,kubectl,beta
./install_apps.sh --no-gcloud-components     # install gcloud core only
```

### Bundled apps

`brave-browser`, `visual-studio-code`, `cursor`, `orbstack`, `slack`, `zoom`,
`telegram`, `spotify`.

Existing apps already in `/Applications` but not managed by brew are
**adopted** (`brew install --cask --force`) so future upgrades flow through
brew.

### Exit codes

`0` clean · `1` some installs failed · `2` preflight failed · `3` bad args.

---

## `install_devtools.sh`

Installs developer toolchains with version managers so you can have multiple
versions side-by-side:

- **Python** via `pyenv` (+ `pyenv-virtualenv`) with macOS build deps
- **Terraform** via `tfenv` (or `tenv` for Terraform + OpenTofu + Terragrunt)
- **Go** via `goenv`
- **Helm** via Homebrew (+ optional plugins: `helm-diff`, `helm-secrets`, `helm-git`)

Or use `**mise`** (ex-rtx) as a unified manager for python/terraform/go in
one binary.

Requires Homebrew (run `install_apps.sh` first, or the script will refuse).
Does **not** touch your shell rc unless you pass `--setup-shell`.

### Quick start

```bash
./install_devtools.sh                    # native managers, latest versions, interactive
./install_devtools.sh --dry-run
./install_devtools.sh --yes --setup-shell
```

### Pick a manager

```bash
./install_devtools.sh --manager native   # pyenv + tfenv + goenv + brew helm  (default)
./install_devtools.sh --manager tenv     # tenv instead of tfenv (tofu/tg support)
./install_devtools.sh --manager mise     # mise for python/terraform/go
```

### Pin versions

```bash
./install_devtools.sh --python-version 3.12.5 \
                      --terraform-version 1.9.5 \
                      --go-version 1.23.2

./install_devtools.sh --skip-python --skip-go   # helm + terraform only
```

Use `latest` (default) to grab the latest stable for each tool.

### Helm plugins

```bash
./install_devtools.sh --helm-plugins helm-diff,helm-secrets,helm-git
./install_devtools.sh --no-helm-plugins
```

Known shorthands resolve to their canonical git URLs; you can also pass a
raw `https://…` URL directly.

### Shell wiring

With `--setup-shell`, the script appends the needed init lines to
`~/.zshrc` (or `~/.bashrc`) — guarded by markers so re-running is safe:

- `pyenv init` + `pyenv virtualenv-init`
- `goenv init`
- `tenv` PATH shims (or nothing for tfenv, which lives under `$(brew --prefix)/bin`)
- `eval "$(mise activate <shell>)"` when `--manager mise`

Without the flag, the script prints the exact block to paste.

### Exit codes

`0` clean · `1` some installs failed · `2` preflight failed · `3` bad args.

---

## `stay_fresh.sh`

One-stop macOS housekeeping. Each step is independent, measures bytes freed,
and degrades gracefully when a tool is missing or a path is SIP-protected.

### What it does

1. Purge inactive memory (`sudo purge`)
2. Flush DNS cache (`dscacheutil` + `mDNSResponder`)
3. Clear system caches (`/Library/Caches`, writable entries under `/System/Library/Caches`)
4. Clear user caches (`~/Library/Caches`, Logs, Saved State, Xcode DerivedData, …)
5. Empty `~/.Trash`
6. Dev-tool cache cleanup (`npm`, `yarn`, `pnpm`, `pip`, `gem`, `go`, `cargo`)
7. Docker / OrbStack prune (images, containers, volumes, builder cache)
8. Xcode extras (Archives, DeviceSupport, stale simulators)
9. Diagnostic / crash reports (user + system)
10. Homebrew update + upgrade (formulae and casks) + cleanup + autoremove
11. `mise self-update` + plugin updates + tool upgrade
12. Helm plugin updates (`helm plugin update <name>` for every installed plugin)
13. `gcloud components update`
14. Report active versions of pyenv / goenv / tfenv / tenv / helm / gcloud

### Quick start

```bash
./stay_fresh.sh                  # interactive, full run
./stay_fresh.sh --dry-run        # preview plan
./stay_fresh.sh --yes --verbose  # non-interactive, stream output live
```

### Useful toggles

```bash
./stay_fresh.sh --no-sudo                # skip purge/DNS/system caches/system diagnostics
./stay_fresh.sh --skip-docker --skip-xcode

# Skip all dev-tool refresh steps in one flag:
./stay_fresh.sh --skip-devtools
#   = --skip-mise --skip-helm-plugins --skip-gcloud --skip-versions

# Upgrade casks pinned to :latest / auto_updates true (may prompt sudo):
./stay_fresh.sh --brew-greedy
```

Full list: `--skip-memory`, `--skip-dns`, `--skip-syscaches`,
`--skip-usercaches`, `--skip-trash`, `--skip-brew`, `--skip-devcaches`,
`--skip-docker`, `--skip-xcode`, `--skip-diagnostics`, `--skip-mise`,
`--skip-helm-plugins`, `--skip-gcloud`, `--skip-versions`, `--no-sudo`.

### Output

Prints a per-step plan, runs each step with OK / WARN / FAIL accounting,
then a final summary with:

- elapsed wall time
- `df` delta on `/`
- sum of per-step deltas (more precise than `df`)
- which steps passed / warned / were skipped / failed
- path to the full log file

### Exit codes

`0` finished (maybe with warnings) · `1` one or more steps hard-failed ·
`2` preflight failed · `3` bad args.

---

## `old_stay_fresh.sh`

Legacy step list, modernized. Preserves the original order/intent of the
historical stay-fresh script but is now self-contained (no `~/scripts/functions`
dependency) and actually clears caches reliably. Use this if you specifically
want the older, simpler flow; otherwise prefer `stay_fresh.sh`.

Steps (in order):

1. Kernel / Quick Look / Finder caches (`qlmanage -r`, `killall Finder`,
  `update_dyld_shared_cache` when SIP allows)
2. Purge inactive memory
3. Clear shell / tool history files (`.lesshst`, `.mysql_history`, `.psql_history`,
  `.node_repl_history`, `.python_history`)
4. Clear user caches (`~/Library/Caches`, Logs, Saved State, Xcode DerivedData/Archives,
  `composer clearcache`)
5. Update Homebrew (self-heals taps — detects default branch per tap instead of
  hard-coding `master`)
6. Upgrade Homebrew formulae + casks
7. Clean Homebrew caches (`brew cleanup --prune=3 -s`, `autoremove`, `tap --repair`)
8. List installed Homebrew versions
9. Terraform update via `tfenv`
10. Helm update (GitHub latest release)
11. Python update via `pyenv`
12. Go update via `gvm`
13. `gcloud components update`
14. Print AWS CLI version

### Quick start

```bash
./old_stay_fresh.sh                # interactive
./old_stay_fresh.sh --dry-run
./old_stay_fresh.sh --yes --no-sudo
```

Options: `--dry-run`, `--yes` / `-y`, `--no-sudo`, `--help` / `-h`.

Missing tools (e.g. no `gvm`, no `tfenv`) are detected and their steps are
politely skipped rather than failing the whole run.

---

## `zsh_aliases.zsh`

A curated set of zsh aliases and helper functions. Everything that depends
on an optional tool (`eza`, `bat`, `fd`, `rg`, `docker`, `kubectl`, `helm`,
`terraform`, `pyenv`, `goenv`, …) is **guarded behind `command -v`**, so the
file is safe to source on any machine.

### Install

```bash
ln -s "$PWD/zsh_aliases.zsh" "$HOME/.zsh_aliases.zsh"
echo '[[ -f "$HOME/.zsh_aliases.zsh" ]] && source "$HOME/.zsh_aliases.zsh"' >> ~/.zshrc
exec zsh
```

### Highlights

- **Safety defaults**: `cp`, `mv`, `rm` are `-i` by default (opt out with `\rm`)
- **Navigation**: `..`, `...`, `....`, `.....`, `-` (cd back), `~`, plus `mkcd`, `up N`
- **Listing**: `ls`/`l`/`ll`/`la`/`lt` use `eza` when available, fall back to `ls`
- **Better tools (auto)**: `cat`→`bat`, `find`→`fd`, `grep`→`rg`, `top`→`htop`, `df`→`duf`, `du`→`dust`
- **Git**: full suite of `g`* aliases (`gs`, `gaa`, `gcm`, `gco`, `gcb`, `gp`, `gpl`, `gl`, …)
plus `gwip` (stage + checkpoint commit) and `gprune` (delete merged branches)
- **Docker / compose**: `d`, `dps`, `dprune`, `dc`, `dcu`, `dcd`, `dcl`, …
- **Kubernetes**: `k`, `kg`, `kd`, `kl`, `kx`, `kns`
- **Homebrew**: `brewup` (update + upgrade + `--greedy` + cleanup + autoremove)
- **Python**: auto-inits `pyenv` + `pyenv-virtualenv`; `venv` creates/activates `.venv`
- **Go**: auto-inits `goenv`, ensures `$GOPATH/bin` on PATH; `gor`, `gob`, `got`, …
- **Terraform / OpenTofu / Helm**: `tf`*, `to*`, `h*` shortcuts
- **Script shortcuts**: `stay-fresh`, `install-apps`, `install-devtools`,
`bootstrap-mac` are auto-wired if the scripts exist next to this file
- **macOS helpers**: `flushdns`, `purgemem`, `showfiles`/`hidefiles`, `lock`,
`ejectall`, `localip`, `myip`, `pbj` (pretty-print clipboard JSON)
- **Functions**: `mkcd`, `extract` (tar/zip/rar/7z/…), `up N`, `mkbackup`, `weather [city]`

### Customizing

It's a single file — read it top to bottom, comment out anything you don't
like, or drop your own additions at the bottom. The `_ZSH_ALIASES_DIR`
variable resolves the directory of this file, so the `stay-fresh` /
`install-apps` aliases keep working regardless of where the repo lives.

---

## Logs

Every script writes a timestamped log to `$TMPDIR` (or `/tmp`):

```
/tmp/install_apps-YYYYMMDD-HHMMSS.log
/tmp/install_devtools-YYYYMMDD-HHMMSS.log
/tmp/stay_fresh-YYYYMMDD-HHMMSS.log
/tmp/old_stay_fresh-YYYYMMDD-HHMMSS.log
```

Pass `--verbose` / `-v` on `install_*` and `stay_fresh.sh` to stream output
live in addition to logging it.

## Safety notes

- Scripts refuse to run as `root`; they ask for `sudo` where needed and keep
the credential warm for the duration of the run.
- `--dry-run` is honored everywhere — nothing is changed and no `sudo`
prompt is triggered.
- `stay_fresh.sh` and `old_stay_fresh.sh` route all cache-clearing errors to
the log (not `/dev/null`), so if something refuses to delete you can see
*why* in the log afterwards.



