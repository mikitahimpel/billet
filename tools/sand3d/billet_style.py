"""Billet's clay look for sand3d programs, taken from apps/ios/Tools/make_items.py and Scene/Kit.swift.

Units: millimetres while modelling (sand3d's default); `s3d.export` writes metres. Every item is built at real
size, Z up, front towards -Y, centred in X and Y with its base on z = 0: the pivot on the floor. The shop then
scales it so one measure (`ShopItem.Fit`) is the catalog size.

Look: rounded "clay" shapes, every sharp edge softened; one matte, non-metallic material per colour from the
Nooki palette; fabric gets a little sheen, nothing is glossy; emission only on light sources.
"""

import sand3d as s3d

# The Nooki palette, sRGB, as in make_items.py.
CREAM = "#f6e8d4"
OAT = "#e9d2b0"
HONEY = "#f2a65e"
TERRACOTTA = "#c8653f"
WOOD = "#b9784a"
WOOD_DARK = "#8a5434"
BLUSH = "#f4a7b4"
ROSE = "#e07b8e"
SAGE = "#8daa7e"
LEAF = "#5e8f5a"
LEAF_DARK = "#3f6e46"
SKY = "#9dbbf5"
INK = "#4a3a33"

# Fabric colourways: (body, cushion, accent pillow).
FABRICS = {
    "oat": (OAT, CREAM, BLUSH),
    "rose": ("#e8a3a8", "#f6d3cf", CREAM),
    "sage": (SAGE, "#c9d8b8", HONEY),
    "honey": (HONEY, "#f8d3a0", TERRACOTTA),
    "sky": (SKY, "#d6e2fb", CREAM),
    "terracotta": (TERRACOTTA, "#eab49a", OAT),
    "ink": ("#6d5a52", "#a99087", HONEY),
}

# Bevel radii (mm). The look is "soft as clay": a cushion's radius is about a third of its thinnest side.
SOFT = 80  # big upholstered blocks
PLUMP = 60  # cushions
BOARD = 12  # wooden boards and panels
TRIM = 6  # knobs, legs, small parts

# Roughness: matte everywhere (Kit.swift's Clay.matte uses 0.82).
MATTE = 0.82
CHALK = 1.0


def clay(ob, color, roughness=MATTE):
    """A matte, non-metallic, uncoated surface of `color`."""
    return s3d.material(ob, "plastic", color=color, roughness=roughness, metallic=0)


def cloth(ob, color):
    """Upholstery: matte with the fabric preset's soft sheen."""
    return s3d.material(ob, "fabric", color=color, roughness=0.9)


def wood(ob, color=WOOD):
    """Painted-looking wood: flat colour, no grain, like the rest of the room."""
    return s3d.material(ob, "plastic", color=color, roughness=0.75, metallic=0)


def soft(ob, r):
    """Round every sharp edge to radius `r`."""
    return s3d.soften(ob, r)


def tessellate(chord=1.0, turn_min=12, turn_max=32):
    """How finely curves are cut: at most `chord` mm off the true curve, `turn_min` to `turn_max` pieces a turn.

    sand3d's own setting (0.05 mm, 24 to 64) is for machined parts and gives about 3.7 times today's triangles on
    the armchair; clay shapes at phone size read the same at 1 mm. sand3d has no public knob for this, so it sets
    the module's values; call it before building.
    """
    from sand3d import _core

    _core.CHORD, _core.TURN_MIN, _core.TURN_MAX = chord, turn_min, turn_max
