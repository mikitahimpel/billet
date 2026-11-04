"""Paints the far cards of the 3D night street into one texture, in the flat views' night palette:
the roofline of the next street over (with a few lit windows and its trees), then the far hills,
the town at their foot, the city's towers with lit floors, the water tower and the radio mast.
Also a glow sprite for the lamps, the far ground's fade to the horizon, the night sky's gradient
behind everything and a star.

Reads the layout make_street_view.py wrote; each card is painted in its own world units, so a
window is the same size on screen wherever its card stands.

    python3 paint_street_cards.py <out dir>      # reads <out>/cards.json, writes street-cards.png
"""

import json
import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(sys.argv[1])
# A FLUX skyline (assets-source/street/skyline.png) takes the far card's place when present.
FLUX_SKYLINE = Path(__file__).resolve().parent.parent / "assets-source" / "street" / "skyline.png"
# The rows of it that hold the skyline: from above the mast's light to the near hills.
FLUX_BAND = (330, 700)
# Where the towers stand, in units across the far card from straight out: right of the note.
FLUX_TOWERS_AT = 30.0
# The share of its width a mirrored tile keeps: everything left of the mast.
FLUX_MIRROR_KEEP = 0.76
# How much of the far card's height the band fills, from its foot.
FLUX_HEIGHT_SHARE = 0.7
INFO = json.loads((OUT / "cards.json").read_text())
SIZE = (4096, 1024)
SS = 2  # painted at twice the size, then halved, for smooth edges

FAR, MIDDLE, HORIZON, STREET = 0x20365A, 0x14233D, 0x3A5A86, 0x0E1A2E
LAMP, LAMP_CORE = 0xFFC36B, 0xFFE2B0
# The flat views' night sky (ViewLook, night): its top, middle and horizon.
SKY_TOP, SKY_MIDDLE = 0x070C18, 0x162846


def rgb(h, a=255):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255, a)


def mixed(a, b, t):
    ca, cb = rgb(a), rgb(b)
    c = [int(round(x + (y - x) * t)) for x, y in zip(ca[:3], cb[:3])]
    return (c[0] << 16) | (c[1] << 8) | c[2]


def lit(h, s):
    return mixed(h, 0xFFFFFF if s >= 0 else 0x000000, abs(s))


# The sky's colour by height in units, from the top of its wall to below the horizon, which sits
# at the far card's foot as the flat view's does at its hills.
SKY_STOPS = [
    (240.0, SKY_TOP),
    (110.0, mixed(SKY_TOP, SKY_MIDDLE, 0.55)),
    (50.0, SKY_MIDDLE),
    (12.0, mixed(SKY_MIDDLE, HORIZON, 0.6)),
    (-5.0, HORIZON),
    (-60.0, mixed(HORIZON, STREET, 0.6)),
]


class Card:
    """Draws in a card's world units onto its rect of the texture."""

    def __init__(self, draw, card):
        self.d, self.c = draw, card
        x, y, w, h = card["px"]
        self.ox, self.oy, self.w, self.h = x * SS, y * SS, w * SS, h * SS

    def __getitem__(self, key):
        return self.c[key]

    def p(self, x, z):
        c = self.c
        return (self.ox + (x - c["x0"]) / (c["x1"] - c["x0"]) * self.w,
                self.oy + (c["z1"] - z) / (c["z1"] - c["z0"]) * self.h)

    def poly(self, pts, colour):
        self.d.polygon([self.p(x, z) for x, z in pts], fill=colour)

    def rect(self, x0, z0, x1, z1, colour):
        a, b = self.p(x0, z1), self.p(x1, z0)
        self.d.rectangle([a, b], fill=colour)

    def line(self, pts, colour, width):
        self.d.line([self.p(x, z) for x, z in pts], fill=colour, width=max(1, int(width * self.w / (self.c["x1"] - self.c["x0"]))))

    def ellipse(self, x, z, rx, rz, colour):
        a, b = self.p(x - rx, z + rz), self.p(x + rx, z - rz)
        self.d.ellipse([a, b], fill=colour)


