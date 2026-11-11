#!/bin/zsh
# What the pull request's iOS run checks, on this Mac: the Swift packages as CI builds them (warnings are errors),
# swift-format and the design rules, then the app's unit and widget tests in a Simulator. UI tests are left out, as
# on a pull request; run the ones a change reaches with -only-testing.
#
#   scripts/verify-ios.sh [--packages | --app] [extra xcodebuild arguments]
#
# Builds wait for the Mac to be quiet (1-minute load under BILLET_MAX_LOAD, 40) and take the shared build lock, one
# build at a time across worktrees, so it never runs under another lock helper. The Simulator is
# BILLET_TEST_SIMULATOR; the app's DerivedData is deleted after.
#
# The app build maps this checkout and its DerivedData to fixed names, so the compilation cache every worktree shares
# (project.yml) hits for another worktree's build of the same source: about twice as fast as a cold build. Only
# command-line settings reach the Swift packages' targets, so the mapping is passed here, not in project.yml.
set -euo pipefail

part=all
case ${1:-} in
  --packages) part=packages; shift ;;
  --app) part=app; shift ;;
esac

root=$(git rev-parse --show-toplevel)
cd "$root"
simulator=${BILLET_TEST_SIMULATOR:-862C3666-D41C-406C-B0AE-843DA78898F2}
max_load=${BILLET_MAX_LOAD:-40}
lock=$HOME/.billet-manager/build.lock
mkdir -p "${lock:h}"

# sysctl prints "{ 1-minute 5-minute 15-minute }".
quiet() {
  until (( $(sysctl -n vm.loadavg | awk '{ print int($2) }') < max_load )); do
    echo "waiting: load $(sysctl -n vm.loadavg)"
    sleep 30
  done
}

locked() {
  until shlock -f "$lock" -p $$; do sleep 15; done
  local rc=0
  "$@" || rc=$?
  [[ $(cat "$lock" 2>/dev/null) == $$ ]] && rm -f "$lock"
  return $rc
}

if [[ $part != app ]]; then
  quiet
  locked pnpm turbo run ios:test ios:format:check
fi

if [[ $part != packages ]]; then
  derived=$(mktemp -d "${TMPDIR:-/tmp}/billet-verify.XXXXXX")
  log=$derived.log
  trap 'rm -rf "$derived"; xcrun simctl shutdown "$simulator" 2>/dev/null || true' EXIT
  (cd apps/ios && xcodegen generate --quiet)
  quiet
  map="\$(PROJECT_TEMP_DIR)=/^derived \$(BUILT_PRODUCTS_DIR)=/^built \$(OBJROOT)/../..=/^dd $root=/^workspace"
  prefix_mapping=(
    SWIFT_ENABLE_PREFIX_MAPPING=YES CLANG_ENABLE_PREFIX_MAPPING=YES
    SWIFT_ENABLE_PROJECT_PREFIX_MAPPING=YES CLANG_ENABLE_PROJECT_PREFIX_MAPPING=YES
    SWIFT_OTHER_PREFIX_MAPPINGS="$map" CLANG_OTHER_PREFIX_MAPPINGS="$map"
    # A session file's path and time are part of every Clang module's key.
    CLANG_MODULES_BUILD_SESSION_FILE=
  )
  result=0
  # TEST_RUNNER_ variables reach the tests without the prefix: Repo.root, which a mapped #filePath can't give.
  locked env TEST_RUNNER_BILLET_REPO="$root" xcodebuild test -project apps/ios/Billet.xcodeproj -scheme Billet -destination "id=$simulator" \
    -derivedDataPath "$derived" -skip-testing:OurioUITests "$@" \
    CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO "${prefix_mapping[@]}" >"$log" 2>&1 || result=$?
  grep -E 'error:|✘ Test [^r]|✔ Test run|✘ Test run|\*\* TEST (SUCCEEDED|FAILED)' "$log" | sort -u || true
  echo "full log: $log"
  exit $result
fi
