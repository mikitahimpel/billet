#!/bin/bash
# The pre-merge check for a pull request that changes UI: the design rules against main (the
# baseline and allow-list may only shrink), their fixture tests, and swift-format.
#
#   scripts/check-ui.sh
#
# Exit: 0 clean, 1 a check failed.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

git fetch -q origin main
base=$(git merge-base HEAD origin/main)
status=0
step() {
  echo "== $1"
  shift
  "$@" || status=1
}

step "design rules" node packages/ios/scripts/check-design.mjs --base "$base"
step "design rule fixtures" node --test packages/ios/scripts/design-rules.test.mjs
for package in packages/ios/*/Package.swift; do
  dir=$(dirname "$package")
  step "swift-format $dir" swift format lint --strict --recursive --configuration .swift-format \
    "$dir/Package.swift" "$dir/Sources" $([[ -d $dir/Tests ]] && echo "$dir/Tests")
done

exit $status
