#!/bin/zsh
# The standard screenshot set from one Release Simulator build: World in each room and pose, with Shop and Moments
# over it (measure.sh --sweep), then first-launch onboarding on a fresh install, into $PERF_OUT/<label>/shots.
#   PERF_DERIVED=<derived> [PERF_DEVICE=<name>] [PERF_DEVICE_TYPE=<type id>] shots.sh <label>
set -euo pipefail

label=${1:?usage: shots.sh <label>}
here=${0:A:h}
repo=${here:h:h:h:h}
derived=${PERF_DERIVED:-$repo/build-perf}
out=${PERF_OUT:-$HOME/.billet-manager/pet-concept/perf/runs}/$label
device_name=${PERF_DEVICE:-billet-perf}
bundle=com.ourio.app
app=$derived/Build/Products/Release-iphonesimulator/Billet.app
[[ -d $app ]] || { echo "no app at $app" >&2; exit 1; }

source $here/lock.sh
perf_lock_take "shots $label"
trap 'perf_lock_give' EXIT

# Each room, its poses and the tabs. measure.sh makes the device if it is missing and signs the
# app, which the fresh install below then reuses.
for room in room city; do
  PERF_ROOM=$room PERF_DERIVED=$derived $here/measure.sh $label --launches 0 --full 0 --sweep
done

udid=$(xcrun simctl list devices | awk -v n="$device_name" -F '[()]' '$0 ~ "^ +"n" \\(" {print $2; exit}')
[[ -n $udid ]] || { echo "no device $device_name" >&2; exit 1; }
trap 'xcrun simctl shutdown $udid >/dev/null 2>&1 || true; perf_lock_give' EXIT
# Erased, so nothing from the runs is left: the app opens on its first-launch onboarding.
xcrun simctl shutdown $udid > /dev/null 2>&1 || true
xcrun simctl erase $udid
xcrun simctl bootstatus $udid -b > /dev/null
xcrun simctl status_bar $udid override --time 9:41 --batteryState charged --batteryLevel 100 \
  > /dev/null 2>&1 || true
xcrun simctl install $udid $app

mkdir -p $out/shots
xcrun simctl launch $udid $bundle > /dev/null
started=$(date +%s)
# Named by when each was asked for; on a busy runner a shot can land a little later.
for at in 2 5 9 14 20; do
  while (($(date +%s) - started < at)); do python3 -c 'import time; time.sleep(0.2)'; done
  for try in 1 2; do
    perl -e 'alarm 40; exec @ARGV' xcrun simctl io $udid screenshot \
      $out/shots/onboarding-${at}s.png > /dev/null 2>&1 && break
  done || echo "no onboarding shot at ${at}s" >&2
done
xcrun simctl terminate $udid $bundle > /dev/null 2>&1 || true
ls $out/shots | wc -l | awk '{print $1 " shots in '"$out"'/shots"}'
