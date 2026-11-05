#!/bin/zsh
# Rebuilds the first-launch heart in Blender and compiles it into the .reality file the app loads.
# Needs macOS (realitytool) and Blender at /Applications/Blender.app.
set -e
here=${0:A:h}
blender=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
source=$here/../assets-source/heart/Heart.usdz
out=$here/../Sources/PetSceneReality/Resources/Heart.reality
$blender -b --python $here/make_heart.py -- "$@" 2>&1 | grep -E 'Error|Traceback|exported' || true
work=$(mktemp -d)
mkdir $work/Heart.rkassets
cp $source $work/Heart.rkassets/
xcrun realitytool compile --platform iphoneos --deployment-target 18.0 \
  --output-reality $out $work/Heart.rkassets 2>&1 | grep -E '^error' || true
rm -rf $work
print "Heart: $(stat -f %z $out) bytes"
