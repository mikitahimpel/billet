#!/bin/bash
# Installs a pinned XcodeGen release, verified by checksum, and puts it on the job's PATH.
set -euo pipefail
version=2.46.0
sha256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
curl -fsSL -o "$RUNNER_TEMP/xcodegen.zip" \
  "https://github.com/yonaskolb/XcodeGen/releases/download/${version}/xcodegen.zip"
echo "${sha256}  $RUNNER_TEMP/xcodegen.zip" | shasum -a 256 -c -
unzip -q -o "$RUNNER_TEMP/xcodegen.zip" -d "$RUNNER_TEMP"
echo "$RUNNER_TEMP/xcodegen/bin" >> "$GITHUB_PATH"
