#!/usr/bin/env bash
# Publish a new release: ./release.sh 0.2.0   (or 0.3.0-beta1 for a beta)
#
# Sets "## Version:" in the TOC, commits, tags v<version> and pushes. The push
# of the tag starts .github/workflows/release.yml, which builds the zip and
# release.json and publishes the GitHub release (a version with a "-" in it is
# published as a prerelease: the Beta channel in SHART and WowUp).
set -euo pipefail
cd "$(dirname "$0")"

addon=$(basename "$(ls ./*.toc | head -1)" .toc)
version=${1:-}
if [[ -z $version ]]; then
    current=$(sed -n 's/^## Version: *//p' "$addon.toc" | tr -d '\r')
    echo "usage: $0 <version>   (current: ${current:-none})" >&2
    exit 1
fi
version=${version#v}
if [[ ! $version =~ ^[0-9]+(\.[0-9]+)*(-[0-9A-Za-z.]+)?$ ]]; then
    echo "$version is not a version like 1.2.0 or 1.3.0-beta1" >&2
    exit 1
fi
tag="v$version"

branch=$(git rev-parse --abbrev-ref HEAD)
[[ $branch == master ]] || { echo "Releases are made from master (on $branch)" >&2; exit 1; }
[[ -z $(git status --porcelain) ]] || { echo "Commit or stash your changes first:" >&2; git status --short >&2; exit 1; }
git fetch --quiet --tags origin
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && { echo "$tag already exists" >&2; exit 1; }
if [[ $(git rev-list --count HEAD..origin/master 2>/dev/null || echo 0) != 0 ]]; then
    echo "origin/master has commits you don't: pull first" >&2
    exit 1
fi

sed -i "s/^## Version:.*/## Version: $version/" ./*.toc
if [[ -n $(git status --porcelain) ]]; then
    git commit --quiet -am "Release $tag"
fi
git tag -a "$tag" -m "$addon $tag"
git push --quiet origin master "$tag"

repo=$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')
echo "Pushed $tag. GitHub Actions is building the release:"
echo "  https://github.com/$repo/actions"
echo "  https://github.com/$repo/releases/tag/$tag"
