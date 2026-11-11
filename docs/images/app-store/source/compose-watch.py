#!/usr/bin/env python3
"""Lays the generated posters in posters/ over the To watch grid.

Usage: compose-watch.py <capture.png> <out.png>
The capture is the To watch sheet as seed.py leaves it (iPhone 17 Pro, 1206 × 2622): the made-up titles have no
TMDB poster, so the app draws its own gradient tiles. Each poster fills its tile and the app's "both" pill or
partner avatar is copied back on top from the capture.
"""
import sys, pathlib
from PIL import Image, ImageDraw

capture, out = sys.argv[1], sys.argv[2]
here = pathlib.Path(__file__).parent
base = Image.open(capture).convert("RGB")
result = base.copy()

# Measured on the capture, in pixels.
COLS = (60, 434, 808)
ROW0, ROW_STEP = 624, 543
TILE_W, TILE_H, TILE_R = 338, 507, 28
BADGE = 24            # inset of the pill and the avatar from the tile's corner
PILL_W, PILL_H = 166, 67
AVATAR_D = 70

for n in range(1, 10):              # tile 0 is the Add tile
    x, y = COLS[n % 3], ROW0 + ROW_STEP * (n // 3)
    poster = Image.open(here / "posters" / f"{n}.jpg").convert("RGB")
    scale = max(TILE_W / poster.width, TILE_H / poster.height)
    poster = poster.resize((round(poster.width * scale), round(poster.height * scale)), Image.Resampling.LANCZOS)
    left, top = (poster.width - TILE_W) // 2, (poster.height - TILE_H) // 2
    poster = poster.crop((left, top, left + TILE_W, top + TILE_H))

    mask = Image.new("L", (TILE_W, TILE_H), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, TILE_W - 1, TILE_H - 1), TILE_R, fill=255)
    result.paste(poster, (x, y), mask)

    # The badge: a pill for "both", a circle for one partner's avatar.
    badge = Image.new("L", (TILE_W, TILE_H), 0)
    d = ImageDraw.Draw(badge)
    pill = (BADGE - 1, BADGE - 1, BADGE + PILL_W, BADGE + PILL_H)
    tile = base.crop((x, y, x + TILE_W, y + TILE_H))
    r, g, _ = tile.convert("RGB").split()
    probe = (BADGE + PILL_W // 2, BADGE + 4)
    if r.getpixel(probe) > 200 and 130 < g.getpixel(probe) < 190:  # honey: a "both" pill
        d.rounded_rectangle(pill, PILL_H // 2 + 1, fill=255)
    else:
        d.ellipse((BADGE - 2, BADGE - 2, BADGE + AVATAR_D - 2, BADGE + AVATAR_D - 2), fill=255)
    result.paste(tile, (x, y), badge)

result.save(out)
print(out)
