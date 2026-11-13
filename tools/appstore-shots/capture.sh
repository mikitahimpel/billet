#!/bin/bash
# Raw App Store screens of the current app, from the -landingDemo fixture, on a shut-down Simulator.
# Usage: tools/appstore-shots/capture.sh [--no-build] [panel-id ...]   (default: every panel in manifest/en.json)
# Env: SIM_NAME (default ui-fixes2-pm, an iPhone 17 Pro Max), OUT (default ~/Developer/billet-shots/appstore/raw)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT=${OUT:-$HOME/Developer/billet-shots/appstore/raw}
SIM_NAME=${SIM_NAME:-ui-fixes2-pm}
DD=${DERIVED_DATA:-$HOME/Library/Caches/appstore-shots-dd}
BUILD=1
[ "${1:-}" = "--no-build" ] && { BUILD=0; shift; }

# panel -> launch arguments of the app (after -landingDemo YES)
args_for() {
  case "$1" in
    room) echo "" ;;
    mochi) echo "-landingGo pet" ;;
    groceries) echo "-landingGo groceries" ;;
    movies) echo "-landingGo list" ;;
    places) echo "-landingGo places" ;;
    days) echo "-landingGo us" ;;
    moments) echo "-shotMoments photos" ;;
    shop) echo "-landingGo shop" ;;
    *) echo "unknown panel $1" >&2; exit 2 ;;
  esac
}
PANELS=("$@")
[ ${#PANELS[@]} -eq 0 ] && PANELS=(room mochi groceries movies places days moments shop)

UDID=$(xcrun simctl list devices -j | python3 -c "
import json,sys
for r,l in json.load(sys.stdin)['devices'].items():
    for d in l:
        if d['name']==sys.argv[1] and d['isAvailable']: print(d['udid'])" "$SIM_NAME" | head -1)
[ -n "$UDID" ] || { echo "no Simulator named $SIM_NAME" >&2; exit 1; }
case "$SIM_NAME" in billet-golden-iphone-17) echo "refusing the golden Simulator" >&2; exit 1 ;; esac
state=$(xcrun simctl list devices -j | python3 -c "
import json,sys
for l in json.load(sys.stdin)['devices'].values():
    for d in l:
        if d['udid']==sys.argv[1]: print(d['state'])" "$UDID")
[ "$state" = "Shutdown" ] || { echo "$SIM_NAME is $state, not shut down: someone is using it" >&2; exit 1; }
avail=$(df -g / | awk 'NR==2{print $4}'); [ "$avail" -ge 8 ] || { echo "less than 8 GB free" >&2; exit 1; }

mkdir -p "$OUT"
cleanup() {
  xcrun simctl shutdown "$UDID" 2>/dev/null || true
  [ "$(cat ~/.billet-manager/build.lock 2>/dev/null)" = "$$" ] && rm -f ~/.billet-manager/build.lock
}
trap cleanup EXIT
~/.billet-manager/bin/lockq-wait $$ appstore-shots

APP="$DD/Build/Products/Debug-iphonesimulator/Billet.app"
if [ "$BUILD" = 1 ]; then
  (cd "$ROOT/apps/ios" && xcodegen generate >/dev/null)
  XCODE_XCCONFIG_FILE=$HOME/.warmbuild/warmbuild.xcconfig xcodebuild build \
    -project "$ROOT/apps/ios/Billet.xcodeproj" -scheme Billet -configuration Debug \
    -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO -quiet
fi

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance dark
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3
xcrun simctl uninstall "$UDID" com.ourio.app 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

# The first launch after an install prepares the room and draws nothing yet: warm it up, then capture.
xcrun simctl launch "$UDID" com.ourio.app -onboardingDone YES -uitestNoHints YES -design.look dusk \
  -landingDemo YES >/dev/null
sleep "${WARMUP:-30}"

for panel in "${PANELS[@]}"; do
  xcrun simctl terminate "$UDID" com.ourio.app 2>/dev/null || true
  # shellcheck disable=SC2046
  xcrun simctl launch "$UDID" com.ourio.app -onboardingDone YES -uitestNoHints YES -design.look dusk \
    -landingDemo YES $(args_for "$panel") >/dev/null
  sleep "${SETTLE:-14}"
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$panel.png"
  echo "captured $panel"
done
xcrun simctl status_bar "$UDID" clear
