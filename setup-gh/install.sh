#!/usr/bin/env bash
# Installs the GitHub CLI (gh) and puts it on PATH for the rest of the job.
#
# Self-hosted runners don't come with gh, so every job that runs it installs it
# first. The release archive is checked against the release's checksums.txt and
# kept in the runner's tool cache, so later jobs on the same runner reuse it.
#
# Used by setup-gh/action.yml, and run directly by the other composite actions
# in this repository that call gh, as "$GITHUB_ACTION_PATH/../setup-gh/install.sh".
#
# Environment: GH_VERSION (optional) overrides the pinned version, e.g. v2.104.0.
# Supports Linux and macOS runners on x64 and arm64.
set -euo pipefail

# renovate: datasource=github-releases depName=cli/cli
DEFAULT_GH_VERSION=v2.104.0

version="${GH_VERSION:-$DEFAULT_GH_VERSION}"
version="${version#v}"

case "${RUNNER_ARCH:-$(uname -m)}" in
  X64 | x86_64 | amd64) arch=amd64 ;;
  ARM64 | arm64 | aarch64) arch=arm64 ;;
  *) echo "::error::setup-gh: unsupported runner architecture ${RUNNER_ARCH:-$(uname -m)}"; exit 1 ;;
esac
case "${RUNNER_OS:-$(uname -s)}" in
  Linux) platform=linux ext=tar.gz ;;
  macOS | Darwin) platform=macOS ext=zip ;;
  *) echo "::error::setup-gh: unsupported runner OS ${RUNNER_OS:-$(uname -s)}"; exit 1 ;;
esac

name="gh_${version}_${platform}_${arch}"
cache="${RUNNER_TOOL_CACHE:-${RUNNER_TEMP:?}}/gh/${version}/${arch}"

if [[ ! -x "$cache/bin/gh" ]]; then
  base="https://github.com/cli/cli/releases/download/v${version}"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL --retry 3 -o "$tmp/${name}.${ext}" "$base/${name}.${ext}"
  curl -fsSL --retry 3 -o "$tmp/checksums.txt" "$base/gh_${version}_checksums.txt"
  expected=$(awk -v f="${name}.${ext}" '$2 == f { print $1 }' "$tmp/checksums.txt")
  if [[ -z "$expected" ]]; then
    echo "::error::setup-gh: ${name}.${ext} is not in the release's checksums.txt"
    exit 1
  fi
  if command -v sha256sum >/dev/null; then
    actual=$(sha256sum "$tmp/${name}.${ext}" | awk '{ print $1 }')
  else
    actual=$(shasum -a 256 "$tmp/${name}.${ext}" | awk '{ print $1 }')
  fi
  if [[ "$actual" != "$expected" ]]; then
    echo "::error::setup-gh: checksum mismatch for ${name}.${ext} (expected $expected, got $actual)"
    exit 1
  fi
  if [[ "$ext" == "zip" ]]; then
    unzip -q "$tmp/${name}.${ext}" -d "$tmp"
  else
    tar -xzf "$tmp/${name}.${ext}" -C "$tmp"
  fi
  mkdir -p "$cache"
  rm -rf "${cache:?}/bin"
  mv "$tmp/${name}/bin" "$cache/bin"
fi

echo "$cache/bin" >> "${GITHUB_PATH:?}"
"$cache/bin/gh" --version | head -n 1
