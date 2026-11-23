#!/bin/bash
# Stacks two runs' movies, the first above the second, and prints their numbers together:
#   tools/cat-motion/compare.sh <before> <after> [scenario ...]
# Movies land in ~/Library/Caches/cat-motion/<before>-vs-<after>/.
set -euo pipefail
cache="$HOME/Library/Caches/cat-motion"
a="$1" b="$2"
shift 2
out="$cache/$a-vs-$b"
mkdir -p "$out"
names=("$@")
if [ ${#names[@]} -eq 0 ]; then
  for f in "$cache/$b"/*.mp4; do names+=("$(basename "$f" .mp4)"); done
fi
for name in "${names[@]}"; do
  [ -f "$cache/$a/$name.mp4" ] && [ -f "$cache/$b/$name.mp4" ] || continue
  # The shorter run holds its last frame until the longer one ends.
  ffmpeg -loglevel error -y -i "$cache/$a/$name.mp4" -i "$cache/$b/$name.mp4" -filter_complex \
    "[0:v]tpad=stop_mode=clone:stop_duration=30[x];[1:v]tpad=stop_mode=clone:stop_duration=30[y];[x][y]vstack=shortest=1" \
    -t "$(for l in "$a" "$b"; do ffprobe -v error -show_entries format=duration -of csv=p=0 "$cache/$l/$name.mp4"; done | sort -n | tail -1)" \
    -c:v libx264 -crf 20 -pix_fmt yuv420p "$out/$name.mp4"
  echo "--- $a"
  cat "$cache/$a/$name.txt"
  echo "--- $b"
  cat "$cache/$b/$name.txt"
  echo
done
echo "$out"
