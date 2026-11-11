"""Renders the kitchen corner the feed, water and brush games are played in, as two baked images.

  blender -b -P kitchen.py -- <out_dir> <wall|floor|look> [--samples 256] [--scale 1.0]

`wall` writes kitchen_wall.png: the wall seen straight on, orthographic, 1.0 m wide and 1.1 m high (1024x1126), with
the counter, the window, the shelf of jars, the utensil rail and the pendant lamp, for a vertical quad standing on the
floor. `floor` writes kitchen_floor.png: the boards seen from above, 1.2 m wide and 0.9 m deep (1024x768), the top of
the image at the wall, with the flat-weave rug and the counter's contact shadow, for a quad lying on the floor. Light and
occlusion are baked in; both are drawn unlit. `look` lays the two PNGs from <out_dir> on quads in the game's room and
renders them from the game's camera (TabletopRoom.framing) with a stand-in cat, to judge the whole corner.

Coordinates are Blender's (z up), in metres: the floor's centre is the origin, the wall's face is at y = WALL, the
viewer looks along +y. In the room (RealityKit) that is x = x, y = z + floor top, z = -y.
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT, MODE = argv[0], argv[1]


def option(name, default):
    return argv[argv.index(name) + 1] if name in argv else default


SAMPLES = int(option("--samples", 256))
SCALE = float(option("--scale", 1.0))

WALL_W, WALL_H = 1.0, 1.1
FLOOR_W, FLOOR_D = 1.2, 0.9
WALL = FLOOR_D / 2
# The rug's centre, in front of the image centre (toward the viewer): where the cat sits and eats.
RUG = (0.0, -0.05)
RUG_SIZE = (0.6, 0.4)
COUNTER_TOP = 0.255
BOARDS = [0xD4B896, 0xDABF9F, 0xCBAE8B, 0xDEC4A6, 0xCFB28F, 0xC4A682, 0xD7BB99]
COUNTER_DEPTH = 0.085

# The Living room's palette (DioramaScene Tone) and the kitchen's own.
CREAM = 0xF6E4C8
CREAM_LIGHT = 0xFBF1E3
WHITE = 0xFFF8EC
OAT = 0xE9C9A0
HONEY = 0xCF8E58
HONEY_LIGHT = 0xDBA06A
WOOD = 0xB46C3C
WOOD_DARK = 0x8C4F2B
TERRACOTTA = 0xD8653F
CLAY = 0xC7744A
BLUSH = 0xE9A98A
SAGE = 0x9DB08A
SAGE_LIGHT = 0xB3C3A0
LEAF = 0x93A86A
LEAF_DARK = 0x6F8A4E
MUSTARD = 0xF2C46E
CORK = 0xC9A27A
INK = 0x5B3A28

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
rng = random.Random(0x4B17)


def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgb(h):
    return tuple(lin(((h >> s) & 255) / 255) for s in (16, 8, 0))


_mats = {}


def material(color, rough=0.85, glow=0.0, glow_color=None):
    k = (color, rough, glow, glow_color)
    if k in _mats:
        return _mats[k]
    m = bpy.data.materials.new(f"m{len(_mats)}")
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb(color), 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Specular IOR Level"].default_value = 0.2
    if glow > 0:
        bsdf.inputs["Emission Color"].default_value = (*rgb(glow_color or color), 1)
        bsdf.inputs["Emission Strength"].default_value = glow
    _mats[k] = m
    return m


def link(name, mesh, at, mat, rot=(0, 0, 0), scale=(1, 1, 1), smooth=False):
    o = bpy.data.objects.new(name, mesh)
    o.location = at
    o.rotation_euler = rot
    o.scale = scale
    mesh.materials.append(mat)
    if smooth:
        for p in mesh.polygons:
            p.use_smooth = True
    scene.collection.objects.link(o)
    return o


def soften(o, width, segments=3):
    m = o.modifiers.new("b", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    o.data.polygons.foreach_set("use_smooth", [True] * len(o.data.polygons))
    if hasattr(o.data, "set_sharp_from_angle"):
        o.data.set_sharp_from_angle(angle=math.radians(40))
    return o


def box(size, at, color, bevel=0.004, rough=0.85, glow=0.0, rot=(0, 0, 0)):
    """A soft clay box; `at` is its centre."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    mesh = bpy.data.meshes.new("box")
    bm.to_mesh(mesh)
    bm.free()
    o = link("box", mesh, at, material(color, rough, glow), rot=rot)
    if bevel > 0:
        soften(o, min(bevel, min(size) * 0.45))
    return o


def cyl(radius, height, at, color, verts=16, bevel=0.002, rough=0.85, axis="z", radius2=None, glow=0.0):
    """A soft cylinder (a cone with `radius2`); `at` is its centre."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=radius, radius2=radius if radius2 is None else radius2,
                          depth=height)
    mesh = bpy.data.meshes.new("cyl")
    bm.to_mesh(mesh)
    bm.free()
    rot = {"z": (0, 0, 0), "x": (0, math.pi / 2, 0), "y": (math.pi / 2, 0, 0)}[axis]
    o = link("cyl", mesh, at, material(color, rough, glow), rot=rot)
    if bevel > 0:
        soften(o, min(bevel, radius * 0.4, height * 0.4))
    return o


def ball(radius, at, color, scale=(1, 1, 1), rough=0.85, glow=0.0, subdivisions=2, glow_color=None):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    mesh = bpy.data.meshes.new("ball")
    bm.to_mesh(mesh)
    bm.free()
    return link("ball", mesh, at, material(color, rough, glow, glow_color), scale=scale, smooth=True)


def dome(radius, at, color, depth=0.5, rough=0.8):
    """The top half of a ball, open at the bottom, with a thin wall: a lamp shade or a bowl turned over."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=radius)
    for v in [v for v in bm.verts if v.co.z < -1e-4]:
        bm.verts.remove(v)
    mesh = bpy.data.meshes.new("dome")
    bm.to_mesh(mesh)
    bm.free()
    o = link("dome", mesh, at, material(color, rough), scale=(1, 1, depth * 2), smooth=True)
    m = o.modifiers.new("s", "SOLIDIFY")
    m.thickness = 0.004
    return o


