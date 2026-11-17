#!/usr/bin/env bash
# Publish a new release of the version in the TOC's "## Version:" line:
#
#   ./release.sh          release the TOC's version as it is
#   ./release.sh 0.2.0    set "## Version:" to 0.2.0 (and commit), then release
#
# Tags v<version> and pushes. The push of the tag starts
# .github/workflows/release.yml, which builds the zip and release.json and
# publishes the GitHub release (a version with a "-" in it, like 0.3.0-beta1,
# is published as a prerelease: the Beta channel in SHART and WowUp).
set -euo pipefail
cd "$(dirname "$0")"

addon=$(basename "$(ls ./*.toc | head -1)" .toc)
toc_version=$(sed -n 's/^## Version: *//p' "$addon.toc" | head -1 | tr -d '\r' | xargs)
version=${1:-$toc_version}
version=${version#v}
if [[ -z $version ]]; then
    echo "$addon.toc has no \"## Version:\" line: add one or run $0 <version>" >&2
    exit 1
fi
if [[ ! $version =~ ^[0-9]+(\.[0-9]+)*(-[0-9A-Za-z.]+)?$ ]]; then
    echo "$version is not a version like 1.2.0 or 1.3.0-beta1" >&2
    exit 1
fi
tag="v$version"

branch=$(git rev-parse --abbrev-ref HEAD)
[[ $branch == master ]] || { echo "Releases are made from master (on $branch)" >&2; exit 1; }
[[ -z $(git status --porcelain) ]] || { echo "Commit or stash your changes first:" >&2; git status --short >&2; exit 1; }
git fetch --quiet --tags origin
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "$tag is already released: raise \"## Version:\" in $addon.toc (or run $0 <new version>)" >&2
    exit 1
fi
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
