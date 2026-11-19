# actions

Composite GitHub Actions shared by the cerebrai-app repositories.

| Action | What it does |
| --- | --- |
| [`claude`](claude/action.yml) | Runs Claude Code when someone mentions `@claude` |
| [`claude-review`](claude-review/action.yml) | Reviews a PR with the `code-review` plugin |
| [`ponytail-review`](ponytail-review/action.yml) | Reviews a PR with the third-party ponytail plugin and posts one report comment |
| [`minimize-ponytail-reviews`](minimize-ponytail-reviews/action.yml) | Collapses all but the newest ponytail report as outdated |
| [`renovate`](renovate/action.yml) | Runs self-hosted Renovate as a GitHub App |
| [`release-notes`](release-notes/action.yml) | Writes the release notes for a `vX.Y.Z` tag with Claude Code, from the commits and PRs since the previous version, and uploads them as an artifact |
| [`publish-release-notes`](publish-release-notes/action.yml) | Puts those notes on the tag's GitHub Release, creating it if needed. Runs in its own job with `contents: write` |
| [`setup-gh`](setup-gh/action.yml) | Installs the GitHub CLI (`gh`), checked against the release's checksums and kept in the runner's tool cache, for runners that don't come with it (e.g. self-hosted ones). The actions here that call `gh` already install it |
| [`setup-jq`](setup-jq/action.yml) | Installs `jq`, checked against the release's checksums and kept in the runner's tool cache, for runners that don't come with it (e.g. self-hosted ones). The actions here that call `jq` already install it |
| [`go-lint`](go-lint/action.yml) | gofmt, `go mod tidy -diff` and golangci-lint for a Go module |
| [`go-test`](go-test/action.yml) | `go build` and `go test -race` on the latest stable Go or exactly the `go` version from go.mod, and an optional smoke test of each main package |
| [`go-cross-build`](go-cross-build/action.yml) | `go build` and `go vet` for every release platform with Go's cross compiler |
| [`govulncheck`](govulncheck/action.yml) | Known vulnerabilities in the code paths a Go module actually calls |
| [`go-release-build`](go-release-build/action.yml) | Tests a Go module, builds every archive with GoReleaser, runs each Linux x86_64 binary and uploads the archives for `go-release-publish`. Builds a snapshot off tags |
| [`go-release-check-tap-app`](go-release-check-tap-app/action.yml) | Checks that the GitHub App can write to the Homebrew tap and Scoop bucket repositories |
| [`go-release-publish`](go-release-publish/action.yml) | On a `vX.Y.Z` tag: build attestations, the GitHub Release with the archives and `checksums.txt`, and optionally the Homebrew casks and Scoop manifests |
| [`setup-rust`](setup-rust/action.yml) | Installs a Rust toolchain (or the MSRV), the cargo cache and an optional arm64 Linux cross toolchain under QEMU. Exports `RUSTUP_TOOLCHAIN`, so the requested toolchain wins over a `rust-toolchain.toml` |

Each `action.yml` documents its inputs.

## What stays in the calling workflow

A composite action is a list of steps, so the following can't move into it and stay in each
repository's workflow:

- **Triggers** (`on:`) and job-level conditions, such as the `@claude` mention check.
- **`permissions:`**, which are set per job. Each action's description lists what its job needs.
  Keep `ponytail-review` and `minimize-ponytail-reviews` in separate jobs: the job that runs the
  third-party plugin should not get write access. The same goes for `release-notes` and
  `publish-release-notes`: Claude writes the notes in a job that can only read.
- **Secrets.** Actions can't read `secrets`, so pass them as inputs.
- **Jobs**: which actions run in parallel, a `matrix`, `needs` between jobs and their outputs.
  Each action documents the job it expects; the Go callers below show a full set.

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

