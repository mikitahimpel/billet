#!/bin/zsh
#   scripts/bake-room/bake.sh [room|city ...] [--skip-export] [--samples N] [--size N]
# BakedShellTests.export writes the shapes, Blender bakes them; sources.json records what each shell
# was baked from, and BakedShellTests fails when a room's static boxes no longer match it.
set -euo pipefail

here=${0:A:h}
repo=${here:h:h}
work=$here/.work
lock=$HOME/.billet-manager/build.lock
blender=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
device=${BAKE_DEVICE:-iPhone 17e}
rooms=() skip_export=0 samples=128 size=2048
while (( $# )); do
  case $1 in
    room|city) rooms+=$1 ;;
    --skip-export) skip_export=1 ;;
    --samples) samples=$2; shift ;;
    --size) size=$2; shift ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done
(( ${#rooms} )) || rooms=(room city)
mkdir -p $work

take_lock() { until shlock -f $lock -p $$; do sleep 15; done; }
give_lock() { [[ -f $lock && $(<$lock) == $$ ]] && rm -f $lock; return 0; }
trap give_lock EXIT

typeset -A names=(room Room_shell city City_shell)

if (( ! skip_export )); then
  take_lock
  (cd $repo/apps/ios && xcodegen generate -q)
  udid=$(xcrun simctl list devices available -j | python3 -I -c '
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d["name"] == name and d["udid"] != "B5E1E03F-B285-4DE0-930C-0021093A917D":
            print(d["udid"]); raise SystemExit
' $device)
  [[ -n $udid ]] || { echo "no Simulator named $device" >&2; exit 1; }
  TEST_RUNNER_BAKE_EXPORT_DIR=$work xcodebuild test -project $repo/apps/ios/Billet.xcodeproj -scheme Billet \
    -destination "platform=iOS Simulator,id=$udid" -only-testing:OurioTests/BakedShellTests/export\(\) \
    -derivedDataPath $work/derived CODE_SIGNING_ALLOWED=NO -quiet
  give_lock
  cp $work/*.json $here/shells/ && for f in $here/shells/*.json; do mv $f ${f%.json}.shapes; done
fi

for room in $rooms; do
  name=$names[$room]
  [[ -f $here/shells/$name.shapes ]] || { echo "shells/$name.shapes is missing: run without --skip-export" >&2; exit 1; }
  extra=()
  [[ $room == room ]] && extra=(--furniture $here/Room_furniture.usdz)
  take_lock
  perl -e 'alarm 600; exec @ARGV' $blender -b -P $here/bake_shell.py -- $room $here/shells/$name.shapes $work/$name.usdz \
    --size $size --samples $samples ${=BAKE_ARGS:-} $extra
  give_lock
  cp $work/$name.usdz $repo/apps/ios/Nooki/Resources/Room/$name.usdz
  bytes=$(stat -f %z $work/$name.usdz)
  printf '%s: %.2f MB\n' $name $((bytes / 1e6))
  (( bytes < 8000000 )) || { echo "$name is over the 8 MB budget" >&2; exit 1; }
done

python3 -I - $here/sources.json $work <<'PY'
import json, os, sys
path, work = sys.argv[1:3]
sources = json.load(open(path)) if os.path.exists(path) else {}
for name in ("Room_shell", "City_shell"):
    sha = os.path.join(work, name + ".sha")
    if os.path.exists(sha):
        sources[name] = open(sha).read().strip()
json.dump(sources, open(path, "w"), indent=2, sort_keys=True)
open(path, "a").write("\n")
PY
echo "baked: $rooms"
