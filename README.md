# actions

Composite GitHub Actions shared by the cerebrai-app repositories.

| Action | What it does |
| --- | --- |
| [`claude`](claude/action.yml) | Runs Claude Code when someone mentions `@claude` |
| [`claude-review`](claude-review/action.yml) | Reviews a PR with the `code-review` plugin |
| [`ponytail-review`](ponytail-review/action.yml) | Reviews a PR with the third-party ponytail plugin and posts one report comment |
| [`minimize-ponytail-reviews`](minimize-ponytail-reviews/action.yml) | Collapses all but the newest ponytail report as outdated |
| [`renovate`](renovate/action.yml) | Runs self-hosted Renovate as a GitHub App |
| [`setup-rust`](setup-rust/action.yml) | Installs a Rust toolchain (or the MSRV), the cargo cache and an optional arm64 Linux cross toolchain under QEMU. Exports `RUSTUP_TOOLCHAIN`, so the requested toolchain wins over a `rust-toolchain.toml` |

Each `action.yml` documents its inputs.

There are also reusable workflows for Go repositories, which hold whole jobs rather than steps:

| Workflow | What it does |
| --- | --- |
| [`go-ci.yml`](.github/workflows/go-ci.yml) | gofmt, `go mod tidy -diff`, golangci-lint, `go test -race`, a build and `go vet` for every release platform with Go's cross compiler, a test with the `go` version from go.mod, and govulncheck |
| [`go-release.yml`](.github/workflows/go-release.yml) | On a `v*` tag: tests, builds every archive with GoReleaser on one `ubuntu-latest` runner, runs each Linux x86_64 binary, and publishes the archives and `checksums.txt` as one GitHub Release |

Their inputs are documented at the top of each file. See [Go repositories](#go-repositories) for callers.

## What stays in the calling workflow

A composite action is a list of steps, so the following can't move into it and stay in each
repository's workflow:

- **Triggers** (`on:`) and job-level conditions, such as the `@claude` mention check.
- **`permissions:`**, which are set per job. Each action's description lists what its job needs.
  Keep `ponytail-review` and `minimize-ponytail-reviews` in separate jobs: the job that runs the
  third-party plugin should not get write access.
- **Secrets.** Actions can't read `secrets`, so pass them as inputs.

## Usage

Pin to a commit, with the tag as a comment. Renovate (`helpers:pinGitHubActionDigests`) keeps
it current:

```yaml
- uses: cerebrai-app/actions/claude@<commit sha> # v1
  with:
    claude-code-oauth-token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

Full callers:
[claude.yml](https://github.com/cerebrai-app/brainctl/blob/main/.github/workflows/claude.yml),
[claude-code-review.yml](https://github.com/cerebrai-app/brainctl/blob/main/.github/workflows/claude-code-review.yml),
[renovate.yml](https://github.com/cerebrai-app/brainctl/blob/main/.github/workflows/renovate.yml),
[ci.yml](https://github.com/cerebrai-app/brainctl/blob/main/.github/workflows/ci.yml) in brainctl.

## Go repositories

A Go repository calls the reusable workflows for CI and releases, and the composite actions
above for Claude and Renovate, as any other repository does. The Go programs live together in
[go-cerebrai](https://github.com/cerebrai-app/go-cerebrai), one module with a `cmd/<name>`
package per program and their shared code under `internal/`. They are released together, under
one version. The examples below are its callers.

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

# One run per PR (or per branch/tag for pushes). A new commit on a PR cancels
# its previous run; runs on main and on tags are never cancelled.
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  ci:
    uses: cerebrai-app/actions/.github/workflows/go-ci.yml@<commit sha> # v2
    with:
      main-packages: ./cmd/brainctl ./cmd/workctl
      smoke-test-args: version # omit for a library
```

`.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags: ["v*"]
  pull_request: # builds a snapshot of everything, publishes nothing
    paths: [".github/workflows/release.yml", ".goreleaser.yaml"]

permissions:
  contents: read

concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  release:
    uses: cerebrai-app/actions/.github/workflows/go-release.yml@<commit sha> # v2
    permissions:
      contents: write # the publish job creates the release
```

Releases are built with [GoReleaser](https://goreleaser.com), pinned in `go-release.yml`. What to
build lives in the caller's `.goreleaser.yaml`; see
[go-cerebrai's](https://github.com/cerebrai-app/go-cerebrai/blob/main/.goreleaser.yaml) and
[the test app's](testdata/go-app/.goreleaser.yaml). The workflow requires that config to:

- disable `release` and `changelog`. The workflow's publish job creates the release itself, so
  GoReleaser runs without a token that can write.
- set `snapshot.version_template`, the version pull request builds report (e.g. `0.0.0-dev`).
- link `{{ .Version }}` (the tag without its `v`) into each binary, which prints
  `<binary> <version>` for `<binary> version`. Before publishing anything, the workflow runs
  every linux/amd64 binary with `version` and checks that output (`smoke-test-args` changes the
  arguments; empty skips the check).

The release holds the archives and GoReleaser's `checksums.txt`. Check a download with
`sha256sum --ignore-missing -c checksums.txt`.

Everything runs on `ubuntu-latest`. `go-ci.yml` builds and vets linux/amd64, linux/arm64,
darwin/amd64, darwin/arm64 and windows/amd64 with Go's cross compiler (`targets` changes the
list; keep it in step with `.goreleaser.yaml`). Only the Linux x86_64 binaries and tests actually
run; the other platforms are compiled and vetted, not executed. To also run the tests elsewhere,
pass runners to `go-ci.yml`'s `os`, for example `'["ubuntu-latest", "windows-latest"]'`.

`renovate.json`, for the Go modules and the pinned actions and workflows:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended", "helpers:pinGitHubActionDigests"],
  "enabledManagers": ["gomod", "github-actions"],
  "postUpdateOptions": ["gomodTidy"]
}
```

`go-ci.yml` sets `GOTOOLCHAIN=local`, so Go never downloads a different toolchain: CI tests
with the latest stable Go, and with exactly the `go` version from go.mod. The `go` line is the
minimum supported Go version. Raise it only when the code or a dependency needs a newer
release, and keep it within the [releases Go supports](https://go.dev/doc/devel/release#policy).

[`test-go-workflows.yml`](.github/workflows/test-go-workflows.yml) runs both workflows against
[`testdata/go-app`](testdata/go-app) on every pull request here.

## Releasing

Tag a commit on `main` with `v<major>.<minor>.<patch>`, then move the `v<major>` tag to it. A
breaking change to an input bumps the major version.

## Renovate

The actions here pin their own dependencies: other actions, the ponytail plugin marketplace and
the Renovate image. This repository runs Renovate on itself (`.github/workflows/renovate.yml`) to
keep those pins current. Callers only need Renovate's `github-actions` manager to track this
repository.
