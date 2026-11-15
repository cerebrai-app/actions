#!/usr/bin/env bash
# Installs jq and puts it on PATH for the rest of the job.
#
# Self-hosted runners don't come with jq, so every job that runs it installs it
# first. The release binary is checked against the release's sha256sum.txt and
# kept in the runner's tool cache, so later jobs on the same runner reuse it.
#
# Used by setup-jq/action.yml, and run directly by the other composite actions
# in this repository that call jq, as "$GITHUB_ACTION_PATH/../setup-jq/install.sh".
#
# Environment: JQ_VERSION (optional) overrides the pinned version, e.g. 1.8.2.
# Supports Linux and macOS runners on x64 and arm64.
set -euo pipefail

# renovate: datasource=github-releases depName=jqlang/jq
DEFAULT_JQ_VERSION=1.8.2

version="${JQ_VERSION:-$DEFAULT_JQ_VERSION}"
version="jq-${version#jq-}"

case "${RUNNER_ARCH:-$(uname -m)}" in
  X64 | x86_64 | amd64) arch=amd64 ;;
  ARM64 | arm64 | aarch64) arch=arm64 ;;
  *) echo "::error::setup-jq: unsupported runner architecture ${RUNNER_ARCH:-$(uname -m)}"; exit 1 ;;
esac
case "${RUNNER_OS:-$(uname -s)}" in
  Linux) platform=linux ;;
  macOS | Darwin) platform=macos ;;
  *) echo "::error::setup-jq: unsupported runner OS ${RUNNER_OS:-$(uname -s)}"; exit 1 ;;
esac

name="jq-${platform}-${arch}"
cache="${RUNNER_TOOL_CACHE:-${RUNNER_TEMP:?}}/jq/${version#jq-}/${arch}"

if [[ ! -x "$cache/bin/jq" ]]; then
  base="https://github.com/jqlang/jq/releases/download/${version}"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL --retry 3 -o "$tmp/$name" "$base/$name"
  curl -fsSL --retry 3 -o "$tmp/sha256sum.txt" "$base/sha256sum.txt"
  expected=$(awk -v f="$name" '$2 == f { print $1 }' "$tmp/sha256sum.txt")
  if [[ -z "$expected" ]]; then
    echo "::error::setup-jq: $name is not in the release's sha256sum.txt"
    exit 1
  fi
  if command -v sha256sum >/dev/null; then
    actual=$(sha256sum "$tmp/$name" | awk '{ print $1 }')
  else
    actual=$(shasum -a 256 "$tmp/$name" | awk '{ print $1 }')
  fi
  if [[ "$actual" != "$expected" ]]; then
    echo "::error::setup-jq: checksum mismatch for $name (expected $expected, got $actual)"
    exit 1
  fi
  mkdir -p "$cache/bin"
  chmod +x "$tmp/$name"
  mv "$tmp/$name" "${cache:?}/bin/jq"
fi

echo "$cache/bin" >> "${GITHUB_PATH:?}"
"$cache/bin/jq" --version
