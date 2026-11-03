#!/bin/bash
# Builds the app in <checkout> for the Simulator, Release and unsigned, into <derived data>: what
# apps/ios/scripts/perf/measure.sh and shots.sh install and measure.
set -euo pipefail
checkout=${1:?usage: build-perf.sh <checkout> <derived data>}
derived=${2:?usage: build-perf.sh <checkout> <derived data>}
cd "$checkout/apps/ios"
xcodegen generate -q
xcodebuild build -project Billet.xcodeproj -scheme Billet -configuration Release \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived" \
  CODE_SIGNING_ALLOWED=NO -quiet
test -d "$derived/Build/Products/Release-iphonesimulator/Billet.app"
