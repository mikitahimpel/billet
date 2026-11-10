"""Renders the Bedroom window's suburb diorama as transparent layers, one time of day per run.

  blender -b -P city_diorama.py -- <out_dir> <day|dusk|night> [--samples 96] [--width 1280] [--only far,mid,street,sky,cars]

Writes <out_dir>/<layer>_<time>.png for the layers sky, far, mid and street (1280x704, the window's 1.82:1 with a
parallax margin round it), and cars_<time>.png (a sprite sheet). `bake.sh` turns the PNGs into WebP and writes
diorama.json. The look is Billet's clay: matte, bevelled boxes in the Room's palette, flat facets, light baked by Cycles.
The city is a grid of straight buildings along a street with one cross street; nothing in it is random but the seed.
"""

import math
import os
import random
import sys
import time

import bmesh
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT, TIME = argv[0], argv[1]


def option(name, default):
    return argv[argv.index(name) + 1] if name in argv else default


SAMPLES = int(option("--samples", 96))
WIDTH = int(option("--width", 1280))
HEIGHT = WIDTH * 11 // 20
ONLY = option("--only", "sky,far,mid,street,cars").split(",")

# Where the cross street opens in the row of buildings, and the street the cars drive on (world units, metres).
GAP_X = 3.0
GAP_W = 6.0
ROAD = (-9.0, 2.0)
LANES = {"far": -1.5, "near": -5.5}

# The Room's palette (Kit.swift Tone) plus the town's own.
WALLS = [0xF6E4C8, 0xE8D2B2, 0xF2C79A, 0xE9A98A, 0xD8653F, 0xB9C9A2, 0xF0B7B0, 0xCFE0DE, 0xF4D58A]
ROOFS = [0xB46C3C, 0x8C4F2B, 0xA85A3A, 0x7A5A4A, 0xC8653F]
WOOD = 0xB46C3C
LEAF = [0x93A86A, 0x6F8A4E, 0x7FA35F, 0xA3B56F]
ROAD_C, SIDEWALK_C, CURB_C, STRIPE_C = 0x8A7F78, 0xE6D4B8, 0xCDB89A, 0xFAF1DF
CAR_PAINTS = [0xE0554A, 0xE3B45C, 0x6F8FB0, 0x7C9A7E, 0xF2E6D2, 0xD8653F]

# Per time of day: sky top / horizon, sun colour / strength / elevation / azimuth (degrees), ambient, share of lit
# windows, lamps on, window glow, haze strength at distance.
LOOKS = {
    "day": dict(top=0x8FB4F0, horizon=0xFBE9CE, sun=0xFFE9D0, sun_strength=4.0, elev=42, azim=-50, ambient=1.0,
                lit=0.0, lamps=False, glow=0, haze=0.5),
    "dusk": dict(top=0x6C6FB4, horizon=0xF7A872, sun=0xFFB27A, sun_strength=2.0, elev=9, azim=-70, ambient=0.8,
                 lit=0.4, lamps=True, glow=5, haze=0.5),
    "night": dict(top=0x141A3E, horizon=0x3A3C78, sun=0xA9B9FF, sun_strength=0.35, elev=38, azim=-55, ambient=0.28,
                  lit=0.62, lamps=True, glow=8, haze=0.45),
}
LOOK = LOOKS[TIME]


def log(*args):
    print("[diorama]", *args, flush=True)


def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgb(h):
    return tuple(lin(((h >> s) & 255) / 255) for s in (16, 8, 0))


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


HORIZON = rgb(LOOK["horizon"])

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
random.seed(0xC17)
LIT = random.Random(0x11A)
T0 = time.time()

_mats = {}


