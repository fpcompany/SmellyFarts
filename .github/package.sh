#!/usr/bin/env bash
# Build dist/<Addon>-<tag>.zip, dist/release.json (the BigWigs packager's
# format, which SHART and WowUp read to pick the file per game flavor) and
# dist/notes.md for a tag. Run by .github/workflows/release.yml; works
# locally too: .github/package.sh v0.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

tag=${1:?usage: $0 <tag>}
addon=$(basename "$(ls ./*.toc | head -1)" .toc)
zip="$addon-$tag.zip"
rm -rf dist && mkdir -p dist/stage

# Files marked export-ignore in .gitattributes stay out of the zip.
git archive --format=tar --prefix="$addon/" "$tag" | tar -x -C dist/stage
(cd dist/stage && zip -qr -X "../$zip" "$addon")
rm -rf dist/stage

# One file serves every client the TOC lists.
flavor() {
    local i=$1
    if ((i >= 100000)); then echo mainline
    elif ((i >= 16000 && i < 20000)); then echo forever
    elif ((i < 20000)); then echo classic
    elif ((i < 30000)); then echo bcc
    elif ((i < 40000)); then echo wrath
    elif ((i < 50000)); then echo cata
    else echo mists
    fi
}
metadata=""
for i in $(sed -n 's/^## Interface: *//p' "$addon.toc" | tr -d '\r' | tr ',' ' '); do
    metadata+="${metadata:+,}{\"flavor\":\"$(flavor "$i")\",\"interface\":$i}"
done
cat > dist/release.json <<JSON
{"releases":[{"name":"$addon","version":"$tag","filename":"$zip","nolib":false,"metadata":[$metadata]}]}
JSON

# Release notes: the commits since the previous tag.
previous=$(git describe --tags --abbrev=0 "$tag^" 2>/dev/null || true)
{
    echo "## Changes"
    echo
    git log --no-merges --pretty='- %s' ${previous:+"$previous.."}"$tag" | grep -v '^- Release v' || echo "- First release"
} > dist/notes.md

echo "dist/$zip"
cat dist/release.json
