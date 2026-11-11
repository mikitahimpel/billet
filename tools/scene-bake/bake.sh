#!/bin/zsh
#   tools/scene-bake/bake.sh [--samples N] [--width N]
# Renders the City window diorama on the pc (Blender, Cycles on the GPU, all three times under one hold of ~/billet-gpu/.klein.lock), pulls the PNGs
# and writes WebP layers plus diorama.json into apps/ios/Nooki/Resources/CityDiorama. Needs `ssh pc` and `cwebp`.
set -euo pipefail
here=${0:A:h}
repo=${here:h:h}
dest=$repo/apps/ios/Nooki/Resources/CityDiorama
work=$here/.work
samples=128 width=1280
while (( $# )); do
  case $1 in
    --samples) samples=$2; shift ;;
    --width) width=$2; shift ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done
mkdir -p $work $dest
ssh pc 'mkdir -p ~/billet-gpu/scene-bake/out'
scp -q $here/city_diorama.py pc:billet-gpu/scene-bake/
ssh pc "cd ~/billet-gpu/scene-bake && rm -rf out/day out/dusk out/night && flock ~/billet-gpu/.klein.lock bash -c 'for t in day dusk night; do ~/billet-gpu/blender-app/blender-billet -b --python-exit-code 1 -P city_diorama.py -- out/\$t \$t --samples $samples --width $width > out/\$t.log 2>&1 < /dev/null || exit 1; done'"
for t in day dusk night; do
  mkdir -p $work/$t
  scp -q "pc:billet-gpu/scene-bake/out/$t/*" $work/$t/
  for png in $work/$t/*.png; do
    name=${png:t:r}
    cwebp -quiet -q 82 -alpha_q 92 -m 6 $png -o $dest/$name.webp
  done
done
python3 -I $here/manifest.py $work/day/info.json $dest/diorama.json $width
du -ch $dest/* | tail -1
