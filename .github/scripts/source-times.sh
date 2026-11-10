#!/bin/bash
# Lets Xcode reuse a restored DerivedData after a fresh checkout. Xcode rebuilds a file whose modification time is
# newer than its last build, and a checkout stamps every file with the time of the checkout. So every file, and
# every folder (asset catalogs are folders), gets the same old time, and only what changed since the build the cache
# was made from gets the current one.
#
#   source-times.sh <derived-data>   before the build: reads <derived-data>/source-sha, the commit it was built from
#   source-times.sh --record <derived-data>   after a green build: writes it
set -euo pipefail

if [ "${1:-}" = --record ]; then
  git rev-parse HEAD > "$2/source-sha"
  exit 0
fi

derived=$1
old=202601010000

git ls-files -z | xargs -0 touch -t "$old"
git ls-files -z | xargs -0 -n1 dirname | sort -u | tr '\n' '\0' | xargs -0 touch -t "$old"

if [ ! -f "$derived/source-sha" ]; then
  echo "No restored DerivedData: a clean build."
  rm -rf "$derived"
  exit 0
fi

built=$(cat "$derived/source-sha")
if ! git cat-file -e "$built^{commit}" 2>/dev/null && ! git fetch -q --depth=1 origin "$built"; then
  # Without the commit there is no telling what changed, and a stale object file would be tested as new code.
  echo "::warning::The cached build's commit $built is not reachable: a clean build."
  rm -rf "$derived"
  exit 0
fi

changed=$(git diff --name-only "$built" HEAD)
echo "DerivedData from $built; $(printf '%s' "$changed" | grep -c . || true) files changed since."
printf '%s\n' "$changed" | while IFS= read -r path; do
  [ -n "$path" ] || continue
  [ -e "$path" ] && touch "$path"
  dir=$(dirname "$path")
  while [ "$dir" != . ] && [ -d "$dir" ]; do
    touch "$dir"
    dir=$(dirname "$dir")
  done
done
