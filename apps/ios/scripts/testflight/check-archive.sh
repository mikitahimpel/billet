#!/bin/bash
# Checks a Release archive before TestFlight: bundle IDs (the app and its three extensions), version 0.1.0, build number, team 2666YPBJTB signing;
# DEMO_HOST is the app's BilletAPIHost and nowhere in git history; StoreKit store, no mock store, and Labs as
# EXPECT_LABS says (NO unless the run asked for a Labs build).
#   check-archive.sh <path.xcarchive> <build-number>  (repository root, full history; never prints the host)
set -euo pipefail

archive=${1:?usage: check-archive.sh <path.xcarchive> <build-number>}
build=${2:?usage: check-archive.sh <path.xcarchive> <build-number>}
version=0.1.0
team=2666YPBJTB
expect_labs=${EXPECT_LABS:-NO}
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
[ "$payments" = storekit ] || fail "the app's store is '$payments', not storekit: build with BILLET_PAYMENTS=storekit"
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
fi
echo "store: $payments, Labs: $labs"

if [ -z "${DEMO_HOST:-}" ]; then
  fail "DEMO_HOST is not set"
else
  [ "$(plist "$app" BilletAPIHost)" = "$DEMO_HOST" ] || fail "the app's BilletAPIHost is not DEMO_HOST"
  in_git=$(git log --all -p -S"$DEMO_HOST" --format=%h | grep -c . || true)
  in_tree=$(git grep -cF -- "$DEMO_HOST" | grep -c . || true)
  [ "$in_git" = 0 ] && [ "$in_tree" = 0 ] || fail "the server host is in git ($in_git history lines, $in_tree files)"
  echo "server host: in the app, not in git"
fi

exit $failed
