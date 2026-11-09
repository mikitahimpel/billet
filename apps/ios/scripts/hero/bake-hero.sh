#!/bin/zsh
# Bakes the hero Mochi of the splash and the welcome: Tools/bake_hero.py renders the seated splat in every coat into
# Nooki/Resources/Hero and prints the patch rectangles, which go into HeroImages (Nooki/UI/Kit/CatHeroStage.swift).
# Needs Python 3 with numpy and Pillow; about two minutes a coat.
set -e
IOS=${0:a:h:h:h}
python3 $IOS/Tools/bake_hero.py $IOS/Nooki/Resources/Hero "$@"
du -ck $IOS/Nooki/Resources/Hero/*.webp | tail -1 | awk '{printf "hero assets: %d KB\n", $1}'
