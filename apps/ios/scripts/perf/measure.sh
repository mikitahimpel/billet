#!/bin/zsh
# Measures Ourio's rooms on a Release build in the Simulator. Home opens on PERF_ROOM: `room` (default) or `city`.
# A Simulator without an Apple7 GPU (CI VMs) draws Mochi as the mesh cat, not the splats a phone shows.
#
#   apps/ios/scripts/perf/measure.sh <label> [--build] [--build-only] [--launches N] [--full N]
#                                    [--sweep] [--cost N] [--steady N] [--welcome N]
#
# --build       generate the project and build Release for the Simulator first
# --build-only  build, then stop
# --launches N  cold launches with `-perf.script launch` (default 7; one extra first run is dropped)
# --full N      runs of `-perf.script full`: orbit, tabs, settled (default 3)
# --sweep       one `-perf.script sweep` run, screenshotting the room, its turned poses and the tabs
# --cost N      runs of `-perf.script cost`, each room part off in turn (default 0; PERF_SWITCHES=a,b limits)
# --steady N    runs of `-perf.script steady`: Home left alone for a minute (default 0)
# --welcome N   launches onto the welcome counting late frames (`PERF phase welcome hitches=`) (default 0)
#
# PERF_APP_ARGS adds launch arguments to every run. Logs accumulate in $PERF_OUT/<label> (default
# ~/.billet-manager/pet-concept/perf/runs), so two builds measured in turns compare fairly; ab.sh does that.
# Takes the measuring lock (lock.sh); waits while another Simulator is up, swap > 15 GB or disk < 4 GB free.
set -euo pipefail

label=${1:?usage: measure.sh <label> [--build] [--launches N] [--full N] [--sweep] [--cost N] [--steady N] [--welcome N]}
shift
build=0 build_only=0 launches=7 fulls=3 sweep=0 costs=0 steadies=0 welcomes=0
while (($#)); do
  case $1 in
    --build) build=1 ;;
    --build-only) build=1 build_only=1 ;;
    --launches) launches=$2; shift ;;
    --full) fulls=$2; shift ;;
    --sweep) sweep=1 ;;
    --cost) costs=$2; shift ;;
    --steady) steadies=$2; shift ;;
    --welcome) welcomes=$2; shift ;;
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
bundle=com.ourio.app
group=group.com.ourio.app
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

# The App Group exists once the app has run; the screenshot handshake (perf-shots) lives in it.
xcrun simctl launch $udid $bundle -onboardingDone YES > /dev/null
python3 -c 'import time; time.sleep(3)'
xcrun simctl terminate $udid $bundle > /dev/null 2>&1 || true
containers=
for dir in $HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Containers/Shared/AppGroup/*(N); do
  if plutil -p $dir/.com.apple.mobile_container_manager.metadata.plist 2> /dev/null | grep -q "\"$group\""; then
    containers=$dir
  fi
done
[[ -n $containers ]] || { echo "no App Group container for $group" >&2; exit 1; }
room=${PERF_ROOM:-room}
[[ $room == room || $room == city ]] || { echo "PERF_ROOM must be room or city, not $room" >&2; exit 2; }
room_args=()
[[ $room == city ]] && room_args=(-room city)
app_args=(${=PERF_APP_ARGS:-})

# Prints screenshots when the run asks for them.
attempt() {
  local name=$1 script=$2 log=$out/$1-$stamp.log
  rm -rf $containers/perf-shots
  xcrun simctl terminate $udid $bundle > /dev/null 2>&1 || true
  python3 -c 'import time; time.sleep(1.5)'
  local only=()
  [[ -n ${PERF_SWITCHES:-} ]] && only=(-perf.switches $PERF_SWITCHES)
  # The welcome is the UI test's launch: onboarding from its first page, with the hitch probe instead of a script.
  local launch=(-onboardingDone YES $room_args $app_args -perf.script $script $only)
  [[ $script == welcome ]] && launch=(-onboardingDone NO -onboardingPage 0 -uitestNoRoom YES -uitestNoHints YES
    -uitestWelcomeProbe $app_args)
  xcrun simctl launch --console-pty $udid $bundle $launch > $log 2>&1 &
  local pid=$! started=$SECONDS
  while ! grep -q '^PERF done' $log 2>/dev/null; do
    if grep -q '^PERF shot' $log 2>/dev/null; then
      grep '^PERF shot' $log | tr -d '\r' | while read -r _ _ shot; do
        # Answered already in this attempt; a retried run takes its shots again.
        [[ -f $containers/perf-shots/$shot ]] && continue
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
    if ! kill -0 $pid 2> /dev/null && ! grep -q '^PERF done' $log; then
      echo "PERF error app exited" >> $log
      break
    fi
    if ((SECONDS - started > run_limit)); then echo "PERF error timeout" >> $log; break; fi
    # A build without `-perf.script` never prints anything: stop early.
    if ((SECONDS - started > 180)) && ! grep -q '^PERF' $log 2>/dev/null; then
      echo "PERF error no PERF lines: this build cannot run -perf.script" >> $log
      break
    fi
  done
  kill $pid 2> /dev/null || true
  wait $pid 2> /dev/null || true
}

# The Simulator's Metal host on a busy CI VM can drop the app's GPU work ("Ignored (for causing
# prior/excessive GPU errors)"); the app then aborts with a lost SimMetalHost connection. That is
# the runner, not the app, so such a run is tried once more. Its log is kept as crashed-<name>.
run() {
  local name=$1 log=$out/$1-$stamp.log mark=$out/.started-$1
  touch $mark
  attempt "$@"
  metal_crash() {
    find $HOME/Library/Logs/DiagnosticReports -name 'Billet-*.ips' -newer $mark 2> /dev/null \
      | xargs grep -l -s 'SimMetalHost' | grep -q .
  }
  local lost=0
  if tail -1 $log | grep -q '^PERF error app exited'; then
    # The crash report lands a few seconds after the app goes.
    for _ in {1..20}; do
      metal_crash && { lost=1; break; }
      python3 -c 'import time; time.sleep(0.5)'
    done
  fi
  if ((lost)); then
    echo "$name: the app lost the Simulator's Metal host; trying once more" >&2
    mv $log $out/crashed-$name-$stamp.log
    attempt "$@"
  fi
  rm -f $mark
}

uptime >> $out/load.txt
run warmup launch
for ((i = 1; i <= launches; i++)); do run launch-$i launch; done
for ((i = 1; i <= fulls; i++)); do run full-$i full; done
((sweep)) && run sweep sweep
for ((i = 1; i <= costs; i++)); do run cost-$i cost; done
for ((i = 1; i <= steadies; i++)); do run steady-$i steady; done
for ((i = 1; i <= welcomes; i++)); do run welcome-$i welcome; done
uptime >> $out/load.txt

du -sk $app | awk '{print $1}' > $out/app-kb.txt
python3 -I $here/report.py $out > $out/summary.md
cat $out/summary.md
