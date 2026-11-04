#!/bin/bash
# Ilya's cat (splats, skin, rig, meshes, and the code that moves them) stays exactly as he made it.
# apps/ios/nooki-cat.sha256 holds each file's SHA-256 from nexishq/nooki-ios; a change to one of
# them fails here until the manifest is updated in the same pull request, on purpose:
#   (cd apps/ios && shasum -a 256 <file>)   # the new line for the manifest
set -euo pipefail
cd "$(dirname "$0")/../../apps/ios"
shasum -a 256 --check --strict nooki-cat.sha256
