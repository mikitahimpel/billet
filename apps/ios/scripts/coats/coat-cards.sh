#!/bin/zsh
# Renders Nooki/Resources/Coats/Coat-<coat>.png, the onboarding carousel cards: Tools/bake_hero.py --cards draws her
# splat sitting, as the room has her, in each coat. Needs Python 3 with numpy and Pillow; about 15 seconds a coat.
set -e
IOS=${0:a:h:h:h}
coats=($@)
(( $# )) || coats=(grey ginger cream tuxedo black calico)
python3 $IOS/Tools/bake_hero.py $IOS/Nooki/Resources/Coats --cards --coats $coats
