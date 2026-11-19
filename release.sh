#!/usr/bin/env bash
# release.sh tags a new release of these actions, moves the v<major> tag to it
# and pushes both, which starts the Release notes workflow
# (.github/workflows/release-notes.yml).
#
# Usage:
#   ./release.sh patch|minor|major   bump the latest release, e.g. v4.2.0 -> v4.3.0
#   ./release.sh v1.2.3              release an exact version
#   ./release.sh -n ...              dry run: check everything, but tag and push nothing
#
# It switches to main and fast-forwards it to origin/main, so you can run it
# from any branch with a clean working tree. Before tagging, it checks that the
# version is new and higher than every earlier one and that CI passed on the
# commit. A breaking change to an input needs major. See README.md, "Releasing".

set -euo pipefail

remote=origin
branch=main

die() {
	printf 'release.sh: %s\n' "$*" >&2
	exit 1
}

usage() {
	sed -n '6,9s/^# \{0,1\}//p' "$0" >&2
	exit 2
}

# semver_re matches a release tag like v1.2.3, capturing major, minor and
# patch. No prereleases: release-notes.yml only runs for vX.Y.Z tags.
semver_re='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

# version_gt reports whether tag $1 is a higher version than tag $2.
version_gt() {
	[[ $1 =~ $semver_re ]] || return 1
	local a=("${BASH_REMATCH[@]:1:3}")
	[[ $2 =~ $semver_re ]] || return 1
	local b=("${BASH_REMATCH[@]:1:3}")
	local i
	for i in 0 1 2; do
		((a[i] > b[i])) && return 0
		((a[i] < b[i])) && return 1
	done
	return 1
}

# check_ci fails unless every check run on commit $1 finished as success,
# skipped or neutral. The lint tools are rarely installed locally, so CI on
# main is the check that counts.
check_ci() {
	local runs
	runs=$(gh api --paginate "repos/{owner}/{repo}/commits/$1/check-runs" \
		--jq '.check_runs[] | "\(.status) \(.conclusion // "-") \(.name)"') ||
		die "cannot read the CI checks of $1 with gh; run gh auth login"
	[[ -n $runs ]] || die "no CI checks have run on $1 yet; wait for them and run this again"
	local bad
	bad=$(grep -Ev '^completed (success|skipped|neutral) ' <<<"$runs" || true)
	[[ -z $bad ]] || die "CI has not passed on $1:
$bad"
	echo "CI passed: $(wc -l <<<"$runs" | tr -d ' ') checks"
}

