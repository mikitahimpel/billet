#!/usr/bin/env bash
# The props mesh build on the PC (CPU), each step under billet-gpu's lock so it never overlaps
# FLUX, Idol or its Blender jobs: splat -> dense coloured mesh -> remesh + flat base + bake
# (Blender, 4 threads) -> pack (atlas pages + one USDZ). The Mac compiles the .reality after.
# usage: ./build_pc.sh name...   (splats: ../out/props*/props-<name>.ply)
set -euo pipefail
cd ~/billet-gpu/props-build
BL=~/billet-gpu/blender-app/blender-billet
LOCK=~/billet-gpu/.klein.lock
spec() { .venv/bin/python -c "import json; s=json.load(open('specs.json'))['$1']; print(s['tris'], s['fit'], s['size'], s.get('yaw', 0), s['mount'])"; }
for n in "$@"; do
  src=$(ls ../out/props*/props-$n.ply 2>/dev/null | head -1 || true)
  [ -n "$src" ] || { echo "SKIP $n (no splat)"; continue; }
  read -r tris fit size yaw mount < <(spec $n)
  [ -f dense/$n/$n.glb ] || flock $LOCK .venv/bin/python -I scripts/dense_mesh.py "$src" dense/$n $n > /dev/null
  flock $LOCK $BL -b --factory-startup -t 4 --python-exit-code 1 -P scripts/remesh_prop.py -- dense/$n/$n.glb \
    remeshed $n $tris $fit $size $yaw 512 0 $mount 2>&1 | grep -E "REMESHED|Error" || echo "FAIL $n"
done
