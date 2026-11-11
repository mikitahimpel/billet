#!/bin/zsh
# The Debug builds share one compilation cache (project.yml), which Xcode never trims when it has its own path. Past
# the limit it is deleted whole, and the next build fills it again; not while another build may be reading it.
dir=${COMPILATION_CACHE_CAS_PATH:-$HOME/Library/Caches/billet-compilation-cache}
limit_kb=$((10 * 1024 * 1024))
[[ $CONFIGURATION == Debug && -d $dir ]] || exit 0
(( $(du -sk "$dir" | cut -f1) > limit_kb )) || exit 0
(( $(pgrep -x xcodebuild | wc -l) <= 1 )) || exit 0
rm -rf "$dir"