A Go repository uses the Go actions above in its own CI and release jobs, and the other actions
for Claude and Renovate, as any other repository does. The Go programs live together in
[go-cerebrai](https://github.com/cerebrai-app/go-cerebrai), one module with a `cmd/<name>`
package per program and their shared code under `internal/`. They are released together, under
one version. The examples below are its workflows. Each job checks out the repository and runs
one action; the actions set up Go themselves. For a module outside the repository root, pass
`working-directory` to each action.

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
  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: cerebrai-app/actions/go-lint@<commit sha> # v4

  # The latest stable Go with the race detector and a smoke test, and exactly
  # the go version from go.mod, so the declared minimum is a tested one.
  test:
    name: Test (${{ matrix.go }})
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          - go: stable
            race: 'true'
          - go: go.mod
            race: 'false'
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: cerebrai-app/actions/go-test@<commit sha> # v4
        with:
          go-version: ${{ matrix.go }}
          race: ${{ matrix.race }}
          main-packages: ./cmd/brainctl ./cmd/workctl
          smoke-test-args: ${{ matrix.go == 'stable' && 'version' || '' }}

  cross-build:
    name: Cross-build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: cerebrai-app/actions/go-cross-build@<commit sha> # v4

  govulncheck:
    name: govulncheck
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: cerebrai-app/actions/govulncheck@<commit sha> # v4
```

For a library, leave out `main-packages` and `smoke-test-args`.

`.github/workflows/release.yml`:

```yaml
name: Release

# A tag like v0.1.0 builds every program for each platform with GoReleaser
# (.goreleaser.yaml) and publishes them in one GitHub Release, then pushes the
# Homebrew casks and Scoop manifests. Every pull request builds a snapshot and
# checks the tap app, and publishes nothing, so a broken release shows up
# before a tag.
on:
  push:
    tags: ["v*"]
  pull_request:

permissions:
  contents: read

concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  build:
    name: Test and build
    runs-on: ubuntu-latest
    outputs:
      go-version: ${{ steps.build.outputs.go-version }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0 # GoReleaser and the default-branch check need the history and tags
          persist-credentials: false
      - id: build
        uses: cerebrai-app/actions/go-release-build@<commit sha> # v4

  tap-app:
    name: Check tap app
    runs-on: ubuntu-latest
    permissions: {}
    steps:
      - uses: cerebrai-app/actions/go-release-check-tap-app@<commit sha> # v4
        with:
          tap-repositories: homebrew-tap,scoop-bucket
          app-client-id: ${{ secrets.RELEASE_APP_CLIENT_ID }}
          app-private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}

  publish:
    name: Publish release
    needs: [build, tap-app]
    if: ${{ github.ref_type == 'tag' }}
    runs-on: ubuntu-latest
    permissions:
      contents: write # create the release
      id-token: write # sign the build attestations
      attestations: write # store them
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0
          persist-credentials: false
      - uses: cerebrai-app/actions/go-release-publish@<commit sha> # v4
        with:
          go-version: ${{ needs.build.outputs.go-version }}
          tap-repositories: homebrew-tap,scoop-bucket
          app-client-id: ${{ secrets.RELEASE_APP_CLIENT_ID }}
          app-private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}
