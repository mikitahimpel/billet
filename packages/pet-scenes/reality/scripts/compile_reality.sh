#!/bin/zsh
# Compiles Room.usdz into the .reality file the app loads first. Run after bake_room.py.
# bake_cat.py does the same for the cat.
set -e
resources=${0:A:h}/../Sources/PetSceneReality/Resources
work=$(mktemp -d)
mkdir $work/Room.rkassets
cp $resources/Room.usdz $work/Room.rkassets/
xcrun realitytool compile --platform iphoneos --deployment-target 18.0 \
  --output-reality $resources/Room.reality $work/Room.rkassets 2>&1 | grep -E '^error' || true
rm -rf $work