def tube_loop(a, b, r, at, color, seg=72, ring=8, rough=1.0, squash=0.55, twist=0.18):
    """A soft tube round an ellipse with semi-axes a and b, lying flat: a whisk's wire loop once stood up."""
    bm = bmesh.new()
    rows = []
    for i in range(seg):
        t = 2 * math.pi * i / seg
        cx, cy = a * math.cos(t), b * math.sin(t)
        nx, ny = b * math.cos(t), a * math.sin(t)
        n = math.hypot(nx, ny)
        nx, ny = nx / n, ny / n
        wobble = twist * r * math.sin(t * seg / 3)
        row = []
        for j in range(ring):
            u = 2 * math.pi * j / ring
            rr = r + wobble * 0.3
            row.append(bm.verts.new((cx + nx * rr * math.cos(u), cy + ny * rr * math.cos(u),
                                     (r + rr * math.sin(u)) * squash)))
        rows.append(row)
    for i in range(seg):
        for j in range(ring):
            bm.faces.new((rows[i][j], rows[(i + 1) % seg][j], rows[(i + 1) % seg][(j + 1) % ring],
                          rows[i][(j + 1) % ring]))
    mesh = bpy.data.meshes.new("coil")
    bm.to_mesh(mesh)
    bm.free()
    return link("coil", mesh, at, material(color, rough), smooth=True)


def curtain(x0, x1, top, bottom, y, color, folds):
    """A gathered panel, its folds along x; `y` is its middle."""
    nx, nz = 48, 8
    verts, faces = [], []
    for k in range(nz + 1):
        z = top + (bottom - top) * k / nz
        flare = 1 + 0.15 * k / nz
        for i in range(nx + 1):
            t = i / nx
            x = x0 + (x1 - x0) * t
            d = 0.006 * flare * math.sin(t * folds * 2 * math.pi)
            verts.append((x, y + d, z))
    for k in range(nz):
        for i in range(nx):
            a = k * (nx + 1) + i
            faces.append((a, a + 1, a + nx + 2, a + nx + 1))
    mesh = bpy.data.meshes.new("curtain")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    o = link("curtain", mesh, (0, 0, 0), material(color, 1.0), smooth=True)
    m = o.modifiers.new("s", "SOLIDIFY")
    m.thickness = 0.004
    return o


def leaf(root, yaw, rise, droop, length, width, color, curl=0.25, rows=16, ring=10):
    """A thick clay leaf blade from `root`: pointed at the tip, narrow at the stalk, gently troughed.

    `yaw` turns it round z (0 points along +x), `rise` is the stalk's angle above the horizontal and `droop` how far
    the blade bends down by the tip, both in radians.
    """
    side = Vector((-math.sin(yaw), math.cos(yaw), 0))
    out = Vector((math.cos(yaw), math.sin(yaw), 0))
    up = Vector((0, 0, 1))
    bm = bmesh.new()
    spine, p, step = [], Vector(root), length / rows
    for k in range(rows + 1):
        u = k / rows
        a = rise - droop * u * u
        t = out * math.cos(a) + up * math.sin(a)
        spine.append((u, p.copy(), t))
        p += t * step
    loops = []
    for u, c, t in spine[:-1]:
        w = width * max(0.12, math.sin(math.pi * u ** 0.8) ** 0.75)
        thick = 0.0035 * (1 - 0.6 * u)
        normal = t.cross(side).normalized()
        if normal.z < 0:
            normal = -normal
        loop = []
        for j in range(ring):
            q = 2 * math.pi * j / ring
            cq, sq = math.cos(q), math.sin(q)
            loop.append(bm.verts.new(c + side * (w * cq) + normal * (thick * sq + curl * w * cq * cq)))
        loops.append(loop)
    tip = bm.verts.new(spine[-1][1])
    stalk = bm.verts.new(spine[0][1])
    for la, lb in zip(loops, loops[1:]):
        for j in range(ring):
            bm.faces.new((la[j], la[(j + 1) % ring], lb[(j + 1) % ring], lb[j]))
    for j in range(ring):
        bm.faces.new((loops[-1][j], loops[-1][(j + 1) % ring], tip))
        bm.faces.new((loops[0][(j + 1) % ring], loops[0][j], stalk))
    mesh = bpy.data.meshes.new("leaf")
    bm.to_mesh(mesh)
    bm.free()
    o = link("leaf", mesh, (0, 0, 0), material(color, 0.75), smooth=True)
    o.modifiers.new("s", "SUBSURF").levels = 1
    return o


