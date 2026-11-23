#!/bin/bash
# Builds the harness and plays its scenarios: tools/cat-motion/run.sh <label> [scenario ...]
# Movies, samples and reports land in ~/Library/Caches/cat-motion/<label>/.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cache="$HOME/Library/Caches/cat-motion"
build="$cache/build"
mkdir -p "$build"
swift build -c release --package-path "$here" --scratch-path "$build" 2>&1 | grep -v "^\[" || true
bin="$(swift build -c release --package-path "$here" --scratch-path "$build" --show-bin-path)"
# The app's own skinning shader and the harness's drawing one, where makeDefaultLibrary looks.
xcrun -sdk macosx metal -o "$bin/default.metallib" \
  "$here/../../apps/ios/Nooki/Scene/SkinSplats.metal" "$here/Shaders/Splat.metal"
"$bin/CatMotion" "$@"
