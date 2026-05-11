# test-env

Sandboxes for automated checks that do not live inside the main script trees
(`git/`, `macos-initial-setup/`, `mikrotik/`).

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
  Cookstyle, yamllint, and ChefSpec on every PR that touches `test-env/chef/**`.
  Kitchen integration stays local (needs Docker + privileged dokken).

Full commands, layout table, and cookbook authoring notes:
**[`chef/README.md`](chef/README.md)**.
