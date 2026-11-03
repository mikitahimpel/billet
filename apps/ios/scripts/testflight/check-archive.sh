#!/bin/bash
# Checks a Release archive before it goes to TestFlight:
#   check-archive.sh <path.xcarchive> <build-number>
#
# - the app, widget and notification service have their bundle IDs, version 0.1.0 and the build
#   number, and are signed by team 2666YPBJTB and pass codesign --verify;
# - nothing from Rive is in the app;
# - every cat file in the PetSceneReality sources is in the bundle;
# - the demo host (DEMO_HOST in the environment) is the app's BilletDemoHost and is nowhere in
#   the git history of this checkout.
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
check_bundle "$app/PlugIns/BilletWidget.appex" com.mikitahimpel.billet.widget
check_bundle "$app/PlugIns/BilletNotificationService.appex" com.mikitahimpel.billet.notification-service

rive_files=$(find "$app" -iname '*rive*' | wc -l | tr -d ' ')
rive_links=$(otool -L "$app/Billet" | grep -ci rive || true)
[ "$rive_files" = 0 ] && [ "$rive_links" = 0 ] || fail "Rive is in the app ($rive_files files, $rive_links links)"
echo "Rive: $rive_files files, $rive_links links"

cats_source=packages/pet-scenes/reality/Sources/PetSceneReality/Resources/Cats
cats_bundle="$app/PetSceneReality_PetSceneReality.bundle/Cats"
want=$(git ls-files "$cats_source" | sed "s|^$cats_source/||" | sort)
have=$( (cd "$cats_bundle" 2> /dev/null && find . -type f | sed 's|^\./||') | sort)
missing=$(comm -23 <(echo "$want") <(echo "$have"))
[ -n "$want" ] || fail "no cat files found in $cats_source"
[ -z "$missing" ] || fail "cat files missing from the app: $(echo "$missing" | tr '\n' ' ')"
echo "cats: $(comm -12 <(echo "$want") <(echo "$have") | grep -c .) of $(echo "$want" | grep -c .) in the app"

if [ -z "${DEMO_HOST:-}" ]; then
  fail "DEMO_HOST is not set"
else
  [ "$(plist "$app" BilletDemoHost)" = "$DEMO_HOST" ] || fail "the app's BilletDemoHost is not DEMO_HOST"
  in_git=$(git log --all -p -S"$DEMO_HOST" --format=%h | grep -c . || true)
  in_tree=$(git grep -cF -- "$DEMO_HOST" | grep -c . || true)
  [ "$in_git" = 0 ] && [ "$in_tree" = 0 ] || fail "the demo host is in git ($in_git history lines, $in_tree files)"
  echo "demo host: in the app, not in git"
fi

exit $failed
