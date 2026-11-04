#!/bin/zsh
# Measures the scenes on a Release build in the Simulator, the same way every time.
#
#   apps/ios/scripts/perf/measure.sh <label> [--build] [--build-only] [--launches N] [--full N]
#                                    [--sweep] [--views] [--cost N]
#
# --build       generate the project and build Release for the Simulator first
# --launches N  cold launches with `-perf.script launch` (default 7; the first after install is
#               dropped, so N+1 are run)
# --full N      runs of `-perf.script full`: orbit, zoom, lighting, tabs (default 3)
# --sweep       one `-perf.script sweep` run, saving a screenshot at each held pose
# --views       one `-perf.script views` run: a screenshot of every window view, in Home and Shop
# --cost N      runs of `-perf.script cost`: each part of the room switched off in turn (default 0)
#               PERF_SWITCHES=a,b keeps them to those parts
# --build-only  build, then stop
#
# Runs add to <label>'s logs, so two builds can be measured in turns in one sitting, which is the
# only fair comparison on a shared Mac:
#   PERF_DERIVED=<a>/build-perf measure.sh base --launches 3 --full 1   # then the same for new,
#   and again, then report.py <out>/base <out>/new. ab.sh does exactly this.
#
# Logs and a summary go to $PERF_OUT/<label> (default ~/.billet-manager/pet-concept/perf/runs).
# Runs take the measuring lock (lock.sh), so agents queue instead of colliding. It then waits while
# another Simulator is booted, swap is over 15 GB or the disk has under 4 GB free, refuses to build
# while another build runs, and shuts its Simulator down when it ends.
set -euo pipefail

label=${1:?usage: measure.sh <label> [--build] [--launches N] [--full N] [--sweep] [--views] [--cost N]}
shift
build=0 build_only=0 launches=7 fulls=3 sweep=0 views=0 costs=0
while (($#)); do
  case $1 in
    --build) build=1 ;;
    --build-only) build=1 build_only=1 ;;
    --launches) launches=$2; shift ;;
    --full) fulls=$2; shift ;;
    --sweep) sweep=1 ;;
    --views) views=1 ;;
    --cost) costs=$2; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

here=${0:A:h}
app_dir=${here:h:h}
repo=${app_dir:h:h}
derived=${PERF_DERIVED:-$repo/build-perf}
out=${PERF_OUT:-$HOME/.billet-manager/pet-concept/perf/runs}/$label
device_name=${PERF_DEVICE:-billet-perf}
# Seconds one scripted run may take before it is given up on. CI runners are far slower.
run_limit=${PERF_RUN_LIMIT:-600}
# The model a missing device is made as, e.g. com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max.
device_type=${PERF_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro}
bundle=com.mikitahimpel.billet
group=group.com.mikitahimpel.billet
mkdir -p $out

gate() {
  local booted
  booted=$(xcrun simctl list devices booted | grep Booted | grep -v "$device_name (" || true)
  if [[ -n $booted ]]; then echo "another Simulator is booted: $booted" >&2; return 1; fi
  local swap free_gb
  swap=$(sysctl -n vm.swapusage | awk '{gsub("M","",$6); print int($6)}')
  if ((swap > 15360)); then echo "swap at ${swap} MB" >&2; return 1; fi
  free_gb=$(df -g / | awk 'NR==2 {print $4}')
  if ((free_gb < 4)); then echo "only ${free_gb} GB free" >&2; return 1; fi
}

if ((build)); then
  if pgrep -fl 'xcodebuild ' | grep -v AgentDeviceRunner | grep -qv 'zsh'; then
    echo "another xcodebuild is running" >&2
    exit 1
  fi
  (cd $app_dir && xcodegen generate -q)
  xcodebuild build -project $app_dir/Billet.xcodeproj -scheme Billet -configuration Release \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath $derived \
    CODE_SIGNING_ALLOWED=NO -quiet > $out/build.log 2>&1
fi
app=$derived/Build/Products/Release-iphonesimulator/Billet.app
[[ -d $app ]] || { echo "no app at $app; pass --build" >&2; exit 1; }
((build_only)) && exit 0
stamp=$(date +%H%M%S)

