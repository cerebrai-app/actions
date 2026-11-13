# actions

Composite GitHub Actions shared by the cerebrai-app repositories.

| Action | What it does |
| --- | --- |
| [`claude`](claude/action.yml) | Runs Claude Code when someone mentions `@claude` |
| [`claude-review`](claude-review/action.yml) | Reviews a PR with the `code-review` plugin |
| [`ponytail-review`](ponytail-review/action.yml) | Reviews a PR with the third-party ponytail plugin and posts one report comment |
| [`minimize-ponytail-reviews`](minimize-ponytail-reviews/action.yml) | Collapses all but the newest ponytail report as outdated |
| [`renovate`](renovate/action.yml) | Runs self-hosted Renovate as a GitHub App |
| [`setup-rust`](setup-rust/action.yml) | Installs a Rust toolchain (or the MSRV), the cargo cache and an optional arm64 Linux cross toolchain under QEMU |

Each `action.yml` documents its inputs.

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

## Releasing

Tag a commit on `main` with `v<major>.<minor>.<patch>`, then move the `v<major>` tag to it. A
breaking change to an input bumps the major version.

## Renovate

The actions here pin their own dependencies: other actions, the ponytail plugin marketplace and
the Renovate image. This repository runs Renovate on itself (`.github/workflows/renovate.yml`) to
keep those pins current. Callers only need Renovate's `github-actions` manager to track this
repository.
