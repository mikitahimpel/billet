"""Stacks a time of day's layers (and a few cars) into one preview PNG: preview.py <dir> <time> <out.png>."""
import sys
from PIL import Image

d, t, out = sys.argv[1:4]
img = None
for name in ("sky", "far", "mid", "street"):
    layer = Image.open(f"{d}/{name}_{t}.png").convert("RGBA")
    img = layer if img is None else Image.alpha_composite(img, layer)
img.convert("RGB").save(out)
