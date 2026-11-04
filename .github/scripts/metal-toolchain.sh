#!/bin/bash
# Installs Xcode's Metal Toolchain component when the selected Xcode lacks it; from Xcode 26 on it
# is a separate download, and the app's .metal shaders do not build without it.
set -euo pipefail
if xcrun metal -v > /dev/null 2>&1; then
  echo "Metal Toolchain already installed"
else
  xcodebuild -downloadComponent MetalToolchain
fi
xcrun metal -v 2>&1 | head -n 1
