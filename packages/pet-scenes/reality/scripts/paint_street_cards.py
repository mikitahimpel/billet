"""Paints the far cards of the 3D night street into one texture, in the flat views' night palette:
the roofline of the next street over (with a few lit windows and its trees), then the far hills,
the town at their foot, the city's towers with lit floors, the water tower and the radio mast.
Also a glow sprite for the lamps and the far ground's fade to the horizon.

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
INFO = json.loads((OUT / "cards.json").read_text())
SIZE = (4096, 1024)
SS = 2  # painted at twice the size, then halved, for smooth edges

FAR, MIDDLE, HORIZON, STREET = 0x20365A, 0x14233D, 0x3A5A86, 0x0E1A2E
LAMP, LAMP_CORE = 0xFFC36B, 0xFFE2B0


def rgb(h, a=255):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255, a)


def mixed(a, b, t):
    ca, cb = rgb(a), rgb(b)
    c = [int(round(x + (y - x) * t)) for x, y in zip(ca[:3], cb[:3])]
    return (c[0] << 16) | (c[1] << 8) | c[2]


def lit(h, s):
    return mixed(h, 0xFFFFFF if s >= 0 else 0x000000, abs(s))


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


def main():
    image = Image.new("RGBA", (SIZE[0] * SS, SIZE[1] * SS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    for card in INFO["cards"]:
        name = card["name"]
        if name == "roofline":
            roofline(Card(draw, card))
        elif name == "skyline":
            skyline(Card(draw, card))
        elif name == "ground":
            ground(draw, card["px"])
    for card in INFO["cards"]:
        if card["name"] == "glow":
            glow(image, card["px"])
    fade_edges(image)
    image = image.resize(SIZE, Image.LANCZOS)
    # Colour bleeds under the transparent edges, so filtering never darkens a silhouette.
    solid = image.copy()
    for _ in range(4):
        solid = Image.alpha_composite(solid.filter(ImageFilter.MaxFilter(3)), solid)
    bled = solid.copy()
    bled.putalpha(image.getchannel("A"))
    bled.save(OUT / "street-cards.png", optimize=True)
    print("CARDS", OUT / "street-cards.png")


main()
