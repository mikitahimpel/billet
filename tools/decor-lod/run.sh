#!/bin/bash
# Rebuilds apps/ios/Nooki/Resources/Decor from the shop's models. Needs Blender.
set -e
cd "$(dirname "$0")/../.."
for id in armchair bookcase donutbed lamp lantern monstera print rug teatable tower yarn mouse; do
  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/decor-lod/decimate.py -- \
    apps/ios/Nooki/Resources/Shop/Item_$id.usdz apps/ios/Nooki/Resources/Decor/Decor_$id.usdz --tris 5000 --parts 3 | grep DECOR
done
