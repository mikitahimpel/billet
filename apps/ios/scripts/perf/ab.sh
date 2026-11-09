#!/bin/zsh
# Runs two Release builds in turns under the measuring lock, then writes <out>/<new-label>/ab.md.
#   apps/ios/scripts/perf/ab.sh <base-label> <base-derived> <new-label> <new-derived> [rounds]
# Derived = a Release Simulator build (measure.sh --build-only). PERF_AB_ARGS, PERF_{BASE,NEW}_APP_ARGS add run args.
set -euo pipefail

base=${1:?usage: ab.sh <base-label> <base-derived> <new-label> <new-derived> [rounds]}
base_derived=${2:?}
new=${3:?}
new_derived=${4:?}
rounds=${5:-3}
here=${0:A:h}
out=${PERF_OUT:-$HOME/.billet-manager/pet-concept/perf/runs}
args=(${=PERF_AB_ARGS:---launches 2 --full 1})

source $here/lock.sh
perf_lock_take "ab $base vs $new"
trap 'perf_lock_give' EXIT

# Each round's output is kept beside its runs, so a failed round says why.
mkdir -p $out/$base $out/$new
for ((round = 1; round <= rounds; round++)); do
  PERF_APP_ARGS=${PERF_BASE_APP_ARGS:-} PERF_DERIVED=$base_derived $here/measure.sh $base $args > $out/$base/round-$round.log 2>&1 \
    || echo "base round $round failed: $out/$base/round-$round.log" >&2
  PERF_APP_ARGS=${PERF_NEW_APP_ARGS:-} PERF_DERIVED=$new_derived $here/measure.sh $new $args > $out/$new/round-$round.log 2>&1 \
    || echo "new round $round failed: $out/$new/round-$round.log" >&2
done
python3 -I $here/report.py $out/$base $out/$new > $out/$new/ab.md
echo "wrote $out/$new/ab.md"
