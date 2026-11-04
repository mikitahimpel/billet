#!/bin/zsh
# Builds the 3D night street for Window Seat's window into Resources/StreetView: models and bakes
# it in Blender (4 threads), paints its far cards, and renders a check from the home camera.
#   scripts/build_street_view.sh [samples]     (default 64; 8 is enough for a layout check)
set -eu
here=${0:A:h}
blender=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
work=$(mktemp -d)
$blender -b --factory-startup -t 4 -P $here/make_street_view.py -- $work ${1:-64} 2>&1 | grep -E '^STREET|Error'
python3 $here/paint_street_cards.py $work
$blender -b --factory-startup -t 4 -P $here/preview_street_view.py -- $work $work/preview.png > /dev/null 2>&1
res=$here/../Sources/PetSceneReality/Resources/StreetView
mkdir -p $res
cp $work/street.bin $work/street-atlas.png $work/street-cards.png $res/
echo "preview: $work/preview.png"
