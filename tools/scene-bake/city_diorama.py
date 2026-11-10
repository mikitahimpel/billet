"""Renders the City window's street diorama as transparent layers, one time of day per run.

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
GAP_X = 7.0
GAP_W = 7.0
ROAD = (-9.0, 2.0)
LANES = {"far": -1.5, "near": -5.5}

# The Room's palette (Kit.swift Tone) plus the town's own.
WALLS = [0xF6E4C8, 0xE8D2B2, 0xF2C79A, 0xE9A98A, 0xD8653F, 0xB9C9A2, 0xF0B7B0, 0xCFE0DE, 0xF4D58A]
ROOFS = [0xB46C3C, 0x8C4F2B, 0xA85A3A, 0x7A5A4A]
WOOD = 0xB46C3C
LEAF = [0x93A86A, 0x6F8A4E, 0x7FA35F]
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


def building(layer, x, y, w, d, h, haze, wall=None, rows=True, gable=None):
    """A building whose front (towards the street, -y) faces the camera: walls, roof cap, window grid, ground floor."""
    wall = wall if wall is not None else random.choice(WALLS)
    roof = random.choice(ROOFS)
    wm, rm = material(wall, haze=haze), material(roof, haze=haze)
    box(layer, (w, d, h), (x, y, 0), wm, bevel=0.18)
    box(layer, (w + 0.35, d + 0.35, 0.45), (x, y, h), rm, bevel=0.12)
    if gable:
        box(layer, (w * 0.5, d * 0.5, gable), (x, y, h + 0.45), rm, bevel=0.2)
    front = y - d / 2
    floors = max(int((h - 2.6) // 3.2), 0)
    cols = max(int((w - 1.0) // 2.2), 1)
    pitch = w / cols
    trim = material(0xFBF1DE, haze=haze)
    for f in range(floors):
        z = 3.1 + f * 3.2
        for c in range(cols):
            cx = x - w / 2 + pitch * (c + 0.5)
            lit = LIT.random() < LOOK["lit"]
            box(layer, (1.15, 0.1, 1.6), (cx, front - 0.04, z), window_glass(haze, lit), bevel=0.05)
            box(layer, (1.5, 0.16, 0.14), (cx, front - 0.08, z - 0.12), trim, bevel=0.04)
    ground_h = 2.7
    door = material(random.choice([WOOD, 0x6F8FB0, 0x7C9A7E]), haze=haze)
    awn = material(random.choice([0xD8653F, 0xE3B45C, 0x7C9A7E, 0xE0554A]), haze=haze)
    shop = random.random() < 0.6
    for c in range(cols):
        cx = x - w / 2 + pitch * (c + 0.5)
        if shop and c % 2 == 0 and w > 5:
            box(layer, (min(pitch * 0.85, 3.4), 0.1, 1.9), (cx, front - 0.04, 0.35), window_glass(haze, LIT.random() < LOOK["lit"] + 0.2), bevel=0.05)
            box(layer, (min(pitch * 0.95, 3.7), 0.9, 0.3), (cx, front - 0.5, 2.3), awn, bevel=0.1)
        else:
            box(layer, (1.2, 0.12, 2.1), (cx, front - 0.05, 0.12), door, bevel=0.05)
    box(layer, (w + 0.2, 0.2, 0.22), (x, front - 0.06, ground_h), trim, bevel=0.06)


def tree(layer, x, y, scale=1.0, haze=0.0):
    trunk = material(0x8C4F2B, haze=haze)
    leaf = material(random.choice(LEAF), haze=haze)
    cyl(layer, 0.18 * scale, 2.2 * scale, (x, y, 0.15), trunk, verts=6)
    blob(layer, 1.35 * scale, (x, y, 3.0 * scale), leaf, (1, 1, 1.05))
    blob(layer, 0.95 * scale, (x + 0.35 * scale, y - 0.1, 4.2 * scale), leaf)


def lamp(layer, x, y, haze=0.0):
    post = material(0x4A3A33, haze=haze)
    cyl(layer, 0.09, 5.2, (x, y, 0.15), post, verts=6)
    box(layer, (0.9, 0.08, 0.08), (x + 0.35, y, 5.2), post, bevel=0.02)
    bulb = material(0xFFE3A8, glow=12 if LOOK["lamps"] else 0.0, glow_color=0xFFC27A, key="bulb")
    blob(layer, 0.2, (x + 0.8, y, 5.2), bulb)
    if LOOK["lamps"]:
        light = bpy.data.lights.new(f"l{x}", "POINT")
        light.energy = 450
        light.color = rgb(0xFFC27A)
        light.shadow_soft_size = 0.4
        o = bpy.data.objects.new(f"l{x}", light)
        o.location = (x + 0.8, y, 4.9)
        collection(layer).objects.link(o)


def ground(layer, y0, y1, color, z=0.0, x=(-120, 120), haze=0.0):
    box(layer, (x[1] - x[0], y1 - y0, 0.3), ((x[0] + x[1]) / 2, (y0 + y1) / 2, z - 0.3), material(color, haze=haze), bevel=0)


# Far: a skyline of tall straight blocks, hazed towards the sky.
def build_far():
    x = -120
    while x < 120:
        w = random.choice([6, 8, 10, 12])
        h = random.choice([14, 20, 26, 34, 42])
        y = random.choice([80, 90, 100])
        building("far", x + w / 2, y, w, 10, h, haze=0.9, rows=True)
        x += w + random.choice([1, 2, 3])
    ground("far", 40, 140, 0xCFD8C8, haze=0.9)
    for tx in range(-80, 90, 17):
        tree("far", tx, 60, 2.2, haze=0.9)


# Mid: two rows of buildings across the street with the cross street open between them.
def build_mid():
    def row(y, d, hs, haze, skip_gap):
        x = -80.0
        while x < 90:
            w = random.choice([5.5, 7, 8.5, 10])
            if skip_gap and abs(x + w / 2 - GAP_X) < (GAP_W / 2 + w / 2):
                x = GAP_X + GAP_W / 2
                continue
            building("mid", x + w / 2, y, w, d, random.choice(hs), haze=haze)
            x += w + 0.25
    row(8.0, 9.0, [7, 9.5, 12, 15], 0.18, True)
    row(24.0, 12.0, [12, 16, 20, 26], 0.5, False)
    ground("mid", 2, 60, 0xD9C7A5, haze=0.3)
    ground("mid", 2, 60, 0xA79A8E, x=(GAP_X - GAP_W / 2 + 0.4, GAP_X + GAP_W / 2 - 0.4), z=0.01, haze=0.3)


# Street: the road and its far sidewalk with trees and lamp posts, the cross street's mouth and its crossing.
def build_street():
    r0, r1 = ROAD
    ground("street", r0, r1, ROAD_C)
    ground("street", r1, 8.0, SIDEWALK_C, z=0.18)
    box("street", (240, 0.35, 0.22), (0, r1 + 0.1, 0), material(CURB_C), bevel=0.05)
    ground("street", -30, r0, SIDEWALK_C, z=0.18)
    box("street", (240, 0.35, 0.22), (0, r0 - 0.1, 0), material(CURB_C), bevel=0.05)
    gx0, gx1 = GAP_X - GAP_W / 2 + 0.4, GAP_X + GAP_W / 2 - 0.4
    cut = material(ROAD_C, key="cross")
    box("street", (gx1 - gx0, 7.0, 0.3), ((gx0 + gx1) / 2, r1 + 3.5, 0.0), cut, bevel=0)
    stripe = material(STRIPE_C)
    for i in range(-3, 4):
        box("street", (0.7, r1 - r0 - 0.8, 0.03), (GAP_X + i * 1.15, (r0 + r1) / 2, 0.0), stripe, bevel=0.02)
    for x in range(-90, 100, 6):
        if abs(x - GAP_X) > 6:
            box("street", (2.4, 0.18, 0.03), (x, (r0 + r1) / 2, 0.0), stripe, bevel=0.02)
    seam = material(0xCDB89A, key="seam")
    for x in range(-90, 100, 3):
        box("street", (0.06, 5.0, 0.02), (x, r0 - 2.6, 0.18), seam, bevel=0)
        box("street", (0.06, 6.0, 0.02), (x + 1.5, r1 + 2.9, 0.18), seam, bevel=0)
    for bx, by in ((-14, -12), (9, -12), (28, -12)):
        box("street", (1.8, 0.7, 0.55), (bx, by, 0.18), material(WOOD), bevel=0.1)
        box("street", (1.8, 0.12, 0.5), (bx, by + 0.3, 0.7), material(WOOD), bevel=0.04)
    for hx in (-3, 19, 34):
        cyl("street", 0.55, 0.9, (hx, -11.0, 0.18), material(0x6F8A4E, key="bin"), verts=8)
        blob("street", 0.8, (hx, -11.0, 1.0), material(0x93A86A, key="bush"), (1.1, 1, 0.8))
    for tx in (-24, -13, 15, 26, 38):
        tree("street", tx, r1 + 2.6, 1.0)
    for lx in (-19, -3, 12, 30):
        lamp("street", lx, r1 + 1.0)
    for bx in (-17, 20, 33):
        box("street", (2.2, 0.6, 0.5), (bx, r1 + 4.3, 0.18), material(WOOD), bevel=0.08)


CARS_X = 0.0


def car(layer, x, y, paint):
    """A clay car, side view along x, base centred at (x, y)."""
    body = material(paint)
    cabin = material(0xC9D6DE, rough=0.3, key="cabin")
    dark = material(0x4A3B36, key="tyre")
    box(layer, (4.2, 1.8, 0.8), (x, y, 0.35), body, bevel=0.3)
    box(layer, (2.3, 1.6, 0.75), (x - 0.15, y, 1.05), body, bevel=0.32)
    box(layer, (2.0, 1.66, 0.5), (x - 0.15, y, 1.12), cabin, bevel=0.2)
    for wx in (-1.4, 1.4):
        for wy in (-0.8, 0.8):
            o = cyl(layer, 0.38, 0.28, (x + wx, y + wy, 0.0), dark, verts=10)
            o.rotation_euler[0] = math.pi / 2
            o.location = (x + wx, y + wy, 0.38)
    lamp_m = material(0xFFE3A8, glow=6 if LOOK["lamps"] else 0.0, glow_color=0xFFD890, key="head")
    tail_m = material(0xE0554A, glow=3 if LOOK["lamps"] else 0.0, glow_color=0xFF4030, key="tail")
    box(layer, (0.12, 1.3, 0.25), (x + 2.1, y, 0.6), lamp_m, bevel=0.04)
    box(layer, (0.12, 1.3, 0.25), (x - 2.1, y, 0.6), tail_m, bevel=0.04)


def build_cars():
    fill = bpy.data.lights.new("fill", "SUN")
    fill.energy = {"day": 0.0, "dusk": 0.9, "night": 1.6}[TIME]
    fill.color = rgb(0xFFD9B0 if TIME == "dusk" else 0xB8C4FF)
    fo = bpy.data.objects.new("fill", fill)
    fo.rotation_euler = (math.radians(70), 0, math.radians(20))
    collection("cars").objects.link(fo)
    for i, paint in enumerate(CAR_PAINTS):
        car("cars", 6.0 * i, 0.0, paint)
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
    o.location = (0, -44, 9.0)
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