def plant(x, base, y):
    """A terracotta pot with eight broad clay leaf blades in two greens, fanning up and drooping at the tips."""
    cyl(0.04, 0.06, (x, y, base + 0.03), CLAY, radius2=0.048, verts=24, bevel=0.004)
    cyl(0.053, 0.014, (x, y, base + 0.066), TERRACOTTA, verts=24, bevel=0.004)
    cyl(0.045, 0.004, (x, y, base + 0.072), 0x6B4A35, verts=24, bevel=0.001, rough=1.0)
    soil = base + 0.072
    # (yaw, rise, droop, length, width, tone): the back ones stand up, the side and front ones lean out and droop.
    leaves = [
        (math.radians(100), math.radians(82), math.radians(40), 0.1, 0.022, LEAF_DARK),
        (math.radians(55), math.radians(68), math.radians(70), 0.105, 0.024, LEAF),
        (math.radians(135), math.radians(66), math.radians(75), 0.1, 0.023, LEAF),
        (math.radians(10), math.radians(44), math.radians(80), 0.095, 0.023, LEAF_DARK),
        (math.radians(172), math.radians(46), math.radians(80), 0.095, 0.023, LEAF_DARK),
        (math.radians(-40), math.radians(40), math.radians(85), 0.08, 0.021, LEAF),
        (math.radians(-145), math.radians(38), math.radians(85), 0.08, 0.021, LEAF),
        (math.radians(-90), math.radians(52), math.radians(80), 0.07, 0.02, LEAF_DARK),
        (math.radians(80), math.radians(60), math.radians(70), 0.09, 0.021, 0xA3B56F),
    ]
    for yaw, rise, droop, length, width, tone in leaves:
        r = 0.008
        root = (x + r * math.cos(yaw), y + r * math.sin(yaw), soil - 0.004)
        leaf(root, yaw, rise, droop, length, width, tone)


def fruit_bowl(x, base, y):
    o = dome(0.075, (x, y, base + 0.038), CREAM_LIGHT, depth=0.5, rough=0.7)
    o.rotation_euler = (math.pi, 0, 0)
    cyl(0.03, 0.008, (x, y, base + 0.004), OAT, verts=20, bevel=0.002)
    cyl(0.077, 0.006, (x, y, base + 0.038), BLUSH, verts=32, bevel=0.002, radius2=0.077)
    for dx, dz, r, tone in [(-0.032, 0.05, 0.026, 0xF2A65E), (0.03, 0.052, 0.025, 0xF09A50), (0.0, 0.07, 0.027, 0xF2A65E),
                            (-0.005, 0.045, 0.022, 0xE0554A)]:
        ball(r, (x + dx, y - 0.01, base + dz), tone, rough=0.6)
    # A pear leaning on the oranges.
    ball(0.02, (x + 0.055, y - 0.02, base + 0.07), 0xB9C46A, scale=(1, 1, 1.25), rough=0.6)
    cyl(0.003, 0.016, (x + 0.057, y - 0.02, base + 0.102), WOOD_DARK, verts=6, bevel=0)


def cloths(x, base, y):
    """Three folded dish cloths, a little askew."""
    z = base
    for w, tone, stripe in [(0.11, SAGE, CREAM_LIGHT), (0.1, CREAM_LIGHT, TERRACOTTA), (0.095, BLUSH, CREAM_LIGHT)]:
        box((w, 0.07, 0.016), (x + rng.uniform(-0.004, 0.004), y, z + 0.008), tone, bevel=0.006, rough=1.0)
        box((0.012, 0.072, 0.0165), (x + w * 0.3, y, z + 0.008), stripe, bevel=0.004, rough=1.0)
        z += 0.016


def jar(x, base, y, r, h, body, lid):
    cyl(r, h, (x, y, base + h / 2), body, verts=20, bevel=0.006, rough=0.6)
    cyl(r * 0.92, 0.016, (x, y, base + h + 0.006), lid, verts=20, bevel=0.004, rough=1.0)
    cyl(r * 0.25, 0.006, (x, y, base + h + 0.016), CORK, verts=12, bevel=0.002, rough=1.0)
    box((r * 0.9, 0.002, min(h * 0.22, 0.018)), (x, y - r - 0.0005, base + h * 0.42), CREAM_LIGHT, bevel=0.002, rough=1.0)


def utensils(x0, x1, z, y):
    """A wooden rail with hooks, and a ladle, a whisk, a spatula and a small pan hanging from it."""
    cyl(0.005, x1 - x0, ((x0 + x1) / 2, y, z), WOOD, axis="x", verts=12, bevel=0.002)
    for xe in (x0, x1):
        cyl(0.008, 0.02, (xe, y + 0.01, z), WOOD_DARK, axis="y", verts=12, bevel=0.002)
    hooks = [x0 + (x1 - x0) * t for t in (0.15, 0.38, 0.6, 0.84)]
    for hx in hooks:
        cyl(0.0022, 0.02, (hx, y - 0.001, z - 0.012), INK, verts=6, bevel=0)
    # Ladle: handle and a bowl.
    h = hooks[0]
    cyl(0.0045, 0.12, (h, y, z - 0.082), HONEY, verts=8, bevel=0.002)
    ball(0.024, (h, y, z - 0.152), CREAM_LIGHT, scale=(1, 0.6, 0.75), rough=0.6)
    # Whisk: a handle and wire loops.
    h = hooks[1]
    cyl(0.006, 0.06, (h, y, z - 0.05), TERRACOTTA, verts=10, bevel=0.002)
    for s in (1.0, 0.55, 0.15):
        o = tube_loop(0.024 * s + 0.001, 0.045, 0.0016, (h, y, z - 0.125), 0xEFE4D6, seg=32, ring=6, rough=0.5,
                      squash=1.0, twist=0.0)
        o.rotation_euler = (math.pi / 2, 0, 0)
    # Spatula: handle and a rounded flat blade.
    h = hooks[2]
    cyl(0.0045, 0.11, (h, y, z - 0.077), HONEY_LIGHT, verts=8, bevel=0.002)
    box((0.04, 0.006, 0.05), (h, y, z - 0.152), SAGE, bevel=0.01, rough=0.7)
    # A small pan, face on, its handle up to the hook.
    h = hooks[3]
    cyl(0.006, 0.07, (h, y, z - 0.05), WOOD, verts=10, bevel=0.002)
    cyl(0.062, 0.016, (h, y + 0.006, z - 0.142), 0x6E5A50, axis="y", verts=32, bevel=0.004, rough=0.5)
    cyl(0.05, 0.01, (h, y - 0.0, z - 0.142), 0x85706A, axis="y", verts=32, bevel=0.003, rough=0.6)


