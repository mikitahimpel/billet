#!/bin/zsh
# Bakes the welcome Mochi: Tools/bake_welcome.py renders her in Blender (BLENDER=path), ffmpeg (hevc_videotoolbox)
# encodes HEVC-with-alpha clips into Nooki/Resources/Welcome plus the poster; prints size vs the 3 MB budget.
# Run under the build lock: shlock -f ~/.billet-manager/build.lock -p $$ && scripts/welcome/bake-welcome.sh
set -e
IOS=${0:a:h:h:h}
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
SAMPLES=${SAMPLES:-48}
OUT=$IOS/Nooki/Resources/Welcome
POSTER=$IOS/Nooki/Assets.xcassets/welcome-poster.imageset
work=$(mktemp -d)
mkdir -p $OUT $POSTER
for clip in idle wave; do
  $BLENDER -b --python $IOS/Tools/bake_welcome.py -- $work --clip $clip --samples $SAMPLES >/dev/null
  ffmpeg -y -loglevel error -framerate 24 -i $work/$clip-%03d.png \
    -c:v hevc_videotoolbox -alpha_quality 0.8 -b:v 1M -tag:v hvc1 -pix_fmt bgra \
    $OUT/welcome-$clip.mov
done
# The poster is the idle clip's first frame: what shows until the video's first frame is ready.
sips -s format png $work/idle-000.png --out $POSTER/welcome-poster.png >/dev/null
cat > $POSTER/Contents.json <<'JSON'
{ "images": [ { "idiom": "universal", "filename": "welcome-poster.png" } ], "info": { "author": "xcode", "version": 1 } }
JSON
rm -rf $work
du -ck $OUT/*.mov $POSTER/welcome-poster.png | tail -1 | awk '{printf "welcome assets: %d KB of 3072 KB\n", $1}'
