#!/bin/zsh
# Renders Shared/Resources/MochiPortrait-<coat>.png, the round avatar in each coat, with Ilya's own
# Tools/make_portrait.py, run unchanged on a copy of Cat.usdz that holds the coat's colour atlas instead of his.
# Grey is his MochiPortrait.png and is not rendered. Needs Blender (BLENDER=/path/to/blender to override).
set -e
IOS=${0:a:h:h:h}
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
for coat in ${@:-ginger cream tuxedo black calico}; do
  work=$(mktemp -d)
  mkdir -p $work/Tools $work/Nooki/Resources
  cp $IOS/Tools/make_portrait.py $work/Tools/
  python3 $IOS/scripts/coats/coat-usdz.py $IOS/Nooki/Resources/Cat.usdz \
    $IOS/Nooki/Resources/Coats/CatColor-$coat.jpg $work/Nooki/Resources/Cat.usdz
  $BLENDER -b --python $work/Tools/make_portrait.py -- $IOS/Shared/Resources/MochiPortrait-$coat.png 512 >/dev/null
  rm -rf $work
  echo "MochiPortrait-$coat.png"
done