def tiles(x0, x1, z0, z1, y):
    """A sage backsplash of small staggered tiles over pale grout."""
    box((x1 - x0, 0.006, z1 - z0), ((x0 + x1) / 2, y + 0.004, (z0 + z1) / 2), 0xE6DCC8, bevel=0.001, rough=1.0)
    tw, th, gap = 0.062, 0.031, 0.0035
    tones = [SAGE, SAGE_LIGHT, 0xA6B894, SAGE, 0x93A784]
    rows = int((z1 - z0) / th)
    for r in range(rows):
        z = z0 + gap / 2 + r * th + (th - gap) / 2
        off = tw / 2 if r % 2 else 0
        x = x0 - off
        while x < x1:
            a, b = max(x + gap / 2, x0), min(x + tw - gap / 2, x1)
            if b - a > 0.006:
                box((b - a, 0.006, th - gap), ((a + b) / 2, y, z), rng.choice(tones), bevel=0.0028, rough=0.55)
            x += tw


def counter():
    """The cupboard run along the whole wall: plinth, four cupboards with a drawer each, a cream top."""
    front = WALL - COUNTER_DEPTH
    yc = WALL - COUNTER_DEPTH / 2
    box((WALL_W + 0.3, COUNTER_DEPTH - 0.02, 0.03), (0, yc + 0.01, 0.015), WOOD_DARK, bevel=0.003)
    box((WALL_W + 0.3, COUNTER_DEPTH - 0.004, COUNTER_TOP - 0.05), (0, yc, 0.03 + (COUNTER_TOP - 0.05) / 2), HONEY,
        bevel=0.003)
    box((WALL_W + 0.32, COUNTER_DEPTH + 0.014, 0.022), (0, yc - 0.007, COUNTER_TOP - 0.011), CREAM_LIGHT, bevel=0.006,
        rough=0.6)
    w = 0.25
    for i in range(-3, 3):
        cx = (i + 0.5) * w
        tone = HONEY_LIGHT if i % 2 else 0xD69A64
        box((w - 0.008, 0.012, 0.048), (cx, front - 0.005, COUNTER_TOP - 0.022 - 0.03), tone, bevel=0.005)
        ball(0.0075, (cx, front - 0.013, COUNTER_TOP - 0.052), WOOD_DARK, rough=0.6)
        box((w - 0.008, 0.012, 0.128), (cx, front - 0.005, 0.032 + 0.068), tone, bevel=0.005)
        box((w - 0.05, 0.006, 0.09), (cx, front - 0.011, 0.032 + 0.068), HONEY, bevel=0.004)
        knob = cx + (0.09 if i % 2 else -0.09)
        ball(0.0085, (knob, front - 0.017, 0.032 + 0.1), CREAM_LIGHT, rough=0.5)