```

Without Homebrew and Scoop, leave out the `tap-app` job (and `tap-app` from `needs`) and the
`tap-repositories` and app inputs of `go-release-publish`.

Releases are built with [GoReleaser](https://goreleaser.com), pinned in `go-release-build` and
`go-release-publish`. What to build lives in the caller's `.goreleaser.yaml`; see
[go-cerebrai's](https://github.com/cerebrai-app/go-cerebrai/blob/main/.goreleaser.yaml) and
[the test app's](testdata/go-app/.goreleaser.yaml). The actions require that config to:

- disable `release` and `changelog`. `go-release-publish` creates the release itself, so
  GoReleaser never gets a token that can write to the calling repository.
- set `snapshot.version_template`, the version pull request builds report (e.g. `0.0.0-dev`).
- link `{{ .Version }}` (the tag without its `v`) into each binary, which prints
  `<binary> <version>` for `<binary> version`. Before anything is uploaded, `go-release-build`
  runs every linux/amd64 binary with `version` and checks that output (`smoke-test-args` changes
  the arguments; empty skips the check).
- build reproducibly: `mod_timestamp`, `-trimpath`, and archive `builds_info` and `files`
  timestamps set to `{{ .CommitDate }}`. Publishing the Homebrew casks and Scoop manifests
  rebuilds the archives, and `go-release-publish` checks that the rebuild matches the release.

A release holds the archives and GoReleaser's `checksums.txt`, and every archive gets a
[build provenance attestation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations).
Check a download with `sha256sum --ignore-missing -c checksums.txt`, and where it was built with
`gh attestation verify <archive> --owner cerebrai-app`.

### Homebrew and Scoop

With `homebrew_casks` and `scoops` in `.goreleaser.yaml`, `go-release-publish` runs GoReleaser a
second time to push them to a tap and a bucket repository. It does that with a GitHub App token
that can write to those repositories only. Set up once per organization:

1. Create the repositories, e.g. `homebrew-tap` (Homebrew requires the `homebrew-` prefix) and
   `scoop-bucket`. Each needs a default branch, so start them with a README.
2. Create a GitHub App with **Contents: read and write** and no other permissions, and install
   it on those two repositories only.
3. Add its Client ID and private key (the whole `.pem` file) as secrets, e.g.
   `RELEASE_APP_CLIENT_ID` and `RELEASE_APP_PRIVATE_KEY`, at the organization or repository
   level, and pass them as `app-client-id` and `app-private-key`.

The `Check tap app` job (`go-release-check-tap-app`) creates the same token on every run, pull
requests included, and reads each tap repository with it. A missing installation, a missing
Contents permission or secrets from the wrong app fail it there, and on a tag they stop the
release before anything is published. Runs without the secrets (pull requests from forks,
Dependabot) skip the check with a notice.

Prerelease tags never update the casks and manifests (`skip_upload: auto`).

Everything runs on `ubuntu-latest`. `go-cross-build` builds and vets linux/amd64,
linux/arm64, darwin/amd64, darwin/arm64, windows/amd64 and windows/arm64 with Go's cross compiler
(`targets` changes the list; keep it in step with `.goreleaser.yaml`). Only the Linux x86_64
binaries and tests actually run; the other platforms are compiled and vetted, not executed. To
also run the tests elsewhere, add runners to the `test` job's matrix, for example
`os: [ubuntu-latest, windows-latest]` with `runs-on: ${{ matrix.os }}`.

`renovate.json`, for the Go modules and the pinned actions:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended", "helpers:pinGitHubActionDigests"],
  "prHourlyLimit": 0,
  "enabledManagers": ["gomod", "github-actions"],
  "postUpdateOptions": ["gomodTidy"]
}
```

The Go actions set `GOTOOLCHAIN=local`, so Go never downloads a different toolchain: CI tests
with the latest stable Go, and with exactly the `go` version from go.mod. The `go` line is the
minimum supported Go version. Raise it only when the code or a dependency needs a newer
release, and keep it within the [releases Go supports](https://go.dev/doc/devel/release#policy).

[`test-go-actions.yml`](.github/workflows/test-go-actions.yml) runs the Go actions against
[`testdata/go-app`](testdata/go-app) on every pull request here, with the same jobs.

## Releasing

Tag a commit on `main` with `v<major>.<minor>.<patch>`, then move the `v<major>` tag to it. A
breaking change to an input bumps the major version.

Pushing the `v<major>.<minor>.<patch>` tag runs
[`release-notes.yml`](.github/workflows/release-notes.yml), which uses this repository's own
`release-notes` and `publish-release-notes` actions: Claude Code reads the commits and pull requests
since the previous version and writes the notes, breaking changes first, and a second job creates
the GitHub Release with them. Creating the release from the web UI instead works too; the workflow
fills in its notes. To rewrite the notes of an existing tag, run the workflow by hand from the
Actions tab with that tag. It needs the `CLAUDE_CODE_OAUTH_TOKEN` secret, like the other Claude
workflows. [cerebrai-app/_template](https://github.com/cerebrai-app/_template) has the same workflow
for new repositories, with the actions pinned by commit.

## Renovate

The actions here pin their own dependencies: other actions, the ponytail plugin marketplace and
the Renovate image. This repository runs Renovate on itself (`.github/workflows/renovate.yml`) to
keep those pins current. Callers only need Renovate's `github-actions` manager to track this
repository.
