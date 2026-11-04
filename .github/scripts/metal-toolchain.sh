#!/bin/bash
# Installs Xcode's Metal Toolchain component when the selected Xcode lacks it; from Xcode 26 on it
# is a separate download, and the app's .metal shaders do not build without it. The download or
# its install can fail on a runner, so it is tried up to three times, and the step passes only
# when the compiler answers afterwards.
set -uo pipefail

works() { xcrun metal --version > /dev/null 2>&1; }

if works; then
  echo "Metal Toolchain already installed"
else
  for attempt in 1 2 3; do
    echo "Downloading the Metal Toolchain, attempt $attempt of 3"
    xcodebuild -downloadComponent MetalToolchain 2>&1 | grep -v '^Downloading\.\.\.' || true
    works && break
    [ "$attempt" = 3 ] || sleep $((attempt * 15))
  done
fi

if ! works; then
  echo "::error::the Metal Toolchain is not installed after 3 attempts"
  xcrun metal --version || true
  exit 1
fi
version=$(xcrun metal --version 2>&1)
echo "${version%%$'\n'*}"