# A build without signing has no entitlements, so no App Group: sign it ad hoc with just that.
entitlements=$out/entitlements.plist
cat > $entitlements <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.application-groups</key><array><string>$group</string></array>
</dict></plist>
PLIST
for appex in $app/PlugIns/*.appex(N); do
  codesign -f -s - --entitlements $entitlements $appex > /dev/null 2>&1
done
codesign -f -s - --entitlements $entitlements $app > /dev/null 2>&1

source $here/lock.sh
perf_lock_take $label
trap 'perf_lock_give' EXIT
# Someone not using the lock may still have a Simulator up: wait for it rather than give up.
if ! gate 2> /dev/null; then
  gate || true
  echo "waiting for the gates" >&2
  until gate 2> /dev/null; do sleep 20; done
fi
udid=$(xcrun simctl list devices | awk -v n="$device_name" -F '[()]' '$0 ~ "^ +"n" \\(" {print $2; exit}')
if [[ -z $udid ]]; then
  udid=$(xcrun simctl create $device_name $device_type)
fi
trap 'xcrun simctl shutdown $udid >/dev/null 2>&1 || true; perf_lock_give' EXIT
xcrun simctl bootstatus $udid -b > /dev/null
xcrun simctl uninstall $udid $bundle > /dev/null 2>&1 || true
xcrun simctl install $udid $app

# The App Group exists once the app has run. Then: paired with the pretend partner, Shop and the
# Notes desk on, the standard room.
xcrun simctl launch $udid $bundle > /dev/null
python3 -c 'import time; time.sleep(3)'
xcrun simctl terminate $udid $bundle > /dev/null 2>&1 || true
containers=
for dir in $HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Containers/Shared/AppGroup/*(N); do
  if plutil -p $dir/.com.apple.mobile_container_manager.metadata.plist 2> /dev/null | grep -q "\"$group\""; then
    containers=$dir
  fi
done
[[ -n $containers ]] || { echo "no App Group container for $group" >&2; exit 1; }
print -r -- '{"fakePartner":true,"notesDesk":true}' > $containers/widget-features.json
print -r -- '"windowSeat"' > $containers/room-style.json
print -r -- '"amberLantern"' > $containers/room-lighting.json
print -r -- '"cosyNook"' > $containers/room-furniture.json
# Window Seat unless the run asks for another room (PERF_ROOM, Labs > Room).
print -r -- "\"${PERF_ROOM:-windowSeat}\"" > $containers/home-room.json

# One run of the app with a script. Prints screenshots when the run asks for them.
run() {
  local name=$1 script=$2 log=$out/$1-$stamp.log
  rm -rf $containers/perf-shots
  xcrun simctl terminate $udid $bundle > /dev/null 2>&1 || true
  python3 -c 'import time; time.sleep(1.5)'
  local only=()
  [[ -n ${PERF_SWITCHES:-} ]] && only=(-perf.switches $PERF_SWITCHES)
  xcrun simctl launch --console-pty $udid $bundle -perf.script $script $only > $log 2>&1 &
  local pid=$! started=$SECONDS
  while ! grep -q '^PERF done' $log 2>/dev/null; do
    if grep -q '^PERF shot' $log 2>/dev/null; then
      grep '^PERF shot' $log | tr -d '\r' | while read -r _ _ shot; do
        [[ -f $out/shots/$shot.png ]] && continue
        mkdir -p $out/shots
        # Twice at most: a busy runner's first try can hang until the alarm.
        for try in 1 2; do
          perl -e 'alarm 40; exec @ARGV' xcrun simctl io $udid screenshot $out/shots/$shot.png \
            > /dev/null 2>&1 && break
        done || true
        mkdir -p $containers/perf-shots && touch $containers/perf-shots/$shot
      done
    fi
    python3 -c 'import time; time.sleep(0.2)'
    if ((SECONDS - started > run_limit)); then echo "PERF error timeout" >> $log; break; fi
  done
  kill $pid 2> /dev/null || true
  wait $pid 2> /dev/null || true
}

uptime >> $out/load.txt
run warmup launch
for ((i = 1; i <= launches; i++)); do run launch-$i launch; done
for ((i = 1; i <= fulls; i++)); do run full-$i full; done
((sweep)) && run sweep sweep
((views)) && run views views
for ((i = 1; i <= costs; i++)); do run cost-$i cost; done
uptime >> $out/load.txt

du -sk $app | awk '{print $1}' > $out/app-kb.txt
python3 -I $here/report.py $out > $out/summary.md
cat $out/summary.md
