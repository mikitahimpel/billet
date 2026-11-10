#!/bin/zsh
# Renders Nooki/Resources/Coats/Coat-<coat>.png, the onboarding carousel cards, with Tools/make_coat_card.py (grey
# from Cat.usdz as is, others from a copy with that coat's atlas). Needs Blender (BLENDER=path); WIDTH and SAMPLES
# override 900 px and 512 samples. 1200 px tall is the 340 pt hero at 3x; more only slows the splash's first frame.
set -e
IOS=${0:a:h:h:h}
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
coats=($@)
(( $# )) || coats=(grey ginger cream tuxedo black calico)
for coat in $coats; do
  work=$(mktemp -d)
  mkdir -p $work/Tools $work/Nooki/Resources
  cp $IOS/Tools/make_coat_card.py $work/Tools/
  if [[ $coat == grey ]]; then
    cp $IOS/Nooki/Resources/Cat.usdz $work/Nooki/Resources/
  else
    python3 $IOS/scripts/coats/coat-usdz.py $IOS/Nooki/Resources/Cat.usdz \
      $IOS/Nooki/Resources/Coats/CatColor-$coat.jpg $work/Nooki/Resources/Cat.usdz
  fi
  $BLENDER -b --python $work/Tools/make_coat_card.py -- $IOS/Nooki/Resources/Coats/Coat-$coat.png \
    ${WIDTH:-900} ${SAMPLES:-512} >/dev/null
  rm -rf $work
  echo "Coat-$coat.png"
done
