#!/bin/bash
# Checks a Release archive before TestFlight: bundle IDs (the app and its three extensions), version 1.0.0, build number, team 2666YPBJTB signing;
# API_HOST is the app's BilletAPIHost; the store as EXPECT_PAYMENTS says (none unless the run asked for storekit), never
# the mock store; Labs as EXPECT_LABS says (NO unless the run asked for a Labs build); no -perf.script hooks (OurioPerf,
# ScenePerf).
#   check-archive.sh <path.xcarchive> <build-number>
set -euo pipefail

archive=${1:?usage: check-archive.sh <path.xcarchive> <build-number>}
build=${2:?usage: check-archive.sh <path.xcarchive> <build-number>}
version=1.0.0
team=2666YPBJTB
expect_labs=${EXPECT_LABS:-NO}
expect_payments=${EXPECT_PAYMENTS:-none}
app="$archive/Products/Applications/Billet.app"
failed=0
fail() {
  echo "::error::$1"
  failed=1
}
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Info.plist" 2> /dev/null || true; }

check_bundle() {
  local path=$1 id=$2
  if [ ! -d "$path" ]; then
    fail "missing ${path#"$archive"/}"
    return
  fi
  local got_id got_version got_build got_team
  got_id=$(plist "$path" CFBundleIdentifier)
  got_version=$(plist "$path" CFBundleShortVersionString)
  got_build=$(plist "$path" CFBundleVersion)
  [ "$got_id" = "$id" ] || fail "$id: bundle ID is $got_id"
  [ "$got_version" = "$version" ] || fail "$id: version is $got_version, not $version"
  [ "$got_build" = "$build" ] || fail "$id: build is $got_build, not $build"
  codesign --verify --strict "$path" || fail "$id: codesign --verify failed"
  got_team=$(codesign -dv "$path" 2>&1 | sed -n 's/^TeamIdentifier=//p' || true)
  [ "$got_team" = "$team" ] || fail "$id: signed by team $got_team, not $team"
  echo "$id $got_version ($got_build), team $got_team, signature verified"
}

check_bundle "$app" com.ourio.app
check_bundle "$app/PlugIns/OurioWidgets.appex" com.ourio.app.widget
check_bundle "$app/PlugIns/OurioNotifications.appex" com.ourio.app.notification-service
check_bundle "$app/PlugIns/OurioShare.appex" com.ourio.app.share

payments=$(plist "$app" BilletPayments)
labs=$(plist "$app" BilletLabs)
case $expect_payments in
  none | storekit)
    [ "$payments" = "$expect_payments" ] ||
      fail "the app's store is '$payments', not $expect_payments: build with BILLET_PAYMENTS=$expect_payments"
    ;;
  *) fail "store: EXPECT_PAYMENTS is '$expect_payments', not none or storekit" ;;
esac
case $expect_labs in
  NO) [ "$labs" = NO ] || fail "Labs is '$labs' in the app, not NO: build without BILLET_LABS" ;;
  YES) [ "$labs" = YES ] || fail "Labs is '$labs' in the app, not YES: build with BILLET_LABS=YES" ;;
  *) fail "Labs: EXPECT_LABS is '$expect_labs', not YES or NO" ;;
esac
binary="$app/$(plist "$app" CFBundleExecutable)"
if [ ! -f "$binary" ]; then
  fail "missing the app's binary"
elif grep -qa MockPaymentsBuild "$binary"; then
  fail "the app's binary carries the mock store"
elif [ "$expect_payments" = none ] && grep -qa StoreKitPayments "$binary"; then
  fail "the app's binary carries the StoreKit store, but the run asked for none"
elif grep -qaE 'ScenePerf8Recorder|scroll: no page scroll view on|error no scene on screen' "$binary"; then
  # A key as short as "perf.script" is stored inline in code, so the check looks for the hooks' own long strings.
  fail "the app's binary carries the -perf.script hooks: build without BILLET_PERF_HOOKS"
fi
echo "store: $payments, Labs: $labs"

if [ -z "${API_HOST:-}" ]; then
  fail "API_HOST is not set"
else
  host=$(plist "$app" BilletAPIHost)
  [ "$host" = "$API_HOST" ] || fail "the app's BilletAPIHost is '$host', not API_HOST '$API_HOST'"
  echo "API host: $host"
fi

exit $failed
