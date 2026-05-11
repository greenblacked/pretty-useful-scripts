# Chef cookbook test environment

Cookbooks are exercised with [Test Kitchen](https://kitchen.ci/) using the
**[kitchen-dokken](https://github.com/test-kitchen/kitchen-dokken)** driver:
Chef is pre-installed in upstream `dokken/*` images, so converges are faster
than a plain `kitchen-docker` flow.

**Cookstyle** (RuboCop rules for Chef), **yamllint**, **ChefSpec**, and
**InSpec** (via Kitchen) all run from the same **Docker runner** on your
machine. The host only needs **Docker Engine + Compose v2**; you do not need
Ruby, Bundler, or pip installed locally for the default workflow.

---

## Layout

| Path | Role |
| --- | --- |
| [`run.sh`](run.sh) | Primary entrypoint: `docker compose … run --rm kitchen …`. Supports `--rebuild`, `--shell`. |
| [`justfile`](justfile) | Shortcuts: `just lint`, `just spec`, `just verify`, `just ci`, … |
| [`docker/Dockerfile`](docker/Dockerfile) | `ruby:3.3-bookworm-slim`, build deps, **yamllint** (apt), Docker static CLI, `bundle install` |
| [`docker/docker-compose.yml`](docker/docker-compose.yml) | Mounts `..` → `/chef` (rw) and `/var/run/docker.sock`; `init: true`, TTY for Kitchen |
| [`docker/entrypoint.sh`](docker/entrypoint.sh) | `bundle check \|\| bundle install`, then `bundle exec` (except `yamllint` / `docker` / `bash` / `sh`) |
| [`kitchen.yml`](kitchen.yml) | dokken driver; platforms **Ubuntu 22.04/24.04**, **Debian 12**, **Rocky Linux 9**; suite `example` |
| [`Gemfile`](Gemfile) | test-kitchen, kitchen-dokken, kitchen-inspec; Cookstyle + ChefSpec + Berkshelf in groups |
| [`.rubocop.yml`](.rubocop.yml), [`.rspec`](.rspec) | Cookstyle + ChefSpec |
| [`.yamllint`](.yamllint), [`.editorconfig`](.editorconfig) | YAML + editor defaults |
| [`.devcontainer/`](.devcontainer/) | Dev container definition (same stack as the runner) |
| [`cookbooks/`](cookbooks/) | Your cookbooks. **`example`** includes Policyfile (sample), ChefSpec, and InSpec |

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with **Compose v2**
- Optional: [`just`](https://github.com/casey/just) for [`justfile`](justfile) tasks

---

## Quick start

From **`test-env/chef`**:

```bash
./run.sh                         # default: kitchen list
./run.sh kitchen verify          # InSpec after converge (all matching instances)
./run.sh cookstyle --display-cop-names cookbooks
./run.sh yamllint -c .yamllint .
./run.sh rspec cookbooks
./run.sh --rebuild               # rebuild image after Gemfile / Dockerfile edits
./run.sh --shell                 # bash inside the runner (debugging)
```

With **`just`**:

```bash
just             # list recipes
just lint        # Cookstyle
just yamllint    # YAML
just spec        # ChefSpec (no Kitchen containers)
just verify      # kitchen verify (all platforms in kitchen.yml)
just ci          # lint + yamllint + spec + kitchen verify ubuntu-2204
just shell       # interactive shell
```

Fast inner loop before Kitchen: **`just lint && just yamllint && just spec`**.

---

## How it works

1. **`run.sh`** builds (when needed) and runs the **kitchen** Compose service.
2. The container runs **`bundle exec`** for Ruby tools; **yamllint** is invoked
   as a system binary (see [`docker/entrypoint.sh`](docker/entrypoint.sh)).
3. **kitchen-dokken** uses the **host** Docker API (mounted socket) to create
   sibling containers (privileged, systemd `pid_one_command` per
   [`kitchen.yml`](kitchen.yml)).

---

## CI vs local

| Layer | Where | Command (local) |
| --- | --- | --- |
| Cookstyle | GitHub Actions + Docker runner | `./run.sh cookstyle --display-cop-names cookbooks` |
| yamllint | GitHub Actions (pip) + Docker runner (apt package) | `./run.sh yamllint -c .yamllint .` |
| ChefSpec | GitHub Actions + Docker runner | `./run.sh rspec cookbooks` |
| Test Kitchen + InSpec | **Local only** (Docker socket + dokken) | `./run.sh kitchen verify` |

Workflow file: **[`.github/workflows/chef.yml`](../../.github/workflows/chef.yml)**  
Kitchen is not run in CI because it needs DinD or a privileged runner; use
`just verify` or `./run.sh kitchen verify` on your workstation.

---

## Dependency management

[`cookbooks/example/Policyfile.rb`](cookbooks/example/Policyfile.rb) demonstrates
Policyfile pins for reproducible converges. To try it, point Kitchen at that
policy instead of `run_list` (see Chef docs for `policyfile` provisioner
options). **Berkshelf** is in the Gemfile if you prefer a `Berksfile`.

---

## Optional: Ruby on the host

If you already have Ruby **3.3+** and Bundler:

```bash
cd test-env/chef
bundle install
bundle exec cookstyle cookbooks
bundle exec rspec cookbooks
bundle exec kitchen verify
```

Install **yamllint** yourself (`pip install yamllint`) if you want parity with CI.

---

## Adding your own cookbooks

1. Place the cookbook under `cookbooks/<name>/`.
2. Edit [`kitchen.yml`](kitchen.yml): add or change a suite `run_list` to
   `recipe[<name>::default]` (or another recipe).
3. Add **ChefSpec** under `cookbooks/<name>/spec/unit/recipes/` and **InSpec**
   under `cookbooks/<name>/test/integration/<suite>/`.