def window(cx, z0, w, h):
    """The window left of centre: deep frame, glowing panes, a sill, a café curtain and a little plant on the sill."""
    y = WALL
    box((w + 0.04, 0.02, h + 0.04), (cx, y - 0.004, z0 + h / 2), WHITE, bevel=0.006, rough=0.7)
    for dz in (-0.009, h + 0.009):
        box((w + 0.04, 0.014, 0.022), (cx, y - 0.02, z0 + dz), WHITE, bevel=0.005, rough=0.7)
    for dx in (-w / 2 - 0.009, w / 2 + 0.009):
        box((0.022, 0.014, h + 0.04), (cx + dx, y - 0.02, z0 + h / 2), WHITE, bevel=0.005, rough=0.7)
    # The sky through the glass: daylight, bright at the top, warming toward the sill.
    glass = bpy.data.materials.new("glass")
    glass.use_nodes = True
    nt = glass.node_tree
    nt.nodes.clear()
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    em = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(coord.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], em.inputs[0])
    nt.links.new(em.outputs[0], out.inputs[0])
    # Bottom to top: a soft green hill line, a warm haze over it, pale blue sky.
    stops = [(0.0, 0x9FBC88), (0.17, 0xB4CD98), (0.25, 0xFBF0D8), (0.45, 0xF1F2E6), (1.0, 0xBBD8EC)]
    ramp.color_ramp.elements[0].position, ramp.color_ramp.elements[1].position = stops[0][0], stops[-1][0]
    ramp.color_ramp.elements[0].color = (*rgb(stops[0][1]), 1)
    ramp.color_ramp.elements[1].color = (*rgb(stops[-1][1]), 1)
    for at, tone in stops[1:-1]:
        ramp.color_ramp.elements.new(at).color = (*rgb(tone), 1)
    em.inputs["Strength"].default_value = 1.05
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * (w - 0.02), v.co.y * 0.004, v.co.z * (h - 0.02)))
    mesh = bpy.data.meshes.new("glass")
    bm.to_mesh(mesh)
    bm.free()
    g = bpy.data.objects.new("glass", mesh)
    g.location = (cx, y - 0.016, z0 + h / 2)
    mesh.materials.append(glass)
    scene.collection.objects.link(g)
    # A glazing bar; the curtain rod hides where a cross bar would be.
    box((0.012, 0.012, h - 0.01), (cx, y - 0.02, z0 + h / 2), WHITE, bevel=0.003, rough=0.7)
    # Sill.
    box((w + 0.08, 0.05, 0.018), (cx, y - 0.025, z0 - 0.012), WHITE, bevel=0.006, rough=0.65)
    box((w + 0.02, 0.02, 0.012), (cx, y - 0.006, z0 - 0.026), 0xEADBC6, bevel=0.003)
    # Café curtain on a thin rod across the lower half, and a short valance at the top.
    rod = z0 + h * 0.55
    cyl(0.0035, w + 0.04, (cx, y - 0.04, rod), WOOD, axis="x", verts=10, bevel=0.001)
    for xe in (cx - w / 2 - 0.022, cx + w / 2 + 0.022):
        ball(0.007, (xe, y - 0.04, rod), WOOD_DARK)
    curtain(cx - w / 2 - 0.01, cx - 0.012, rod + 0.004, z0 + 0.03, y - 0.042, BLUSH, folds=5)
    curtain(cx + 0.012, cx + w / 2 + 0.01, rod + 0.004, z0 + 0.03, y - 0.042, BLUSH, folds=5)
    for xs in (cx - w / 2 - 0.01, cx + 0.012):
        box((cx - 0.012 - (cx - w / 2 - 0.01), 0.008, 0.012),
            (xs + (cx - 0.012 - (cx - w / 2 - 0.01)) / 2, y - 0.043, z0 + 0.032), CREAM_LIGHT, bevel=0.004, rough=1.0)
    curtain(cx - w / 2 - 0.03, cx + w / 2 + 0.03, z0 + h + 0.02, z0 + h - 0.045, y - 0.04, BLUSH, folds=9)
    box((w + 0.07, 0.01, 0.01), (cx, y - 0.04, z0 + h + 0.024), WOOD, bevel=0.003)
    # A tiny cactus pot on the sill.
    s = z0 - 0.003
    cyl(0.018, 0.026, (cx - w / 2 + 0.05, y - 0.03, s + 0.013), CREAM_LIGHT, radius2=0.021, verts=16, bevel=0.002)
    ball(0.016, (cx - w / 2 + 0.05, y - 0.03, s + 0.04), LEAF, scale=(1, 1, 1.4), rough=0.9)
    ball(0.006, (cx - w / 2 + 0.05, y - 0.035, s + 0.064), 0xF0B7B0, rough=0.9)


def shelf(x0, x1, z, y):
    box((x1 - x0, 0.07, 0.018), ((x0 + x1) / 2, y - 0.035, z), HONEY, bevel=0.005)
    for xb in (x0 + 0.04, x1 - 0.04):
        box((0.014, 0.05, 0.04), (xb, y - 0.025, z - 0.028), WOOD, bevel=0.004)
    base = z + 0.009
    jy = y - 0.035
    jars = [(0.028, 0.10, TERRACOTTA, CORK), (0.024, 0.075, CREAM_LIGHT, CORK), (0.032, 0.12, SAGE, CORK),
            (0.022, 0.06, MUSTARD, CORK), (0.026, 0.085, CLAY, CORK)]
    x = x0 + 0.045
    for r, h, body, lid in jars:
        jar(x, base, jy, r, h, body, lid)
        x += r * 2 + 0.018
    # A little leaning recipe book at the end.
    box((0.016, 0.05, 0.085), (x1 - 0.03, jy, base + 0.042), 0x6F8FB0, bevel=0.003, rot=(0, math.radians(-10), 0))


def pendant(x, z_bottom, y):
    """A round dome lamp on a cord from the top, lit: a warm bulb and the pool of light it throws."""
    cyl(0.0018, WALL_H + 0.1 - z_bottom - 0.08, (x, y, (WALL_H + 0.1 + z_bottom + 0.08) / 2), INK, verts=6, bevel=0)
    cyl(0.012, 0.022, (x, y, z_bottom + 0.088), MUSTARD, verts=16, bevel=0.003)
    dome(0.085, (x, y, z_bottom + 0.012), MUSTARD, depth=0.42, rough=0.7)
    cyl(0.086, 0.008, (x, y, z_bottom + 0.012), 0xE5AE57, verts=32, bevel=0.002)
    ball(0.024, (x, y, z_bottom + 0.004), 0xFFF1D0, glow=18.0, glow_color=0xFFD9A0, rough=0.5)
    inner = bpy.data.lights.new("bulb", "POINT")
    inner.energy = 1.8 * SCALE
    inner.color = rgb(0xFFC98A)
    inner.shadow_soft_size = 0.03
    o = bpy.data.objects.new("bulb", inner)
    o.location = (x, y, z_bottom - 0.01)
    scene.collection.objects.link(o)
    pool = bpy.data.lights.new("pool", "SPOT")
    pool.energy = 6.5 * SCALE
    pool.color = rgb(0xFFC27A)
    pool.spot_size = math.radians(110)
    pool.spot_blend = 1.0
    pool.shadow_soft_size = 0.08
    o = bpy.data.objects.new("pool", pool)
    o.location = (x, y, z_bottom - 0.005)
    o.rotation_euler = (math.radians(180), 0, 0)
    scene.collection.objects.link(o)


