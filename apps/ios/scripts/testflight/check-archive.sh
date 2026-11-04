#!/bin/bash
# Checks a Release archive before it goes to TestFlight:
#   check-archive.sh <path.xcarchive> <build-number>
#
# - the app and its widget extension have their bundle IDs, version 0.1.0 and the build number, and
#   are signed by team 2666YPBJTB and pass codesign --verify;
# - the server host (DEMO_HOST in the environment) is the app's BilletAPIHost and is nowhere in the
#   git history of this checkout.
# Prints what it checked, never the host. Run from the repository root with full history.
set -euo pipefail

archive=${1:?usage: check-archive.sh <path.xcarchive> <build-number>}
build=${2:?usage: check-archive.sh <path.xcarchive> <build-number>}
version=0.1.0
team=2666YPBJTB
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
  got_team=$(codesign -dv "$path" 2>&1 | sed -n 's/^TeamIdentifier=//p')
  [ "$got_team" = "$team" ] || fail "$id: signed by team $got_team, not $team"
  echo "$id $got_version ($got_build), team $got_team, signature verified"
}

check_bundle "$app" com.mikitahimpel.billet
check_bundle "$app/PlugIns/NookiWidgets.appex" com.mikitahimpel.billet.widget

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
