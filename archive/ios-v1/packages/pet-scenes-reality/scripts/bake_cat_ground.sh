#!/bin/zsh
# Measures how high every shipped cat's clips hold its lowest point (measure_cat_ground.py) and
# writes Resources/Cats/Cat_<model>.ground.json beside each clip table. Pass model names to
# measure only those. Needs Blender at /Applications/Blender.app.
set -eu
cd "${0:A:h}/.."
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
CATS=Sources/PetSceneReality/Resources/Cats
models=("$@")
if (( ${#models} == 0 )); then
  models=(${${(f)"$(ls $CATS/*.reality)"}:t:r})
  models=(${models#Cat_})
fi
for model in $models; do
  length=0.2998
  [[ $model == hero ]] && length=0.3192
  (
    $BLENDER -b -P scripts/measure_cat_ground.py -- assets-source/cats/$model/Cat.usdz \
      assets-source/cats/$model/clips.json $length $CATS/Cat_$model.ground.json >/dev/null 2>&1 \
      && echo "measured $model" || echo "FAILED $model"
  ) &
  while (( $(jobs -r | wc -l) >= 3 )); do sleep 1; done
done
wait