def room_shell():
    """The wall, the counter, the window and everything on the wall."""
    box((WALL_W + 0.4, 0.04, WALL_H + 0.3), (0, WALL + 0.02, (WALL_H + 0.3) / 2 - 0.05), CREAM, bevel=0, rough=0.95)
    # A cream picture rail along the top, under which the wall is a shade warmer.
    box((WALL_W + 0.4, 0.012, 0.014), (0, WALL - 0.006, WALL_H - 0.075), CREAM_LIGHT, bevel=0.004)
    tiles(-WALL_W / 2 - 0.2, WALL_W / 2 + 0.2, COUNTER_TOP, 0.43, WALL - 0.004)
    box((WALL_W + 0.4, 0.012, 0.012), (0, WALL - 0.01, 0.436), CREAM_LIGHT, bevel=0.004)
    counter()
    top = COUNTER_TOP
    yc = WALL - COUNTER_DEPTH / 2
    fruit_bowl(-0.37, top, yc)
    cloths(-0.215, top, yc + 0.005)
    plant(0.40, top, yc)
    # A cutting board leaning on the tiles beside the plant.
    box((0.1, 0.012, 0.15), (0.28, WALL - 0.016, top + 0.075), HONEY_LIGHT, bevel=0.01, rot=(math.radians(-6), 0, 0))
    cyl(0.009, 0.014, (0.28, WALL - 0.024, top + 0.128), WOOD, axis="y", verts=12, bevel=0.002)
    window(-0.19, 0.47, 0.29, 0.33)
    shelf(0.05, 0.45, 0.71, WALL)
    utensils(0.09, 0.43, 0.6, WALL - 0.02)
    pendant(0.12, 0.89, WALL - 0.17)


def floor():
    """Honey boards along the depth, staggered, over a dark gap, with a soft vignette toward the edges."""
    box((FLOOR_W + 0.4, FLOOR_D + 0.4, 0.01), (0, 0, -0.006), 0x9C6E48, bevel=0, rough=1.0)
    vignette = floor_material()
    pw, gap = 0.08, 0.002
    tones = BOARDS
    y_lo, y_hi = -FLOOR_D / 2 - 0.2, WALL
    n = int((FLOOR_W + 0.4) / pw)
    for i in range(n):
        x = -(FLOOR_W + 0.4) / 2 + (i + 0.5) * pw
        y = y_lo - rng.uniform(0, 0.4)
        while y < y_hi:
            length = rng.uniform(0.55, 1.0)
            a, b = max(y + gap / 2, y_lo), min(y + length - gap / 2, y_hi + 0.05)
            if b - a > 0.02:
                o = box((pw - gap, b - a, 0.008), (x, (a + b) / 2, -0.004), rng.choice(tones), bevel=0.0025, rough=0.8)
                o.data.materials[0] = vignette[o.data.materials[0].name]
            y += length


def floor_material():
    """Each board tone, darkened softly within 0.14 m of the image's edges, with a faint grain."""
    out = {}
    tones = BOARDS
    for tone in tones:
        base = material(tone, 0.8)
        m = base.copy()
        m.name = "v" + base.name
        nt = m.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(geo.outputs["Position"], sep.inputs[0])

        def edge(axis, half):
            ab = nt.nodes.new("ShaderNodeMath")
            ab.operation = "ABSOLUTE"
            nt.links.new(sep.outputs[axis], ab.inputs[0])
            sub = nt.nodes.new("ShaderNodeMath")
            sub.operation = "SUBTRACT"
            sub.inputs[0].default_value = half
            nt.links.new(ab.outputs[0], sub.inputs[1])
            div = nt.nodes.new("ShaderNodeMath")
            div.operation = "DIVIDE"
            div.use_clamp = True
            div.inputs[1].default_value = 0.2
            nt.links.new(sub.outputs[0], div.inputs[0])
            return div

        ex, ey = edge("X", FLOOR_W / 2), edge("Y", FLOOR_D / 2)
        mn = nt.nodes.new("ShaderNodeMath")
        mn.operation = "MULTIPLY"
        nt.links.new(ex.outputs[0], mn.inputs[0])
        nt.links.new(ey.outputs[0], mn.inputs[1])
        smooth = nt.nodes.new("ShaderNodeMapRange")
        smooth.interpolation_type = "SMOOTHSTEP"
        smooth.inputs["To Min"].default_value = 0.62
        # The counter's contact shadow: the boards darken over the last 8 cm before the image's top edge.
        back = nt.nodes.new("ShaderNodeMath")
        back.operation = "SUBTRACT"
        back.inputs[0].default_value = FLOOR_D / 2
        nt.links.new(sep.outputs["Y"], back.inputs[1])
        reach = nt.nodes.new("ShaderNodeMath")
        reach.operation = "DIVIDE"
        reach.use_clamp = True
        reach.inputs[1].default_value = 0.08
        nt.links.new(back.outputs[0], reach.inputs[0])
        both = nt.nodes.new("ShaderNodeMath")
        both.operation = "MULTIPLY"
        nt.links.new(mn.outputs[0], both.inputs[0])
        nt.links.new(reach.outputs[0], both.inputs[1])
        nt.links.new(both.outputs[0], smooth.inputs[0])
        grain = nt.nodes.new("ShaderNodeTexWave")
        grain.bands_direction = "Y"
        grain.inputs["Scale"].default_value = 3.0
        grain.inputs["Distortion"].default_value = 2.5
        grain.inputs["Detail"].default_value = 1.0
        gmap = nt.nodes.new("ShaderNodeMapRange")
        gmap.inputs["To Min"].default_value = 0.965
        gmap.inputs["To Max"].default_value = 1.0
        nt.links.new(grain.outputs["Fac"], gmap.inputs[0])
        mul1 = nt.nodes.new("ShaderNodeMix")
        mul1.data_type = "RGBA"
        mul1.blend_type = "MULTIPLY"
        mul1.inputs[0].default_value = 1.0
        mul1.inputs[6].default_value = (*rgb(tone), 1)
        nt.links.new(smooth.outputs[0], mul1.inputs[7])
        mul2 = nt.nodes.new("ShaderNodeMix")
        mul2.data_type = "RGBA"
        mul2.blend_type = "MULTIPLY"
        mul2.inputs[0].default_value = 1.0
        nt.links.new(mul1.outputs[2], mul2.inputs[6])
        nt.links.new(gmap.outputs[0], mul2.inputs[7])
        nt.links.new(mul2.outputs[2], bsdf.inputs["Base Color"])
        out[base.name] = m
    return out


