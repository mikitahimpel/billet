"""Writes the placement catalog both sides read: the app's (DecorCatalog.generated.swift) and the room's
(decor-catalog.ts), from the hand-made pieces below and the JSON next to each prop model in
apps/ios/Nooki/Resources/Shop. Run it after a prop is added; CI's formatters check the output.

    python3 tools/decor-lod/catalog.py
    swift format format --in-place --configuration .swift-format packages/ios/features/Sources/DecorInterface/DecorCatalog.generated.swift
    pnpm exec oxfmt packages/contracts/domain/src/decor-catalog.ts
"""

import glob
import json
import os

root = os.path.join(os.path.dirname(__file__), "..", "..")
shop = os.path.join(root, "apps/ios/Nooki/Resources/Shop")

# The room is about 0.4 of real size (its walls are 0.8 m high), so a piece is sized for that: id, the model
# measure that is fixed (width or height), its size in the room in metres, mount and whether it lies flat. The
# prop models from the PC are drawn at half of real size, so they are brought down by PROP_SCALE.
HAND = [
    ("armchair", "width", 0.36, "floor", False),
    ("bookcase", "height", 0.5, "floor", False),
    ("donutbed", "width", 0.4, "floor", False),
    ("lamp", "height", 0.26, "floor", False),
    ("lantern", "height", 0.15, "floor", False),
    ("monstera", "height", 0.45, "floor", False),
    ("print", "height", 0.22, "wall", False),
    ("rug", "width", 0.6, "floor", True),
    ("teatable", "height", 0.18, "floor", False),
    ("tower", "height", 0.55, "floor", False),
    ("yarn", "width", 0.08, "floor", False),
    ("mouse", "height", 0.05, "floor", False),
]
PROP_SCALE = 0.8

# What she cannot walk through is a plant's pot, not its leaves.
CORE = {"monstera": (0.2, 0.2)}

bounds = json.load(open(os.path.join(os.path.dirname(__file__), "bounds.json")))


def measured(asset, fit, size):
    """The piece's width, depth and height in the room, from its model's bounds scaled to `size` on `fit`."""
    b = bounds[asset]
    k = size / b["width" if fit == "width" else "height"]
    return round(b["width"] * k, 3), round(b["depth"] * k, 3), round(b["height"] * k, 3)


# What the cat does with a piece: curl up on it, sit at it, scratch it, sit in it.
CAT = {"armchair": "sofa", "armchair-round": "sofa", "beanbag": "sofa", "beanbag-sage": "sofa",
       "beanbag-terracotta": "sofa", "windowseat": "windowSeat", "scratchpost": "post", "catbed": "catBed",
       "donutbed": "catBed", "box": "crate", "tunnel": "crate"}

# The room's own furniture, the pieces every pair owns: id, name, what the cat lies on (rest), width, depth
# and height in metres, flat, and the grid cell its middle stands in. Sizes and middles are the room's built
# furniture (apps/ios/Tools/make_room.py) rounded to the 5 cm grid, so a new room reads as it always did.
BASE = [
    ("base-windowseat", "Window seat", False, 0.19, 0.42, 0.26, False, (-8, 0)),
    ("base-nightstand", "Nightstand", False, 0.21, 0.23, 0.18, False, (-8, 7)),
    ("base-plant", "Corner plant", False, 0.12, 0.12, 0.3, False, (-8, -8)),
    ("base-lamp", "Stool and lamp", False, 0.124, 0.124, 0.35, False, (-2, -8)),
    ("base-cattree", "Cat tree", False, 0.2, 0.2, 0.4, False, (7, -7)),
    ("base-bowls", "Bowls", False, 0.2, 0.09, 0.04, False, (2, -7)),
    ("base-donutbed", "Cat bed", True, 0.38, 0.38, 0.14, False, (1, -1)),
    ("base-basket", "Yarn basket", False, 0.16, 0.16, 0.09, False, (7, 7)),
    ("base-books", "Books", False, 0.12, 0.1, 0.05, False, (4, 8)),
    ("base-rug", "Rug", False, 0.64, 0.64, 0.02, True, (0, 1)),
]

# The Bedroom's own furniture, built in code by CityRoomScene from CityLayout: the same columns. Middles are
# CityLayout's rounded to the 5 cm grid (a test holds them within a cell). The window, its sill and the wall
# fittings stay fixed, so they are not here. Sizes are the turn-0 footprint: the dresser runs along the wall.
BEDROOM = [
    ("base-bedroom-bed", "Bed", True, 0.76, 0.36, 0.2, False, (1, -3)),
    ("base-bedroom-nightstand", "Nightstand and lamp", False, 0.13, 0.13, 0.28, False, (-8, -3)),
    ("base-bedroom-dresser", "Dresser", False, 0.12, 0.24, 0.2, False, (-8, 6)),
    ("base-bedroom-catbed", "Cat bed", True, 0.23, 0.23, 0.06, False, (5, 6)),
    ("base-bedroom-rug", "Rug", False, 0.44, 0.44, 0.02, True, (1, 5)),
    ("base-bedroom-bowls", "Bowls", False, 0.08, 0.14, 0.03, False, (8, 2)),
    ("base-bedroom-slippers", "Slippers", False, 0.12, 0.1, 0.04, False, (-4, 2)),
    ("base-bedroom-books", "Books", False, 0.1, 0.08, 0.05, False, (-4, 8)),
    ("base-bedroom-mouse", "Toy mouse", False, 0.05, 0.1, 0.03, False, (0, 5)),
]

