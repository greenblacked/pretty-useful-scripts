# test-env

Sandboxes for automated checks that do not live inside the main script trees
(`git/`, `macos-initial-setup/`, `mikrotik/`). Each subfolder (`chef/`, `python/`,
`go/`) is self-contained: Docker on the host, optional `just`, and its own README.

## Chef (`chef/`)

**[`chef/`](chef/)** — Chef Infra cookbook toolchain in one place:

- **Docker runner** — [`chef/run.sh`](chef/run.sh) starts a Compose service with
  Ruby, gems, the Docker CLI, and **yamllint**; it mounts this repo at `/chef` and
  the host **`/var/run/docker.sock`** so [kitchen-dokken](https://github.com/test-kitchen/kitchen-dokken)
  can start converge containers on your machine.
- **Tasks** — [`chef/justfile`](chef/justfile) wraps `run.sh` for `just lint`,
  `just spec`, `just verify`, etc.
- **Editor** — [`.devcontainer/`](chef/.devcontainer/) reuses the same image for
  VS Code / Cursor.
- **CI** — [`.github/workflows/chef.yml`](../.github/workflows/chef.yml) runs
  Cookstyle, yamllint (pip on the runner), and ChefSpec on pushes/PRs that touch
  `test-env/chef/**` (and on pushes to `master` / `dev` when configured). Kitchen
  stays local (Docker socket + privileged dokken).

Full commands, layout table, and cookbook authoring notes:
**[`chef/README.md`](chef/README.md)**.

## Python (`python/`)

**[`python/`](python/)** — Python 3.12 in Docker with **Ruff** (lint + format),
**pytest**, and optional **mypy** (local / `just typecheck`; not in Actions today):

- **Docker runner** — [`python/run.sh`](python/run.sh) starts a long-running Compose
  `dev` service, mounts `test-env/python` at `/python`, and `exec`s commands so
  repeated runs stay fast.
- **Tasks** — [`python/justfile`](python/justfile) wraps `run.sh` for `just lint`,
  `just format-check`, `just test`, `just typecheck`, `just ci`, etc.
- **Editor** — [`.devcontainer/`](python/.devcontainer/) reuses the same image for
  VS Code / Cursor.
- **CI** — [`.github/workflows/python.yml`](../.github/workflows/python.yml) runs
  `pip install -e ".[dev]"`, then `ruff check`, `ruff format --check`, and
  `pytest` on pushes/PRs that touch `test-env/python/**` (and on pushes to
  `master` / `dev` when configured).

Details and layout table: **[`python/README.md`](python/README.md)**.

## Go (`go/`)

**[`go/`](go/)** — Go 1.23 in Docker with **golangci-lint**, **goimports**, and
**govulncheck**:

- **Docker runner** — [`go/run.sh`](go/run.sh) starts a long-running Compose
  `dev` service; module and build caches live in named volumes so rebuilds are
  fast.
- **Tasks** — [`go/justfile`](go/justfile) wraps `run.sh` for `just test`,
  `just lint`, `just cov`, `just vuln`, `just ci`, etc.
- **Editor** — [`.devcontainer/`](go/.devcontainer/) reuses the same image for
  VS Code / Cursor.
- **CI** — If [`.github/workflows/go.yml`](../.github/workflows/go.yml) is in the
  tree, use it as the source of truth for GitHub Actions. Locally, `just ci` runs
  `go vet`, golangci-lint, goimports format check, `go test -race`, and
  `govulncheck` inside Docker.

Details and layout table: **[`go/README.md`](go/README.md)**.