def woven(color):
    """A matt cloth material whose colour wavers by a few percent in fine streaks along x, like a flat weave."""
    base = material(color, 1.0)
    m = base.copy()
    m.name = "w" + base.name
    nt = m.node_tree
    coord = nt.nodes.new("ShaderNodeTexCoord")
    stretch = nt.nodes.new("ShaderNodeMapping")
    stretch.inputs["Scale"].default_value = (1.0, 7.0, 1.0)
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 40.0
    noise.inputs["Detail"].default_value = 3.0
    shade = nt.nodes.new("ShaderNodeMapRange")
    shade.inputs["From Min"].default_value = 0.3
    shade.inputs["From Max"].default_value = 0.7
    shade.inputs["To Min"].default_value = 0.94
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1.0
    mix.inputs[6].default_value = (*rgb(color), 1)
    nt.links.new(coord.outputs["Object"], stretch.inputs[0])
    nt.links.new(stretch.outputs[0], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], shade.inputs[0])
    nt.links.new(shade.outputs[0], mix.inputs[7])
    nt.links.new(mix.outputs[2], nt.nodes["Principled BSDF"].inputs["Base Color"])
    return m


def rounded_rect(hw, hh, r, inset=0.0, per_corner=10):
    """The outline of a rectangle with half sizes hw, hh and corner radius r, shrunk by `inset`, counter-clockwise.

    Every inset gives the same number of points at the same angles, so two outlines can be bridged into a band.
    """
    pts = []
    for cx, cy, a0 in ((hw - r, hh - r, 0), (-hw + r, hh - r, 90), (-hw + r, -hh + r, 180), (hw - r, -hh + r, 270)):
        for k in range(per_corner + 1):
            a = math.radians(a0 + 90 * k / per_corner)
            pts.append((cx + (r - inset) * math.cos(a), cy + (r - inset) * math.sin(a)))
    return pts


