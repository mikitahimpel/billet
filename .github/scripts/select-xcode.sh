#!/bin/bash
# Selects the Xcode named in the given .xcode-version on a GitHub Mac runner.
set -euo pipefail
version="$(tr -d '[:space:]' < "${1:?usage: select-xcode.sh <.xcode-version>}")"
app="/Applications/Xcode_${version}.app"
if [ ! -d "$app" ]; then
  echo "::error::$app is not installed on this runner (.xcode-version is $version)"
  ls -d /Applications/Xcode_*.app
  exit 1
fi
sudo xcode-select -s "$app"
# Captured, not piped: `head` closing the pipe early makes xcodebuild abort on the broken pipe.
selected="$(xcodebuild -version)"
echo "$selected"
[ "$(sed -n 1p <<< "$selected")" = "Xcode ${version}" ]
