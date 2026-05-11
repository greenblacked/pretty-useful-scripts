# Go test environment

Develop and run checks in **Docker** so your laptop does not need a local Go
toolchain. The image ships **Go 1.23**, **golangci-lint**, **goimports**, and
**govulncheck**; module + build caches live in named Compose volumes so
recompiles are quick.

The stack keeps a **long-running dev container** so every `run.sh` invocation
`docker compose exec`s into it — milliseconds, not seconds.

---

## Layout

| Path | Role |
| --- | --- |
| [`run.sh`](run.sh) | Entrypoint. Subcommands: `up`/`down`/`logs`/`ps`/`shell`. Flags: `--once`, `--rebuild`. |
| [`justfile`](justfile) | Shortcuts: `just up`, `just test`, `just lint`, `just ci`, … |
| [`docker/Dockerfile`](docker/Dockerfile) | `golang:1.23-bookworm` + golangci-lint + goimports + govulncheck |
| [`docker/docker-compose.yml`](docker/docker-compose.yml) | Long-running `dev` service, `go-mod-cache` + `go-build-cache` volumes |
| [`.golangci.yml`](.golangci.yml) | Lint config (errcheck, staticcheck, gosec, revive, …) |
| [`go.mod`](go.mod) | Module — `github.com/pretty-useful-scripts/test-env/go` |
| [`internal/sample/`](internal/sample/) | Sample package with table test |
| [`cmd/hello/`](cmd/hello/) | Sample binary that prints `sample.Greet(...)` |
| [`.devcontainer/`](.devcontainer/) | VS Code / Cursor dev container (same image) |
| [`.editorconfig`](.editorconfig) | Tabs for Go, spaces for everything else |

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with **Compose v2**
- Optional: [`just`](https://github.com/casey/just)

---

## Quick start

From **`test-env/go`**:

```bash
./run.sh up                       # start container in the background
./run.sh go test ./...            # exec inside it
./run.sh golangci-lint run
./run.sh govulncheck ./...
./run.sh go run ./cmd/hello dock  # try the sample binary
./run.sh shell                    # interactive bash
./run.sh down
```

With **`just`**:

```bash
just up           # start container
just build        # go build ./...
just test         # go test -race
just cov          # coverage report
just lint         # golangci-lint
just vet          # go vet
just format       # goimports -w
just vuln         # govulncheck
just tidy         # go mod tidy
just ci           # vet + lint + format-check + test + vuln
just hello docker # run the sample binary
just shell
just down
```

The container survives between commands, so the second `go test` is fast —
the build cache stays warm in the `go-build-cache` volume.

## One-shot mode

```bash
./run.sh --once go test ./...
./run.sh --once --shell
```

## After dependency changes

`go.mod` / `Dockerfile` changed? Rebuild:

```bash
./run.sh --rebuild
./run.sh down && ./run.sh up
```

Module cache lives in a named volume, so a rebuild still reuses downloaded
modules.

---

## CI vs local

Local parity with automation is usually **`just ci`** inside Docker: **`go vet`**
→ **golangci-lint** → **goimports format check** → **`go test -race`** →
**`govulncheck`**.

If the repository ships **[`.github/workflows/go.yml`](../../.github/workflows/go.yml)**,
use that file for the exact GitHub Actions matrix and triggers; otherwise run
`just ci` before pushing.

---

## Optional: Go on the host

If you already have Go **1.23+**:

```bash
cd test-env/go
go test ./...
go run ./cmd/hello docker
```
