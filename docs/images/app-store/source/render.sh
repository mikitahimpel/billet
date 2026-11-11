#!/bin/sh
# Renders index.html#1… to ../01.png… at 1290 × 2796 (App Store 6.9" slot).
# Needs Google Chrome, ImageMagick, macOS (the app's SF Pro Rounded is read from
# /System/Library/Fonts) and a network connection for Caveat Brush.
# Usage: render.sh [slide numbers…]   (default: every slide in index.html)
set -e
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
slides="$*"
[ -n "$slides" ] || slides=$(grep -o 'id="s[0-9]*"' index.html | tr -dc '0-9\n')
for i in $slides; do
  out="../$(printf %02d "$i").png"
  rm -f "$out"
  # Chrome can exit non-zero on teardown after writing the file, so the file is the check.
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --allow-file-access-from-files --window-size=1290,2796 --virtual-time-budget=8000 \
    --screenshot="$PWD/$out" "file://$PWD/index.html#$i" >/dev/null 2>&1 || true
  [ -s "$out" ] || { echo "slide $i did not render" >&2; exit 1; }
  # App Store Connect rejects screenshots with an alpha channel.
  magick "$out" -background white -alpha remove -alpha off "$out"
  echo "$out"
done
