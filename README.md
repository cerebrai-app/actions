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
| [`go-release.yml`](.github/workflows/go-release.yml) | On a `v*` tag: tests, cross-compiles a binary per platform on one `ubuntu-latest` runner, and publishes them with `.sha256` files as a GitHub Release |

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
above for Claude and Renovate, as any other repository does. Shared Go code, such as the
`buildinfo` package that the release workflow links the version into, lives in
[go-cerebrai](https://github.com/cerebrai-app/go-cerebrai).

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  ci:
    uses: cerebrai-app/actions/.github/workflows/go-ci.yml@<commit sha> # v1
    with:
      smoke-test-args: version # omit for a library
```

`.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags: ["v*"]
  pull_request:
    paths: [".github/workflows/release.yml"] # builds everything, publishes nothing

permissions:
  contents: read

jobs:
  release:
    uses: cerebrai-app/actions/.github/workflows/go-release.yml@<commit sha> # v1
    permissions:
      contents: write # the publish job creates the release
    with:
      binary-name: brainctl
```

The program prints `<binary-name> <version>` for `<binary-name> version`: the release workflow
runs the linux/amd64 binary with `version` before publishing anything and checks that output. It links the
version from the tag into `github.com/cerebrai-app/go-cerebrai/buildinfo.version`, so the program
gets it from `buildinfo.Version()`. A program with its own variable sets `version-variable`, for
example to `main.version`.

The archives are named `<binary-name>-v<version>-<goos>-<goarch>.tar.gz` (`.zip` for Windows).
Binaries are built with cgo off, so the Linux ones are static and run on any distribution.

Everything runs on `ubuntu-latest`. Both workflows build linux/amd64, linux/arm64,
darwin/amd64, darwin/arm64 and windows/amd64 with Go's cross compiler (`targets` changes the
list). Only the Linux x86_64 binary and tests actually run; the other platforms are compiled and
vetted, not executed. To also run the tests elsewhere, pass runners to `go-ci.yml`'s `os`, for
example `'["ubuntu-latest", "windows-latest"]'`.

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
