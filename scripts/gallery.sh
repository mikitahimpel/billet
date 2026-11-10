#!/bin/bash
# The design gallery (apps/ios/OurioTests/Gallery) on an iOS Simulator: every design component and the
# key screens at the SE and Pro Max sizes and the largest text size, against the WebP references in
# packages/ios/design/Tests/Gallery/References. One build, one test run.
#
#   scripts/gallery.sh            compare
#   scripts/gallery.sh --record   draw the pages again and keep them as the new references
#
# Runs under ~/.billet-manager/build.lock, once the load is under 40, with its own Simulator, which it
# shuts down after.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

gallery=packages/ios/design/Tests/Gallery
derived=${GALLERY_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/billet-gallery}
device_name=billet-gallery
runtime=com.apple.CoreSimulator.SimRuntime.iOS-27-2
lock=~/.billet-manager/build.lock

udid=$(xcrun simctl list devices available -j |
  jq -r --arg name "$device_name" --arg runtime "$runtime" '.devices[$runtime][]? | select(.name == $name) | .udid' |
  head -1)
if [[ -z $udid ]]; then
  udid=$(xcrun simctl create "$device_name" com.apple.CoreSimulator.SimDeviceType.iPhone-17 "$runtime")
fi

if [[ ${1:-} == --record ]]; then
  rm -rf "$gallery/Recorded"
fi

# The Simulator is shared by every worktree's gallery run, so it is shut down only by the run that
# holds the lock, and the lock file is removed only when it still names this script.
holding=0
release() {
  ((holding)) || return 0
  xcrun simctl shutdown "$udid" 2>/dev/null || true
  [[ $(tr -dc 0-9 <"$lock" 2>/dev/null) == "$$" ]] && rm -f "$lock"
}
trap release EXIT
trap 'exit 130' INT TERM

# Waits while the machine is busy (1-minute load over 40) or another live process holds the lock.
# It never clears or rewrites the lock: macOS shlock refuses even a lock whose pid is gone, so a stale
# one waits for whoever owns it, or the manager, to remove it.
while true; do
  load=$(sysctl -n vm.loadavg | awk '{print int($2)}')
  if ((load > 40)); then
    echo "gallery: load $load is over 40; waiting"
  elif shlock -f "$lock" -p $$; then
    holding=1
    break
  else
    holder=$(tr -dc 0-9 <"$lock" 2>/dev/null)
    if [[ -n $holder ]] && kill -0 "$holder" 2>/dev/null; then
      echo "gallery: build.lock is held by $holder ($(ps -o command= -p "$holder" | cut -c1-100)); waiting"
    else
      echo "gallery: build.lock names ${holder:-nobody}, which is not running; waiting for its owner to clear it"
    fi
  fi
  sleep 30
done

(cd apps/ios && xcodegen generate --quiet)
xcode() {
  perl -e 'alarm shift; exec @ARGV' 900 xcodebuild "$@" -quiet -project apps/ios/Billet.xcodeproj \
    -scheme Billet -destination "id=$udid" -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO
}
status=0
xcode build-for-testing
xcode test-without-building -only-testing:OurioTests/GalleryTests || status=$?

if [[ ${1:-} == --record ]]; then
  mkdir -p "$gallery/References"
  for png in "$gallery"/Recorded/*.png; do
    [[ -e $png ]] || continue
    cwebp -quiet -lossless -exact -z 9 -metadata icc "$png" -o "$gallery/References/$(basename "${png%.png}").webp"
  done
  rm -rf "$gallery/Recorded"
  echo "References written to $gallery/References; run scripts/gallery.sh to compare."
  exit 0
fi
exit $status
