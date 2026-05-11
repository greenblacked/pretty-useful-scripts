# Python test environment

Develop and run checks in **Docker** so your laptop does not need a local Python
toolchain. The image ships **Python 3.12**, **Ruff** (lint + formatter),
**pytest**, **mypy**, and the meta-linters **shellcheck**, **hadolint**, and
**yamllint** for the test-env scaffolding itself. Your code lives under
[`src/`](src/) (sample package **`sample`**) and [`tests/`](tests/).

The Compose stack keeps a **long-running dev container** so every `run.sh`
invocation `docker compose exec`s into it — milliseconds, not seconds.

---

## Layout

| Path | Role |
| --- | --- |
| [`run.sh`](run.sh) | Entrypoint. Subcommands: `up`/`down`/`logs`/`ps`/`shell`. Flags: `--once`, `--rebuild`. |
| [`justfile`](justfile) | Shortcuts: `just up`, `just lint`, `just test`, `just ci`, … |
| [`docker/Dockerfile`](docker/Dockerfile) | `python:3.12-slim-bookworm`, cached `pip install -e ".[dev]"`, **shellcheck / hadolint / yamllint** baked in |
| [`docker/docker-compose.yml`](docker/docker-compose.yml) | Long-running `dev` service, `pip-cache` named volume |
| [`pyproject.toml`](pyproject.toml) | Package metadata, Ruff/pytest/mypy settings, **`dev`** extras |
| [`.devcontainer/`](.devcontainer/) | VS Code / Cursor dev container (same image) |
| [`.editorconfig`](.editorconfig) | Editor defaults |

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with **Compose v2**
- Optional: [`just`](https://github.com/casey/just)

---

## Quick start (long-running container — recommended)

From **`test-env/python`**:

```bash
./run.sh up                       # start container in the background
./run.sh pytest -q                # exec inside it
./run.sh ruff check .
./run.sh ruff format --check .
./run.sh mypy
./run.sh shellcheck run.sh        # lint the scaffolding itself
./run.sh hadolint docker/Dockerfile
./run.sh yamllint docker/docker-compose.yml
./run.sh shell                    # interactive bash
./run.sh logs                     # tail dev container logs
./run.sh down                     # stop
```

With **`just`**:

```bash
just up           # start container
just lint         # ruff check (source code)
just lint-env     # shellcheck + hadolint + yamllint (test-env scaffolding)
just test         # pytest
just typecheck    # mypy
just cov          # pytest with coverage
just ci           # lint-env + lint + format-check + typecheck + test
just shell        # interactive shell
just down         # stop
```

The container survives between commands, so the second `pytest` run is
near-instant.

## One-shot mode

Skip the persistent container with `--once`:

```bash
./run.sh --once pytest -q
./run.sh --once --shell
```

## After dependency changes

`pyproject.toml` or `Dockerfile` changed? Rebuild:

```bash
./run.sh --rebuild
./run.sh down && ./run.sh up      # recreate the dev container
```

The Compose stack mounts a named `pip-cache` volume, so even rebuilds reuse
wheels.

---

## Linters

| Target | Tool | Recipe |
| --- | --- | --- |
| Python source | Ruff (`ruff check`, `ruff format`) | `just lint` / `just format-check` |
| Type checking | mypy | `just typecheck` |
| Shell scripts (`run.sh`) | shellcheck | `just lint-env` |
| Dockerfile | hadolint | `just lint-env` |
| YAML (`docker-compose.yml`) | yamllint | `just lint-env` |

`just ci` runs all of the above (plus tests) in one go.
