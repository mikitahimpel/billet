#!/bin/zsh
# Renders Shared/Resources/MochiPortrait-<coat>.png with Tools/make_portrait.py on a copy of CatStanding.usdz holding
# the coat's colour atlas. Grey is the existing MochiPortrait.png, not rendered. Needs Blender (BLENDER=path).
set -e
IOS=${0:a:h:h:h}
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
for coat in ${@:-ginger cream tuxedo black calico}; do
  work=$(mktemp -d)
  mkdir -p $work/Tools $work/Nooki/Resources
  cp $IOS/Tools/make_portrait.py $IOS/Tools/sit_mesh.py $IOS/Tools/cat_pose.py $work/Tools/
  cp $IOS/Nooki/Resources/MochiStanding.rig.json $work/Nooki/Resources/
  python3 $IOS/scripts/coats/coat-usdz.py $IOS/Nooki/Resources/CatStanding.usdz \
    $IOS/Nooki/Resources/Coats/CatStandingColor-$coat.jpg $work/Nooki/Resources/CatStanding.usdz
  $BLENDER -b --python $work/Tools/make_portrait.py -- $IOS/Shared/Resources/MochiPortrait-$coat.png 512 >/dev/null
  rm -rf $work
  echo "MochiPortrait-$coat.png"
done
