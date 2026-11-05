#!/bin/zsh
# Renders Nooki/Resources/Coats/Coat-<coat>.png, the onboarding carousel cards, with Tools/make_coat_card.py.
# Grey renders Cat.usdz as it is; every other coat a copy holding that coat's colour atlas. Needs Blender
# (BLENDER=/path/to/blender to override); WIDTH and SAMPLES override the 1200 px width and 512 samples.
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
    ${WIDTH:-1200} ${SAMPLES:-512} >/dev/null
  rm -rf $work
  echo "Coat-$coat.png"
done