items = []
for id, name, rest, width, depth, height, flat, (u, v) in BASE + BEDROOM:
    bedroom = id.startswith("base-bedroom-")
    items.append(dict(id=id, model="", asset="" if bedroom else "Base_" + id[len("base-"):], fit="width", size=width, mount="floor", width=width, depth=depth,
                      flat=flat, height=height, base=True, name=name, rest=rest, home=(u, v), space="bedroom" if bedroom else "living"))
for id, fit, size, mount, flat in HAND:
    width, depth, height = measured(f"Decor_{id}", fit, size)
    width, depth = CORE.get(id, (width, depth))
    items.append(dict(id=id, model=f"Item_{id}", asset=f"Decor_{id}", fit=fit, size=size, mount=mount,
                      width=width, depth=0.0 if mount == "wall" else depth, flat=flat, height=height))
for path in sorted(glob.glob(os.path.join(shop, "Item_*.json"))):
    j = json.load(open(path))
    size = round(j["size_m"] * PROP_SCALE, 3)
    width, depth, height = measured(f"Item_{j['id']}", j["fit"], size)
    items.append(dict(id=j["id"], model=f"Item_{j['id']}", asset=f"Item_{j['id']}", fit=j["fit"], size=size,
                      mount=j["mount"], width=width, depth=0.0 if j["mount"] == "wall" else depth,
                      flat=j["kind"] == "FLAT" and j["mount"] == "floor", height=height))

swift = ["// Generated by tools/decor-lod/catalog.py. Do not edit.", "", "extension DecorItem {",
         "  static let catalog: [DecorItem] = ["]
for i in items:
    if i.get("base"):
        swift.append(
            f'    DecorItem(id: "{i["id"]}", model: "", assetName: "{i["asset"]}", fit: .width, size: {i["size"]}, '
            f'mount: .floor, width: {i["width"]}, depth: {i["depth"]}, '
            f'isFlat: {"true" if i["flat"] else "false"}, height: {i["height"]}, cat: nil, '
            f'base: BaseSpot(title: "{i["name"]}", u: {i["home"][0]}, v: {i["home"][1]}, '
            f'isRest: {"true" if i["rest"] else "false"}'
            f'{", space: .bedroom" if i["space"] == "bedroom" else ""})),')
        continue
    swift.append(
        f'    DecorItem(id: "{i["id"]}", model: "{i["model"]}", assetName: "{i["asset"]}", '
        f'fit: .{i["fit"]}, size: {i["size"]}, mount: .{i["mount"]}, width: {i["width"]}, '
        f'depth: {i["depth"]}, isFlat: {"true" if i["flat"] else "false"}, height: {i["height"]}, '
        f'cat: {"." + CAT[i["id"]] if i["id"] in CAT else "nil"}),')
swift += ["  ]", "}", ""]
open(os.path.join(root, "packages/ios/features/Sources/DecorInterface/DecorCatalog.generated.swift"), "w").write("\n".join(swift))

ts = ["// Generated by tools/decor-lod/catalog.py. Do not edit.", "",
      "export interface Footprint {", "  readonly width: number;", "  readonly depth: number;",
      '  readonly mount: "floor" | "wall";', "  readonly flat: boolean;",
      "  /** The cat lies on it: a bed or a sofa. */", "  readonly rest: boolean;", "}", "",
      "/** In metres across and into the room with no turn; a wall piece has its width only. */",
      "export const footprints: Readonly<Record<string, Footprint>> = {"]
for i in items:
    key = i["id"] if i["id"].isidentifier() else f'"{i["id"]}"'
    rest = i.get("rest", False) or CAT.get(i["id"]) in ("sofa", "catBed")
    ts.append(f'  {key}: {{ width: {i["width"]}, depth: {i["depth"]}, mount: "{i["mount"]}", '
              f'flat: {"true" if i["flat"] else "false"}, rest: {"true" if rest else "false"} }},')
ts += ["};", "",
       "/** Where each piece of the room's own furniture stands in a room nobody has arranged: grid cells of 5 cm. */",
       "export const baseHomes: Readonly<Record<string, { readonly u: number; readonly v: number }>> = {"]
for i in items:
    if i.get("base"):
        ts.append(f'  "{i["id"]}": {{ u: {i["home"][0]}, v: {i["home"][1]} }},')
ts += ["};", ""]
open(os.path.join(root, "packages/contracts/domain/src/decor-catalog.ts"), "w").write("\n".join(ts))
print(len(items), "pieces")