def material(color, rough=0.82, haze=0.0, glow=0.0, glow_color=None, key=None):
    """One shared matte material per colour and haze, so the file stays small."""
    k = (key or color, rough, round(haze, 2), glow, glow_color)
    if k in _mats:
        return _mats[k]
    m = bpy.data.materials.new(f"m{len(_mats)}")
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    base = mix(rgb(color), HORIZON, haze * LOOK["haze"])
    bsdf.inputs["Base Color"].default_value = (*base, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Specular IOR Level"].default_value = 0.15
    if glow > 0:
        bsdf.inputs["Emission Color"].default_value = (*rgb(glow_color or color), 1)
        bsdf.inputs["Emission Strength"].default_value = glow
    _mats[k] = m
    return m


COLLECTIONS = {}


def collection(name):
    if name not in COLLECTIONS:
        c = bpy.data.collections.new(name)
        scene.collection.children.link(c)
        COLLECTIONS[name] = c
    return COLLECTIONS[name]


def add(layer, name, mesh, at, mat, rot=(0, 0, 0), scale=(1, 1, 1)):
    o = bpy.data.objects.new(name, mesh)
    o.location = at
    o.rotation_euler = rot
    o.scale = scale
    mesh.materials.append(mat)
    collection(layer).objects.link(o)
    return o


def box(layer, size, at, mat, bevel=0.12, rot=0.0):
    """A bevelled clay box; `at` is its base centre (x, y, z of the bottom)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    mesh = bpy.data.meshes.new("box")
    bm.to_mesh(mesh)
    bm.free()
    o = add(layer, "box", mesh, (at[0], at[1], at[2] + size[2] / 2), mat, rot=(0, 0, rot))
    if bevel > 0:
        m = o.modifiers.new("b", "BEVEL")
        m.width = min(bevel, min(size) * 0.45)
        m.segments = 2
    return o


def cyl(layer, radius, height, at, mat, verts=8, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=radius, radius2=radius, depth=height)
    mesh = bpy.data.meshes.new("cyl")
    bm.to_mesh(mesh)
    bm.free()
    return add(layer, "cyl", mesh, (at[0], at[1], at[2] + height / 2), mat)


def blob(layer, radius, at, mat, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    mesh = bpy.data.meshes.new("blob")
    bm.to_mesh(mesh)
    bm.free()
    return add(layer, "blob", mesh, at, mat, scale=scale)


def window_glass(haze, lit):
    if lit and LOOK["glow"] > 0:
        warm = LIT.random() < 0.8
        return material(0xFFD27A if warm else 0xCFE6FF, haze=haze * 0.5, glow=LOOK["glow"] * LIT.uniform(0.6, 1.0),
                        glow_color=0xFFC070 if warm else 0xBFD8FF, key=("lit", warm, LIT.randint(0, 3)))
    sky = 0x9DB4C8 if TIME == "day" else (0x6F7396 if TIME == "dusk" else 0x1E2447)
    return material(sky, rough=0.25, haze=haze, key=("glass", TIME))


def prism(layer, size, at, mat, ridge="x", overhang=0.5):
    """A gabled roof: `size` is (width, depth, rise); the ridge runs along `ridge`; `at` is the base centre."""
    w, d, h = size[0] + overhang * 2, size[1] + overhang * 2, size[2]
    if ridge == "x":
        v = [(-w / 2, -d / 2, 0), (w / 2, -d / 2, 0), (w / 2, d / 2, 0), (-w / 2, d / 2, 0), (-w / 2, 0, h), (w / 2, 0, h)]
        f = [(0, 1, 5, 4), (2, 3, 4, 5), (0, 4, 3), (1, 2, 5), (0, 3, 2, 1)]
    else:
        v = [(-w / 2, -d / 2, 0), (w / 2, -d / 2, 0), (w / 2, d / 2, 0), (-w / 2, d / 2, 0), (0, -d / 2, h), (0, d / 2, h)]
        f = [(0, 4, 5, 3), (1, 2, 5, 4), (0, 1, 4), (3, 5, 2), (0, 3, 2, 1)]
    mesh = bpy.data.meshes.new("roof")
    mesh.from_pydata(v, [], f)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    return add(layer, "roof", mesh, at, mat)


def windows(layer, x, front, z, cols, pitch, haze, shutters, lit_bonus=0.0):
    glass_trim = material(0xFBF1DE, haze=haze)
    for c in range(cols):
        cx = x + (c - (cols - 1) / 2) * pitch
        lit = LIT.random() < LOOK["lit"] + lit_bonus
        box(layer, (1.1, 0.1, 1.5), (cx, front - 0.04, z), window_glass(haze, lit), bevel=0.05)
        box(layer, (1.4, 0.14, 0.12), (cx, front - 0.07, z - 0.1), glass_trim, bevel=0.04)
        if shutters is not None:
            for s in (-1, 1):
                box(layer, (0.38, 0.09, 1.5), (cx + s * 0.8, front - 0.045, z), shutters, bevel=0.04)


def porch_light(layer, x, front, z, haze):
    bulb = material(0xFFE3A8, glow=10 if LOOK["lamps"] else 0.0, glow_color=0xFFC27A, key="porch")
    blob(layer, 0.14, (x + 0.75, front - 0.2, z), bulb)


def door(layer, x, front, haze, z=0.15):
    d = material(random.choice([0xB46C3C, 0x6F8FB0, 0x7C9A7E, 0xE0554A]), haze=haze)
    box(layer, (1.2, 0.12, 2.2), (x, front - 0.05, z), d, bevel=0.05)
    porch_light(layer, x, front, z + 1.8, haze)


def house(layer, cx, front, style, haze):
    """A detached house whose front faces the street (-y): `front` is the y of its front wall, `cx` its centre."""
    wall = material(random.choice([0xF6E4C8, 0xF4D58A, 0xB9C9A2, 0xF0B7B0, 0xCFE0DE, 0xF2C79A, 0xFBF1DE]), haze=haze)
    roof = material(random.choice(ROOFS), haze=haze)
    trim = material(0xFBF1DE, haze=haze)
    shutter = material(random.choice([0x6F8A4E, 0x4F6F86, 0x8C4F2B]), haze=haze)
    wood = material(0xE8D2B2, haze=haze)
    if style == "colonial":
        w, d, h = 9.0, 7.5, 6.0
        box(layer, (w, d, h), (cx, front + d / 2, 0.15), wall, bevel=0.2)
        prism(layer, (w, d, 2.6), (cx, front + d / 2, h + 0.15), roof, ridge="x", overhang=0.55)
        box(layer, (1.0, 1.0, 3.2), (cx + 3, front + d / 2 + 1.5, h + 0.2), material(0xA85A3A, haze=haze, key="brick"), bevel=0.08)
        windows(layer, cx, front, 3.5, 3, 2.7, haze, shutter)
        windows(layer, cx, front, 0.85, 3, 2.7, haze, shutter)
        door(layer, cx, front, haze)
        box(layer, (2.6, 1.3, 0.2), (cx, front - 0.65, 2.6), roof, bevel=0.05)
        for s in (-1, 1):
            box(layer, (0.18, 0.18, 2.5), (cx + s * 1.1, front - 1.15, 0.15), trim, bevel=0.03)
        box(layer, (2.8, 1.4, 0.2), (cx, front - 0.7, 0.0), material(0xCDB89A, haze=haze, key="step"), bevel=0.05)
    elif style == "ranch":
        w, d, h = 11.0, 6.5, 3.4
        box(layer, (w, d, h), (cx, front + d / 2, 0.15), wall, bevel=0.2)
        prism(layer, (w, d, 1.7), (cx, front + d / 2, h + 0.15), roof, ridge="x", overhang=0.6)
        windows(layer, cx + 2.2, front, 1.2, 2, 2.8, haze, shutter)
        door(layer, cx - 0.6, front, haze)
        box(layer, (3.0, 0.1, 2.3), (cx - 3.6, front - 0.05, 0.15), material(0xF3EDE4, haze=haze, key="garage"), bevel=0.06)
        for gy in (0.7, 1.4, 2.1):
            box(layer, (3.0, 0.12, 0.05), (cx - 3.6, front - 0.1, gy), trim, bevel=0.01)
        box(layer, (1.3, 0.8, 0.4), (cx + 4.2, front + 0.3, 0.15), material(0x93A86A, haze=haze, key="shrub"), bevel=0.2)
    else:
        two = style == "farmhouse"
        w, d, h = 8.0, 8.0, 5.6 if two else 3.6
        box(layer, (w, d, h), (cx, front + d / 2, 0.55), wall, bevel=0.2)
        prism(layer, (w, d, 3.0 if two else 2.6), (cx, front + d / 2, h + 0.55), roof, ridge="y", overhang=0.55)
        box(layer, (w + 0.6, 2.4, 0.4), (cx, front - 1.2, 0.15), wood, bevel=0.08)
        box(layer, (w + 0.8, 2.6, 0.22), (cx, front - 1.2, 2.9), roof, bevel=0.05)
        for px in (-w / 2 + 0.3, w / 2 - 0.3, -1.6, 1.6):
            box(layer, (0.2, 0.2, 2.35), (cx + px, front - 2.1, 0.55), trim, bevel=0.03)
        windows(layer, cx, front, 1.5, 2, 4.4, haze, None)
        door(layer, cx + 0.0, front, haze, z=0.55)
        if two:
            windows(layer, cx, front, 4.4, 2, 4.4, haze, shutter)


def tree(layer, x, y, scale=1.0, haze=0.0, tone=None):
    """A big rounded clay tree: a trunk and a heap of soft canopy blobs."""
    trunk = material(0x8C4F2B, haze=haze)
    colour = tone if tone is not None else random.choice(LEAF)
    leaf = material(colour, haze=haze)
    cyl(layer, 0.32 * scale, 3.2 * scale, (x, y, 0.15), trunk, verts=7)
    for dx, dy, dz, r in ((0, 0, 5.6, 2.8), (-1.9, 0.2, 4.7, 2.1), (1.9, -0.2, 4.9, 2.2), (0.3, -0.6, 7.2, 1.9)):
        blob(layer, r * scale, (x + dx * scale, y + dy, dz * scale), leaf, (1, 1, 0.92))


def bush(layer, x, y, r=0.9, tone=0x6F8A4E, haze=0.0):
    blob(layer, r, (x, y, r * 0.6), material(tone, haze=haze), (1.2, 1, 0.85))


def fence(layer, x0, x1, y, haze=0.0):
    white = material(0xFBF1DE, haze=haze)
    x = x0
    while x < x1:
        box(layer, (0.16, 0.06, 0.95), (x, y, 0.18), white, bevel=0.02)
        x += 0.45
    for z in (0.5, 0.95):
        box(layer, (x1 - x0, 0.06, 0.1), ((x0 + x1) / 2, y + 0.02, z), white, bevel=0.01)


def mailbox(layer, x, y):
    cyl(layer, 0.05, 1.0, (x, y, 0.18), material(0x4A3A33, key="post"), verts=5)
    box(layer, (0.5, 0.25, 0.28), (x, y, 1.15), material(0xE0554A, key="mail"), bevel=0.06)


def lamp(layer, x, y, haze=0.0):
    post = material(0x4A3A33, haze=haze)
    cyl(layer, 0.09, 5.0, (x, y, 0.15), post, verts=6)
    box(layer, (0.9, 0.08, 0.08), (x + 0.35, y, 5.0), post, bevel=0.02)
    bulb = material(0xFFE3A8, glow=12 if LOOK["lamps"] else 0.0, glow_color=0xFFC27A, key="bulb")
    blob(layer, 0.2, (x + 0.8, y, 5.0), bulb)
    if LOOK["lamps"]:
        light = bpy.data.lights.new(f"l{x}", "POINT")
        light.energy = 450
        light.color = rgb(0xFFC27A)
        light.shadow_soft_size = 0.4
        o = bpy.data.objects.new(f"l{x}", light)
        o.location = (x + 0.8, y, 4.7)
        collection(layer).objects.link(o)


def ground(layer, y0, y1, color, z=0.0, x=(-120, 120), haze=0.0, key=None):
    box(layer, (x[1] - x[0], y1 - y0, 0.3), ((x[0] + x[1]) / 2, (y0 + y1) / 2, z - 0.3), material(color, haze=haze, key=key), bevel=0)


LAWN = 0xA9BF78
STYLES = ["colonial", "ranch", "bungalow", "farmhouse", "colonial", "bungalow", "ranch", "colonial"]
LOTS = [-45.0, -32.0, -19.0, -6.0, 12.0, 25.0, 38.0, 51.0]


def build_far():
    """Low rolling hills, a church steeple, distant roofs and tree lines, hazed into the sky."""
    hill = (0xA9BF78, 0x93A86A, 0xB5C48A)
    for i, x in enumerate(range(-150, 160, 42)):
        blob("far", 38, (x, 120 + (i % 2) * 15, -2), material(hill[i % 3], haze=0.8), (1.3, 1, 0.55))
    for x in range(-80, 90, 9):
        tree("far", x + random.uniform(-2, 2), random.choice([80, 88]), random.choice([0.9, 1.1, 1.3]), haze=0.85)
    box("far", (4, 4, 9), (-24, 92, 0), material(0xF6E4C8, haze=0.85, key="church"), bevel=0.2)
    prism("far", (4, 4, 5), (-24, 92, 9), material(0xA85A3A, haze=0.85, key="spire"), ridge="x", overhang=0.1)
    box("far", (2.6, 2.6, 7), (-24, 92, 14), material(0xF6E4C8, haze=0.85, key="church"), bevel=0.1)
    prism("far", (2.6, 2.6, 6), (-24, 92, 21), material(0xA85A3A, haze=0.85, key="spire"), ridge="x", overhang=0.2)
    for x in (-60, -40, 6, 28, 52, 70):
        house("far", x, 62, random.choice(["colonial", "bungalow"]), haze=0.75)
    ground("far", 40, 160, 0xB5C48A, haze=0.8, key="farground")


def build_mid():
    """Two rows of houses on a grid of lots with the side street open between them, lawns and driveways."""
    ground("mid", 2, 60, LAWN, haze=0.15, key="lawn")
    gx0, gx1 = GAP_X - GAP_W / 2 + 0.3, GAP_X + GAP_W / 2 - 0.3
    box("mid", (gx1 - gx0, 58, 0.3), ((gx0 + gx1) / 2, 31, -0.28), material(ROAD_C, haze=0.15, key="side"), bevel=0)
    for i, x in enumerate(LOTS):
        style = STYLES[i]
        house("mid", x, 13.0, style, haze=0.1)
        drive_x = x - 3.6 if style == "ranch" else x + 5.2
        box("mid", (3.0, 11.0, 0.06), (drive_x, 2.4, 0.0), material(0xD9CDBB, haze=0.1, key="drive"), bevel=0.02)
        box("mid", (1.3, 8.6, 0.05), (x - 0.6 if style == "ranch" else x, 4.0, 0.0), material(0xD9CDBB, haze=0.1, key="path"), bevel=0.02)
        bush("mid", x - 4.7 if style != "ranch" else x + 5.6, 11.5, 0.9, haze=0.1)
        bush("mid", x + 4.6 if style != "ranch" else x - 6.4, 11.5, 0.8, 0x7FA35F, haze=0.1)
        if i % 2 == 0:
            car("mid", drive_x, 6.5, random.choice(CAR_PAINTS), kind="sedan", turn=True)
    for i, x in enumerate([-46, -33, -20, -7, 13, 26, 39]):
        house("mid", x + 1, 34.0, STYLES[(i + 3) % len(STYLES)], haze=0.4)
        tree("mid", x - 5.5, 31.0, 1.2, haze=0.4)
    for x in (-52, -12, 4, 19, 33, 47):
        tree("mid", x, 24.0, 1.25, haze=0.25)


def build_street():
    """The quiet road, its far sidewalk with picket fences, mailboxes, street lamps and big front-yard trees."""
    r0, r1 = ROAD
    ground("street", r0, r1, ROAD_C)
    ground("street", r1, 5.6, SIDEWALK_C, z=0.18)
    box("street", (240, 0.35, 0.22), (0, r1 + 0.1, 0), material(CURB_C), bevel=0.05)
    ground("street", -30, r0, SIDEWALK_C, z=0.18)
    box("street", (240, 0.35, 0.22), (0, r0 - 0.1, 0), material(CURB_C), bevel=0.05)
    gx0, gx1 = GAP_X - GAP_W / 2 + 0.3, GAP_X + GAP_W / 2 - 0.3
    cut = material(ROAD_C, key="cross")
    box("street", (gx1 - gx0, 4.5, 0.3), ((gx0 + gx1) / 2, r1 + 2.1, 0.0), cut, bevel=0)
    stripe = material(STRIPE_C)
    for i in range(-3, 4):
        box("street", (0.7, r1 - r0 - 0.8, 0.03), (GAP_X + i * 1.15, (r0 + r1) / 2, 0.0), stripe, bevel=0.02)
    for x in range(-90, 100, 6):
        if abs(x - GAP_X) > 6:
            box("street", (2.4, 0.18, 0.03), (x, (r0 + r1) / 2, 0.0), stripe, bevel=0.02)
    seam = material(0xCDB89A, key="seam")
    for x in range(-90, 100, 3):
        box("street", (0.06, 5.0, 0.02), (x, r0 - 2.6, 0.18), seam, bevel=0)
        box("street", (0.06, 3.6, 0.02), (x + 1.5, r1 + 1.9, 0.18), seam, bevel=0)
    for x0, x1 in ((-52, -1.0), (7.0, 56)):
        fence("street", x0, x1, 5.9)
    for lot, x in enumerate(LOTS):
        mailbox("street", x + 4.6, 5.0)
        tree("street", x + (-5.2 if lot % 2 else 5.4), 9.0, 1.0 + 0.1 * (lot % 3),
             tone=[0x93A86A, 0x7FA35F, 0xE3B45C, 0x6F8A4E][lot % 4] if lot != 2 else 0xD8653F)
    for lx in (-26, -1, 15, 30, 45):
        lamp("street", lx, r1 + 1.0)
    for bx, by in ((-14, -12), (9, -12), (28, -12)):
        box("street", (1.8, 0.7, 0.55), (bx, by, 0.18), material(WOOD), bevel=0.1)
        box("street", (1.8, 0.12, 0.5), (bx, by + 0.3, 0.7), material(WOOD), bevel=0.04)
    for hx in (-3, 19, 34):
        bush("street", hx, -11.0, 0.9, 0x93A86A)


CARS_X = 0.0


def car(layer, x, y, paint, kind="sedan", turn=False):
    """A clay car, side view along x with its front at +x; `turn` stands it end-on, nose towards the street."""
    body = material(paint)
    cabin = material(0xC9D6DE, rough=0.3, key="cabin")
    dark = material(0x4A3B36, key="tyre")
    parts = []
    if kind == "sedan":
        parts += [((4.2, 1.8, 0.8), 0, 0.35, body), ((2.3, 1.6, 0.75), -0.15, 1.05, body),
                  ((2.0, 1.66, 0.5), -0.15, 1.12, cabin)]
        length = 4.2
    elif kind == "suv":
        parts += [((4.6, 1.9, 1.1), 0, 0.35, body), ((3.4, 1.7, 0.9), -0.45, 1.3, body),
                  ((3.1, 1.76, 0.6), -0.45, 1.4, cabin)]
        length = 4.6
    else:
        parts += [((4.8, 1.9, 0.75), 0, 0.4, body), ((1.7, 1.7, 0.85), 0.9, 1.1, body),
                  ((1.45, 1.76, 0.5), 0.95, 1.2, cabin), ((2.4, 1.9, 0.4), -1.15, 1.1, material(0x8A7F78, key="bed"))]
        length = 4.8
    wheels = [(-length * 0.33, -0.8), (length * 0.33, -0.8), (-length * 0.33, 0.8), (length * 0.33, 0.8)]
    lamp_m = material(0xFFE3A8, glow=6 if LOOK["lamps"] else 0.0, glow_color=0xFFD890, key="head")
    tail_m = material(0xE0554A, glow=3 if LOOK["lamps"] else 0.0, glow_color=0xFF4030, key="tail")
    parts += [((0.12, 1.3, 0.25), length / 2, 0.6, lamp_m), ((0.12, 1.3, 0.25), -length / 2, 0.6, tail_m)]

    def place(px, py):
        return (x + py, y - px) if turn else (x + px, y + py)

    rot = -math.pi / 2 if turn else 0.0
    for size, px, pz, mat in parts:
        o = box(layer, size, (0, 0, pz), mat, bevel=0.25)
        o.location = (*place(px, 0.0), pz + size[2] / 2)
        o.rotation_euler[2] = rot
    for wx, wy in wheels:
        o = cyl(layer, 0.38, 0.28, (0, 0, 0), dark, verts=10)
        o.rotation_euler = (math.pi / 2, 0, rot)
        o.location = (*place(wx, wy), 0.38)


def build_cars():
    fill = bpy.data.lights.new("fill", "SUN")
    fill.energy = {"day": 0.0, "dusk": 0.9, "night": 1.6}[TIME]
    fill.color = rgb(0xFFD9B0 if TIME == "dusk" else 0xB8C4FF)
    fo = bpy.data.objects.new("fill", fill)
    fo.rotation_euler = (math.radians(70), 0, math.radians(20))
    collection("cars").objects.link(fo)
    kinds = ["sedan", "suv", "pickup", "sedan", "suv", "pickup"]
    for i, (paint, kind) in enumerate(zip(CAR_PAINTS, kinds)):
        car("cars", 6.0 * i, 0.0, paint, kind=kind)
    # A shadow catcher under the row so the sprites keep a soft contact shadow of their own.
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=100)
    mesh = bpy.data.meshes.new("catch")
    bm.to_mesh(mesh)
    bm.free()
    add("cars", "catch", mesh, (15, 0, 0), material(0xFFFFFF)).is_shadow_catcher = True


def world():
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    path = nt.nodes.new("ShaderNodeLightPath")
    flat = nt.nodes.new("ShaderNodeMix")
    flat.data_type = "RGBA"
    bg = nt.nodes.new("ShaderNodeBackground")
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(coord.outputs["Window"], sep.inputs[0])
    nt.links.new(sep.outputs["Y"], ramp.inputs[0])
    nt.links.new(path.outputs["Is Camera Ray"], flat.inputs[0])
    flat.inputs[6].default_value = (*mix(rgb(LOOK["horizon"]), rgb(LOOK["top"]), 0.5), 1)
    nt.links.new(ramp.outputs[0], flat.inputs[7])
    nt.links.new(flat.outputs[2], bg.inputs[0])
    nt.links.new(bg.outputs[0], out.inputs[0])
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (*rgb(LOOK["horizon"]), 1)
    ramp.color_ramp.elements[1].position = 1.0
    ramp.color_ramp.elements[1].color = (*rgb(LOOK["top"]), 1)
    bg.inputs["Strength"].default_value = LOOK["ambient"]
    scene.world = w
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = LOOK["sun_strength"]
    sun.color = rgb(LOOK["sun"])
    sun.angle = math.radians(6)
    o = bpy.data.objects.new("sun", sun)
    az, el = math.radians(LOOK["azim"]), math.radians(LOOK["elev"])
    d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    scene.collection.objects.link(o)


def camera(kind):
    cam = bpy.data.cameras.new("cam")
    o = bpy.data.objects.new("cam", cam)
    scene.collection.objects.link(o)
    scene.camera = o
    if kind == "cars":
        cam.type = "ORTHO"
        cam.ortho_scale = 6.0 * len(CAR_PAINTS)
        o.location = (6.0 * (len(CAR_PAINTS) - 1) / 2, -30, 1.4)
        o.rotation_euler = (math.pi / 2, 0, 0)
        cam.shift_y = 0.0
        return
    cam.lens = 30
    cam.sensor_width = 36
    cam.sensor_fit = "HORIZONTAL"
    cam.shift_y = -0.03
    o.location = (0, -28, 7.0)
    o.rotation_euler = (math.pi / 2, 0, 0)


def scene_info():
    """Where the lanes and the crossing land in the layers, as fractions of the image (origin top left)."""
    from bpy_extras.object_utils import world_to_camera_view

    bpy.context.view_layer.update()

    def at(x, y, z):
        p = world_to_camera_view(scene, scene.camera, Vector((x, y, z)))
        return p.x, 1 - p.y

    cell = WIDTH / len(CAR_PAINTS)
    lanes = []
    for name, y in LANES.items():
        (x0, ya), (x1, _) = at(-2.1, y, 0.0), at(2.1, y, 0.0)
        pixels_per_metre = (x1 - x0) * WIDTH / 4.2
        lanes.append({"name": name, "y": round(ya, 4), "scale": round(pixels_per_metre / (cell / 6.0), 4),
                      "direction": -1 if name == "far" else 1})
    half = 3 * 1.15 + 0.35
    cross = {"left": round(at(GAP_X - half, LANES["far"], 0)[0], 4), "right": round(at(GAP_X + half, LANES["far"], 0)[0], 4)}
    return {"lanes": lanes, "crossing": cross}


def render(name, layers, transparent=True, sky=False, width=None, height=None):
    for n, c in COLLECTIONS.items():
        c.hide_render = n not in layers
    scene.render.film_transparent = transparent
    scene.render.resolution_x = width or WIDTH
    scene.render.resolution_y = height or HEIGHT
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    log("wrote", scene.render.filepath, f"{time.time() - T0:.0f}s")


def setup_cycles():
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for kind in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = kind
        except TypeError:
            continue
        prefs.get_devices()
        gpus = [d for d in prefs.devices if d.type == kind]
        if gpus:
            for d in prefs.devices:
                d.use = d.type == kind
            scene.cycles.device = "GPU"
            break
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 4
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0


os.makedirs(OUT, exist_ok=True)
setup_cycles()
world()
if any(l in ONLY for l in ("far", "mid", "street", "sky")):
    build_far()
    log('far built', len(bpy.data.objects))
    build_mid()
    build_street()
    log('built', len(bpy.data.objects), f'{time.time() - T0:.0f}s')
    camera("street")
    import json
    json.dump(scene_info(), open(os.path.join(OUT, "info.json"), "w"))
    if "sky" in ONLY:
        for c in COLLECTIONS.values():
            c.hide_render = True
        render(f"sky_{TIME}", [], transparent=False)
    for layer in ("far", "mid", "street"):
        if layer in ONLY:
            render(f"{layer}_{TIME}", [layer])
if "cars" in ONLY:
    for c in list(COLLECTIONS.values()):
        for o in list(c.objects):
            bpy.data.objects.remove(o, do_unlink=True)
    build_cars()
    camera("cars")
    render(f"cars_{TIME}", ["cars"], width=WIDTH, height=WIDTH // len(CAR_PAINTS) * 1)
