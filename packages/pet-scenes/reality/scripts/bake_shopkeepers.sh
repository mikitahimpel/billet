#!/bin/zsh
# Rebuilds the shopkeepers in Blender and compiles each into the .reality file the shop loads.
# Needs macOS (realitytool) and Blender at /Applications/Blender.app.
set -e
here=${0:A:h}
blender=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
sources=$here/../assets-source/shopkeepers
out=$here/../Sources/PetSceneReality/Resources/Shopkeepers
$blender -b --python $here/make_shopkeepers.py -- "$@" 2>&1 | grep -E 'Error|Traceback|exported' || true
mkdir -p $out
for usdz in $sources/Keeper_*.usdz; do
  name=${usdz:t:r}
  work=$(mktemp -d)
  mkdir $work/$name.rkassets
  cp $usdz $work/$name.rkassets/
  xcrun realitytool compile --platform iphoneos --deployment-target 18.0 \
    --output-reality $out/$name.reality $work/$name.rkassets 2>&1 | grep -E '^error' || true
  rm -rf $work
  print "$name: $(stat -f %z $out/$name.reality) bytes"
done
