# Python test environment

Develop and run checks in **Docker** so your laptop does not need a local Python
toolchain. The image ships **Python 3.12**, **Ruff** (lint + formatter),
**pytest**, and **mypy**; your code lives under [`src/`](src/) (sample package
**`sample`**) and [`tests/`](tests/).

The Compose stack keeps a **long-running dev container** so every `run.sh`
invocation `docker compose exec`s into it — milliseconds, not seconds.

---

## Layout

| Path | Role |
| --- | --- |
| [`run.sh`](run.sh) | Entrypoint. Subcommands: `up`/`down`/`logs`/`ps`/`shell`. Flags: `--once`, `--rebuild`. |
| [`justfile`](justfile) | Shortcuts: `just up`, `just lint`, `just test`, `just ci`, … |
| [`docker/Dockerfile`](docker/Dockerfile) | `python:3.12-slim-bookworm`, cached `pip install -e ".[dev]"` |
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
./run.sh mypy                     # optional; not run in GitHub Actions
./run.sh shell                    # interactive bash
./run.sh logs                     # tail dev container logs
./run.sh down                     # stop
```

With **`just`**:

```bash
just up           # start container
just lint         # ruff check
just test         # pytest
just typecheck    # mypy
just cov          # pytest with coverage
just ci           # lint + format-check + typecheck + test
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

## CI vs local

| Step | GitHub Actions | Local (Docker) |
| --- | --- | --- |
| Ruff lint (`ruff check`) | Yes | `./run.sh ruff check .` or `just lint` |
| Ruff format (`ruff format --check`) | Yes | `./run.sh ruff format --check .` or `just format-check` |
| pytest | Yes | `./run.sh pytest -q` or `just test` |
| mypy | No (run locally) | `./run.sh mypy` or `just typecheck` |

When the workflow is present in the tree, it lives at
**[`.github/workflows/python.yml`](../../.github/workflows/python.yml)** and
runs on pushes and pull requests that touch `test-env/python/**` (and on pushes
to `master` / `dev` when those branches are configured there).