def roofline(card):
    """The next street over: a row of roofs and trees, lit windows here and there."""
    rng = random.Random(3)
    ground = card["z0"]
    roof = mixed(MIDDLE, FAR, 0.45)
    x = card["x0"]
    while x < card["x1"]:
        width = rng.uniform(7, 12)
        wall = rng.uniform(3.5, 6.5)
        rise = rng.uniform(2.5, 4.0)
        shade = lit(roof, rng.uniform(-0.04, 0.05))
        card.rect(x, ground, x + width, ground + wall, rgb(shade))
        card.poly([(x - 0.6, ground + wall), (x + width + 0.6, ground + wall),
                   (x + width / 2, ground + wall + rise)], rgb(lit(shade, -0.05)))
        if rng.random() < 0.4:
            cx = x + width * rng.uniform(0.6, 0.8)
            card.rect(cx, ground + wall + rise * 0.3, cx + 0.9, ground + wall + rise + 0.8, rgb(lit(shade, -0.05)))
        for k in range(int(width // 3.5)):
            if rng.random() < 0.42:
                wx = x + 1 + k * 3.5
                card.rect(wx, ground + wall - 2.4, wx + 1.3, ground + wall - 0.9, rgb(LAMP, 200))
        if rng.random() < 0.55:
            tx = x + width + rng.uniform(0.5, 2.5)
            r = rng.uniform(2.4, 3.8)
            tree = rgb(mixed(lit(roof, -0.03), 0x10302C, 0.2))
            card.rect(tx - 0.25, ground, tx + 0.25, ground + 5, tree)
            for dx, dz, k in [(0, 0, 1.0), (-r * 0.5, -r * 0.4, 0.7), (r * 0.5, -r * 0.35, 0.75)]:
                card.ellipse(tx + dx, ground + 5 + r * 0.7 + dz, r * k, r * k * 1.05, tree)
        x += width + rng.uniform(1.5, 4.5)
    # Power poles and their wires along the street.
    pole = rgb(lit(roof, -0.25))
    xs = [card["x0"] + 4 + k * 28 for k in range(int((card["x1"] - card["x0"]) // 28) + 1)]
    for px in xs:
        card.rect(px - 0.18, ground, px + 0.18, ground + 11, pole)
        card.rect(px - 1.6, ground + 10.2, px + 1.6, ground + 10.5, pole)
    for a, b in zip(xs, xs[1:]):
        for off, sag in [(-1.4, 1.6), (1.4, 1.6), (0, 2.2)]:
            pts = [(a + off + (b - a) * t, ground + 10.4 - (0.6 if off == 0 else 0) - sag * 4 * t * (1 - t))
                   for t in [k / 12 for k in range(13)]]
            card.line(pts, pole, 0.12)
    card.rect(card["x0"], ground - 2, card["x1"], ground + 0.4, rgb(lit(roof, -0.08)))


def skyline(card):
    """The far hills and the town under them, the city's towers, the water tower and the mast."""
    rng = random.Random(9)
    ground = card["z0"] + 2
    far = FAR
    city = mixed(far, HORIZON, 0.35)
    # The city's towers, a cluster off to the left of the middle, lit floors after dark.
    cx = -40.0
    for k in range(16):
        width = rng.uniform(5, 11)
        height = rng.uniform(9, 26) * (1 - abs(k - 7.5) / 14)
        x0 = cx + k * 7.2 + rng.uniform(-2, 2)
        shade = lit(city, 0.02 if k % 2 else -0.02)
        card.rect(x0, ground, x0 + width, ground + height, rgb(shade))
        z = ground + 2
        while z < ground + height - 1:
            x = x0 + 0.8
            while x < x0 + width - 1:
                if rng.random() < 0.3:
                    card.rect(x, z, x + 0.9, z + 0.7, rgb(LAMP, 150))
                x += 1.8
            z += 2.0
        if height > 20:
            card.rect(x0 + width / 2 - 0.15, ground + height, x0 + width / 2 + 0.15, ground + height + 6, rgb(shade))
            card.ellipse(x0 + width / 2, ground + height + 6, 0.5, 0.5, rgb(0xFF3B3B, 230))
    # Rolling hills in front of the city.
    pts = [(card["x0"], ground - 2)]
    x = card["x0"]
    phase = 0.0
    while x <= card["x1"]:
        h = 6 + 4 * math.sin(x * 0.021 + 1.3) + 2.5 * math.sin(x * 0.057 + phase) + 1.2 * math.sin(x * 0.13)
        pts.append((x, ground + max(h, 1.5)))
        x += 2
    pts.append((card["x1"], ground - 2))
    card.poly(pts, rgb(lit(far, 0.05)))
    # A far-off town along the foot of the hills.
    x = card["x0"]
    while x < card["x1"]:
        w = rng.uniform(3, 6)
        h = rng.uniform(1.5, 4)
        card.rect(x, ground - 2, x + w, ground + h, rgb(lit(far, -0.06)))
        if rng.random() < 0.5:
            card.rect(x + 1, ground + h - 1.2, x + 1.8, ground + h - 0.4, rgb(LAMP, 190))
        x += w + rng.uniform(0.5, 3)
    # The water tower on the hill to the right, and the radio mast to the left.
    tower = rgb(lit(far, -0.24))
    tx, tz = 70.0, ground + 9
    for dx in (-3.5, -1.2, 1.2, 3.5):
        card.line([(tx + dx * 0.8, tz), (tx + dx, ground + 2)], tower, 0.5)
    card.rect(tx - 4.5, tz, tx + 4.5, tz + 6, tower)
    card.poly([(tx - 5, tz + 6), (tx + 5, tz + 6), (tx, tz + 9)], tower)
    card.ellipse(tx, tz + 9.4, 0.5, 0.5, rgb(0xFF3B3B, 200))
    mx = -95.0
    mast = rgb(lit(far, -0.1))
    card.line([(mx - 2, ground + 4), (mx, ground + 28), (mx + 2, ground + 4)], mast, 0.35)
    for t in [k / 7 for k in range(1, 7)]:
        z = ground + 4 + 24 * t
        half = 2 * (1 - t)
        card.line([(mx - half, z), (mx + half, z + 2)], mast, 0.2)
    card.ellipse(mx, ground + 28.4, 0.7, 0.7, rgb(0xFF3B3B, 230))
    card.rect(card["x0"], card["z0"], card["x1"], ground - 1.5, rgb(lit(far, -0.02)))


def flux_skyline(image, card):
    """The FLUX skyline on the far card: its sky keyed out against the sky's own gradient, the
    band tiled across the card, every other tile mirrored so the hills run on."""
    src = Image.open(FLUX_SKYLINE).convert("RGB")
    w, h = src.size
    px = src.load()
    lum = lambda c: 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    # The sky's brightness row by row, fitted on the empty top rows and carried down.
    top = FLUX_BAND[0] - 20
    rows = [sum(lum(px[x, y]) for x in range(0, w, 4)) / (w / 4) for y in range(top)]
    n = len(rows)
    mean_y, mean_l = (n - 1) / 2, sum(rows) / n
    slope = sum((y - mean_y) * (l - mean_l) for y, l in enumerate(rows)) / sum((y - mean_y) ** 2 for y in range(n))
    sky = lambda y: mean_l + slope * (y - mean_y)
    y0, y1 = FLUX_BAND
    band = Image.new("RGBA", (w, y1 - y0))
    out = band.load()
    for y in range(y0, y1):
        expected = sky(y)
        solid = [False] * w
        for x in range(w):
            r, g, b = px[x, y]
            dark = (expected - lum((r, g, b))) / max(expected * 0.22, 1)
            warm = r > b + 40 or r > 150
            a = 1.0 if warm else min(max(dark, 0.0), 1.0)
            if 0 < a < 1:
                # Take the sky's share back out of an edge, so it never keeps a light rim.
                k = expected / max(lum((r, g, b)), 1)
                r, g, b = (int(min(255, max(0, (c - (1 - a) * c * k) / a))) for c in (r, g, b))
            out[x, y - y0] = (r, g, b, int(255 * a))
    # Below the first solid row of a column it is all hill: fill any gaps keying left there.
    alpha = band.getchannel("A").load()
    for x in range(w):
        seen = False
        for y in range(y1 - y0):
            if seen:
                alpha[x, y] = 255
            elif alpha[x, y] > 240 and y + 6 < y1 - y0 and all(alpha[x, y + k] > 200 for k in range(1, 6)):
                seen = True
    band.putalpha(band.getchannel("A"))
    cx, cy, cw, card_h = card.ox, card.oy, int(card.w), int(card.h)
    # The band fills the lower part of the card, so the town sits far off and low.
    ch = int(card_h * FLUX_HEIGHT_SHARE)
    cy += card_h - ch
    tile_w = int(w * ch / (y1 - y0))
    tile = band.resize((tile_w, ch), Image.LANCZOS)
    # Mirrored tiles leave out the mast, so two never stand side by side at a seam.
    keep = int(tile_w * FLUX_MIRROR_KEEP)
    mirrored = tile.crop((0, 0, keep, ch)).transpose(Image.FLIP_LEFT_RIGHT)
    # The source's towers are about at 0.7 of its width; put them at FLUX_TOWERS_AT.
    towers_px = (FLUX_TOWERS_AT - card["x0"]) / (card["x1"] - card["x0"]) * cw
    start = int(towers_px - 0.7 * tile_w)
    k0 = -((start + tile_w - 1) // tile_w) - 1
    strip = Image.new("RGBA", (cw, ch))
    # Tiles left of the towers' tile, then right of it: plain at even steps, mirrored at odd.
    pieces = {0: (start, tile)}
    x = start
    for k in range(1, cw // keep + 3):
        piece = mirrored if k % 2 else tile
        x -= piece.width
        pieces[-k] = (x, piece)
    x = start + tile_w
    for k in range(1, cw // keep + 3):
        piece = mirrored if k % 2 else tile
        pieces[k] = (x, piece)
        x += piece.width
    for x, piece in pieces.values():
        if x + piece.width < 0 or x > cw:
            continue
        strip.alpha_composite(piece, (max(x, 0), 0), (max(-x, 0), 0))
    image.alpha_composite(strip, (int(cx), int(cy)))


def glow(image, px):
    x, y, w, h = [v * SS for v in px]
    r, g, b, _ = rgb(LAMP_CORE)
    sprite = Image.new("RGBA", (w, h))
    pixels = sprite.load()
    for j in range(h):
        for i in range(w):
            d = math.hypot((i + 0.5) / w * 2 - 1, (j + 0.5) / h * 2 - 1)
            a = max(0.0, 1 - d) ** 2.2
            pixels[i, j] = (r, g, b, int(255 * 0.75 * a))
    image.alpha_composite(sprite, (x, y))


def ground(draw, px):
    x, y, w, h = [v * SS for v in px]
    near, far = lit(STREET, 0.02), mixed(lit(FAR, -0.15), HORIZON, 0.25)
    for j in range(h):
        draw.line([(x, y + j), (x + w, y + j)], fill=rgb(mixed(far, near, (j / h) ** 0.6)))


def sky(draw, card):
    """The sky's gradient down the strip: its rows run evenly from the wall's top to its foot."""
    x, y, w, h = [v * SS for v in card["px"]]
    z1, z0 = card["z1"], card["z0"]
    for j in range(h):
        z = z1 + (z0 - z1) * (j + 0.5) / h
        for (za, ca), (zb, cb) in zip(SKY_STOPS, SKY_STOPS[1:]):
            if zb <= z <= za:
                t = (za - z) / (za - zb)
                colour = mixed(ca, cb, t * t * (3 - 2 * t))
                break
        else:
            colour = SKY_STOPS[0][1] if z > SKY_STOPS[0][0] else SKY_STOPS[-1][1]
        draw.line([(x, y + j), (x + w - 1, y + j)], fill=rgb(colour))


def star(image, px):
    """A soft white point, as the flat view's stars are."""
    x, y, w, h = [v * SS for v in px]
    sprite = Image.new("RGBA", (w, h))
    pixels = sprite.load()
    for j in range(h):
        for i in range(w):
            d = math.hypot((i + 0.5) / w * 2 - 1, (j + 0.5) / h * 2 - 1)
            a = max(0.0, 1 - d) ** 2.6
            pixels[i, j] = (0xEE, 0xF2, 0xF7, int(255 * 0.9 * a))
    image.alpha_composite(sprite, (x, y))


def fade_edges(image):
    """Each card fades out over its outer tenth on either side, into the sky behind."""
    alpha = image.getchannel("A")
    pixels = alpha.load()
    for card in INFO["cards"]:
        if card["name"] not in ("roofline", "skyline"):
            continue
        x, y, w, h = [v * SS for v in card["px"]]
        edge = w // 10
        for i in range(edge):
            k = (i + 0.5) / edge
            k = k * k * (3 - 2 * k)
            for j in range(y, y + h):
                for col in (x + i, x + w - 1 - i):
                    pixels[col, j] = int(pixels[col, j] * k)
    image.putalpha(alpha)


def bleed(image):
    """Fills the colour under fully transparent pixels from the nearby opaque ones (alpha-weighted),
    so filtering at an edge blends towards the silhouette's own colour, never a light rim."""
    import numpy as np

    rgba = np.asarray(image).astype(np.float32) / 255
    a = rgba[..., 3:4]
    pre = Image.fromarray((np.clip(rgba[..., :3] * a, 0, 1) * 255).astype(np.uint8))
    weight = Image.fromarray((a[..., 0] * 255).astype(np.uint8))
    blurred = np.asarray(pre.filter(ImageFilter.GaussianBlur(6))).astype(np.float32) / 255
    w = np.asarray(weight.filter(ImageFilter.GaussianBlur(6))).astype(np.float32)[..., None] / 255
    fill = blurred / np.maximum(w, 1e-4)
    rgb = np.where(a > 0, rgba[..., :3], fill)
    out = np.concatenate([np.clip(rgb, 0, 1), a], -1)
    return Image.fromarray((out * 255).round().astype(np.uint8))


def main():
    image = Image.new("RGBA", (SIZE[0] * SS, SIZE[1] * SS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    for card in INFO["cards"]:
        name = card["name"]
        if name == "roofline":
            roofline(Card(draw, card))
        elif name == "skyline":
            if FLUX_SKYLINE.exists():
                flux_skyline(image, Card(draw, card))
            else:
                skyline(Card(draw, card))
        elif name == "ground":
            ground(draw, card["px"])
        elif name == "sky":
            sky(draw, card)
    for card in INFO["cards"]:
        if card["name"] == "glow":
            glow(image, card["px"])
        elif card["name"] == "star":
            star(image, card["px"])
    fade_edges(image)
    image = image.resize(SIZE, Image.LANCZOS)
    bleed(image).save(OUT / "street-cards.png", optimize=True)
    print("CARDS", OUT / "street-cards.png")


main()