# main does the release. The whole script is in functions, so bash has read all
# of it before main runs: switching branches may change this file underneath it.
main() {
	dry_run=false
	if [[ ${1-} == -n || ${1-} == --dry-run ]]; then
		dry_run=true
		shift
	fi
	[[ $# -eq 1 ]] || usage
	arg=$1

	cd "$(dirname "$0")"
	command -v gh >/dev/null || die "gh is not installed; it reads the CI checks"

	[[ -z $(git status --porcelain) ]] ||
		die "the working tree has uncommitted changes; commit or stash them first"

	# Release exactly what is on GitHub, not a stale clone. --force updates
	# the local v<major> tag, which every release moves.
	git fetch --quiet --tags --force "$remote" "$branch" ||
		die "cannot fetch from $remote; check your network and credentials"

	current=$(git symbolic-ref --quiet --short HEAD || true)
	if [[ $current != "$branch" ]]; then
		echo "==> Switching from ${current:-a detached HEAD} to $branch"
		if git rev-parse --quiet --verify "refs/heads/$branch" >/dev/null; then
			git switch --quiet "$branch"
		else
			git switch --quiet --track -c "$branch" "$remote/$branch"
		fi
	fi
	if [[ $(git rev-parse HEAD) != "$(git rev-parse "$remote/$branch")" ]]; then
		git merge --quiet --ff-only "$remote/$branch" ||
			die "$branch has commits that are not on $remote/$branch; push them through a pull request, or reset $branch to $remote/$branch"
		echo "==> Updated $branch to $(git log -1 --format='%h %s')"
	fi

	latest=""
	while IFS= read -r t; do
		if [[ $t =~ $semver_re ]] && { [[ -z $latest ]] || version_gt "$t" "$latest"; }; then
			latest=$t
		fi
	done < <(git tag --list 'v*')

	case $arg in
	patch | minor | major)
		[[ $latest =~ $semver_re ]] || die "no earlier release to bump; give an exact version such as v1.0.0"
		major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}
		case $arg in
		patch) version="v$major.$minor.$((patch + 1))" ;;
		minor) version="v$major.$((minor + 1)).0" ;;
		major) version="v$((major + 1)).0.0" ;;
		esac
		;;
	*)
		version=$arg
		[[ $version == v* ]] || version="v$version"
		[[ $version =~ $semver_re ]] ||
			die "$arg is not a version like v1.2.3, or one of patch, minor, major"
		;;
	esac
	[[ $version =~ $semver_re ]]
	floating="v${BASH_REMATCH[1]}"

	if git rev-parse --quiet --verify "refs/tags/$version" >/dev/null ||
		[[ -n $(git ls-remote --tags "$remote" "refs/tags/$version") ]]; then
		die "$version already exists; pick another version"
	fi
	if [[ -n $latest ]] && ! version_gt "$version" "$latest"; then
		die "$version is not higher than the latest release, $latest; pick a higher version"
	fi
	released=$(git tag --points-at HEAD --list 'v*.*.*')
	if [[ -n $released ]]; then
		die "HEAD is already released as $(tr '\n' ' ' <<<"$released")- there is nothing new to release"
	fi

	# The floating tag's current commit on the remote, for --force-with-lease:
	# the push fails if someone moved it since, instead of overwriting that.
	floating_old=$(git ls-remote --tags "$remote" "refs/tags/$floating" | cut -f1)

	echo "==> Checks"
	check_ci "$(git rev-parse HEAD)"

	echo
	echo "Latest release: ${latest:-none}"
	echo "New release:    $version"
	if [[ -n $floating_old ]]; then
		echo "Moves:          $floating, from $(git rev-parse --short "$floating^{commit}" 2>/dev/null || echo "${floating_old:0:7}")"
	else
		echo "Creates:        $floating (new major version)"
	fi
	echo "Commit:         $(git log -1 --format='%h %s')"
	if [[ -n $latest ]]; then
		echo
		echo "Commits since $latest:"
		git log --format='  %h %s' "$latest..HEAD"
	fi
	echo

	if $dry_run; then
		echo "Dry run: not tagging. Run without -n to release $version."
		exit 0
	fi

	read -r -p "Tag $version, point $floating at it and push both to $remote? [y/N] " answer
	[[ $answer == [yY] || $answer == [yY][eE][sS] ]] || die "cancelled; nothing was tagged"

	local_floating_old=$(git rev-parse --quiet --verify "refs/tags/$floating" || true)
	git tag -a "$version" -m "$version"
	git tag -fa "$floating" -m "$floating" >/dev/null
	# Atomic, so the remote never has the new version without the moved tag.
	if ! git push --atomic --force-with-lease="refs/tags/$floating:$floating_old" \
		"$remote" "refs/tags/$version" "refs/tags/$floating"; then
		git tag -d "$version" >/dev/null
		if [[ -n $local_floating_old ]]; then
			git update-ref "refs/tags/$floating" "$local_floating_old"
		else
			git tag -d "$floating" >/dev/null
		fi
		die "pushing $version and $floating failed; the local tags were restored, so you can run this again"
	fi

	url=$(git remote get-url "$remote" | sed -E 's#^git@github.com:#https://github.com/#; s#\.git$##')
	echo
	echo "Pushed $version and $([[ -n $floating_old ]] && echo moved || echo created) $floating. Follow the Release notes workflow at $url/actions/workflows/release-notes.yml"
}

main "$@"
