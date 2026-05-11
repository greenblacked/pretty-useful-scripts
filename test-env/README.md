# test-env

Sandboxes for automated checks that do not live inside the main script trees
(`git/`, `macos-initial-setup/`, `mikrotik/`). Each subfolder (`chef/`, `python/`)
is self-contained: Docker on the host, optional `just`, and its own README.

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
  Cookstyle, yamllint, and ChefSpec on pushes/PRs that touch `test-env/chef/**`
  (and on pushes to `master` / `dev`). Kitchen integration stays local (needs
  Docker + privileged dokken).

Full commands, layout table, and cookbook authoring notes:
**[`chef/README.md`](chef/README.md)**.

## Python (`python/`)

**[`python/`](python/)** — Python 3.12 in Docker with **Ruff** (lint + format),
**pytest**, and optional **mypy** (`just typecheck`; not run in GitHub Actions):

- **Docker runner** — [`python/run.sh`](python/run.sh) starts a long-running Compose
  `dev` service, mounts `test-env/python` at `/python`, and `exec`s commands so
  repeated runs stay fast.
- **Tasks** — [`python/justfile`](python/justfile) wraps `run.sh` for `just lint`,
  `just format-check`, `just test`, `just ci`, etc.
- **Editor** — [`.devcontainer/`](python/.devcontainer/) reuses the same image for
  VS Code / Cursor.
- **CI** — [`.github/workflows/python.yml`](../.github/workflows/python.yml) runs
  `ruff check`, `ruff format --check`, and `pytest` on pushes/PRs that touch
  `test-env/python/**` (and on pushes to `master` / `dev`).

Details and layout table: **[`python/README.md`](python/README.md)**.