def flat_band(outer, inner, z0, thick, mat, bevel=0.002):
    """A flat piece between two outlines (the whole shape when `inner` is None), `thick` high from z0."""
    bm = bmesh.new()
    lo = [bm.verts.new((x, y, z0)) for x, y in outer]
    hi = [bm.verts.new((x, y, z0 + thick)) for x, y in outer]
    n = len(outer)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    if inner is None:
        bm.faces.new(hi)
    else:
        ilo = [bm.verts.new((x, y, z0)) for x, y in inner]
        ihi = [bm.verts.new((x, y, z0 + thick)) for x, y in inner]
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((hi[i], hi[j], ihi[j], ihi[i]))
            bm.faces.new((ihi[i], ihi[j], ilo[j], ilo[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("band")
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new("band", mesh)
    o.location = (RUG[0], RUG[1], 0)
    mesh.materials.append(mat)
    scene.collection.objects.link(o)
    soften(o, bevel, segments=3)
    return o


def rug():
    """A cream flat-weave rug with rounded corners: an oat border band edged in sage, a few tonal stripes toward each
    end and a short fringe on the two short sides. The middle stays plain for the cat and her bowls."""
    hw, hh = RUG_SIZE[0] / 2, RUG_SIZE[1] / 2
    r = 0.06
    flat_band(rounded_rect(hw, hh, r), None, 0.0, 0.0045, woven(0xF1E4CF), bevel=0.0025)
    flat_band(rounded_rect(hw, hh, r, 0.012), rounded_rect(hw, hh, r, 0.042), 0.0045, 0.0012, woven(0xD6B48A),
              bevel=0.001)
    flat_band(rounded_rect(hw, hh, r, 0.05), rounded_rect(hw, hh, r, 0.056), 0.0045, 0.0012, woven(SAGE),
              bevel=0.0006)
    inner = hh - 0.056
    for s in (-1, 1):
        for dx, w, tone in ((0.085, 0.014, 0xEAD3B2), (0.108, 0.006, 0xE7B79C), (0.124, 0.014, 0xEAD3B2)):
            box((w, 2 * inner - 0.012, 0.0014), (RUG[0] + s * (hw - dx), RUG[1], 0.0048), 0xEAD3B2, bevel=0.0006,
                rough=1.0).data.materials[0] = woven(tone)
        for k in range(23):
            fy = -hh + r + (2 * hh - 2 * r) * k / 22
            cyl(0.0022, 0.022, (RUG[0] + s * (hw + 0.009), RUG[1] + fy, 0.002), CREAM_LIGHT, axis="x", verts=6,
                bevel=0.0008, rough=1.0)


def lights():
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*rgb(0xFFEBD2), 1)
    bg.inputs["Strength"].default_value = 0.55 * SCALE
    scene.world = w
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 1.9 * SCALE
    sun.color = rgb(0xFFE6C8)
    sun.angle = math.radians(32)
    o = bpy.data.objects.new("sun", sun)
    # From the front, high and from the left, like the window side of the Living room.
    d = Vector((-0.45, -1.0, 1.1)).normalized()
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    scene.collection.objects.link(o)
    # Daylight spilling from the window onto the counter and the sill.
    spill = bpy.data.lights.new("spill", "AREA")
    spill.energy = 1.6 * SCALE
    spill.color = rgb(0xFFF4E2)
    spill.size = 0.3
    o = bpy.data.objects.new("spill", spill)
    o.location = (-0.19, WALL - 0.03, 0.64)
    o.rotation_euler = (math.radians(-60), 0, 0)
    o.visible_camera = False
    scene.collection.objects.link(o)


def setup_cycles():
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for kind in ("OPTIX", "CUDA", "METAL"):
        try:
            prefs.compute_device_type = kind
        except TypeError:
            continue
        prefs.get_devices()
        if any(d.type == kind for d in prefs.devices):
            for d in prefs.devices:
                d.use = d.type == kind
            scene.cycles.device = "GPU"
            break
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 6
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"


def ortho(at, rot, scale, fit, w, h):
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = scale
    cam.sensor_fit = fit
    o = bpy.data.objects.new("cam", cam)
    o.location = at
    o.rotation_euler = rot
    scene.collection.objects.link(o)
    scene.camera = o
    scene.render.resolution_x, scene.render.resolution_y = w, h


def render(name, transparent):
    scene.render.film_transparent = transparent
    scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("[kitchen] wrote", scene.render.filepath, flush=True)


def hide_from_camera(objects):
    for o in objects:
        o.visible_camera = False


def build_wall():
    before = set(bpy.data.objects)
    floor()
    rug()
    hide_from_camera(set(bpy.data.objects) - before)
    room_shell()
    lights()
    ortho((0, -3, WALL_H / 2), (math.pi / 2, 0, 0), WALL_H, "VERTICAL", 1024, 1126)
    render("kitchen_wall", transparent=True)


def build_floor():
    # The wall layer's plane is the counter's front, so here the counter stands just behind the image's top edge and
    # only its soft contact shadow reaches the boards.
    before = set(bpy.data.objects)
    room_shell()
    shell = set(bpy.data.objects) - before
    hide_from_camera(shell)
    for o in shell:
        o.location.y += COUNTER_DEPTH
    floor()
    rug()
    lights()
    ortho((0, 0, 3), (0, 0, 0), FLOOR_W, "HORIZONTAL", 1024, 768)
    render("kitchen_floor", transparent=False)


def image_plane(path, size, at, rot):
    img = bpy.data.images.load(path)
    m = bpy.data.materials.new(os.path.basename(path))
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Linear"
    em = nt.nodes.new("ShaderNodeEmission")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mixer = nt.nodes.new("ShaderNodeMixShader")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(tex.outputs["Color"], em.inputs["Color"])
    nt.links.new(tex.outputs["Alpha"], mixer.inputs[0])
    nt.links.new(tr.outputs[0], mixer.inputs[1])
    nt.links.new(em.outputs[0], mixer.inputs[2])
    nt.links.new(mixer.outputs[0], out.inputs[0])
    bpy.ops.mesh.primitive_plane_add(size=1, location=at, rotation=rot)
    o = bpy.context.active_object
    o.scale = (size[0], size[1], 1)
    o.data.materials.append(m)
    return o


def build_look():
    """The two layers on quads in the game's room, seen from TabletopRoom's camera, with a stand-in cat."""
    top = 0.02
    image_plane(os.path.join(OUT, "kitchen_floor.png"), (FLOOR_W, FLOOR_D), (0, 0, top), (0, 0, 0))
    image_plane(os.path.join(OUT, "kitchen_wall.png"), (WALL_W, WALL_H), (0, WALL + 0.001, top + WALL_H / 2),
                (math.pi / 2, 0, 0))
    # A stand-in cat, the game's 0.68 scale (about 0.2 m to the ears), sitting where buildCat puts her.
    cx, cy = 0.0, 0.13
    fur = 0xE9A35E
    ball(0.075, (cx, cy, top + 0.07), fur, scale=(0.9, 0.8, 1.0))
    ball(0.055, (cx, cy - 0.02, top + 0.165), fur)
    for s in (-1, 1):
        cyl(0.018, 0.035, (cx + s * 0.03, cy - 0.02, top + 0.215), fur, radius2=0.002, verts=8, bevel=0)
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (*rgb(0xF4E2CA), 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    scene.world = w
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 2.0
    sun.angle = math.radians(30)
    o = bpy.data.objects.new("sun", sun)
    o.rotation_euler = Vector((-0.6, -0.8, 1.5)).normalized().to_track_quat("Z", "Y").to_euler()
    scene.collection.objects.link(o)
    # TabletopRoom.framing: target [0, 0.07, 0.02], direction normalize([0.1, 0.3, 1]), distance 3.2, 22 deg vertical.
    target = Vector((0, 0.01, 0.07))
    direction = Vector((0.1, -1.0, 0.3)).normalized()
    cam = bpy.data.cameras.new("cam")
    cam.sensor_fit = "VERTICAL"
    cam.angle = math.radians(22)
    o = bpy.data.objects.new("cam", cam)
    scene.collection.objects.link(o)
    scene.camera = o
    scene.render.resolution_x, scene.render.resolution_y = 590, 1278
    for name, distance, fov in (("look_game", 3.2, 22), ("look_wide", 3.2, 40)):
        cam.angle = math.radians(fov)
        o.location = target + direction * distance
        o.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
        render(name, transparent=False)


os.makedirs(OUT, exist_ok=True)
setup_cycles()
{"wall": build_wall, "floor": build_floor, "look": build_look}[MODE]()
