#!/bin/zsh
# Compiles Cat.usdz and Room.usdz into the .reality files the app loads first. Run after bake_room.py.
set -e
resources=${0:A:h}/../Sources/PetSceneReality/Resources
work=$(mktemp -d)
for name in Cat Room; do
  mkdir $work/$name.rkassets
  cp $resources/$name.usdz $work/$name.rkassets/
  xcrun realitytool compile --platform iphoneos --deployment-target 18.0 \
    --output-reality $resources/$name.reality $work/$name.rkassets 2>&1 | grep -E '^error' || true
done
rm -rf $work
