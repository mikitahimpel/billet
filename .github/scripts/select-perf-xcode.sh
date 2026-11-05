#!/bin/bash
# Selects the Xcode a perf run builds with: the one in .xcode-version when the runner has it (the
# xcode-27 image), otherwise the newest Xcode the runner has (Xcode 26 on macos-26, whose iOS 26
# Simulator draws the room without the GPU aborts the iOS 27 one has on CI).
set -euo pipefail
file=${1:?usage: select-perf-xcode.sh <.xcode-version>}
here=$(cd "$(dirname "$0")" && pwd)
version="$(tr -d '[:space:]' < "$file")"
if [ ! -d "/Applications/Xcode_${version}.app" ]; then
  newest=$(ls -d /Applications/Xcode_*.app | sed -E 's|.*/Xcode_(.*)\.app|\1|' \
    | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -V | tail -n 1)
  echo "Xcode $version is not on this runner; building with Xcode $newest"
  version=$newest
fi
echo "$version" > "$RUNNER_TEMP/perf-xcode-version"
"$here/select-xcode.sh" "$RUNNER_TEMP/perf-xcode-version"
