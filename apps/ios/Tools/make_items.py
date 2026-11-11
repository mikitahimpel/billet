"""Builds the shop catalog items in Blender: one USDZ model and one card thumbnail per item.

Run:
  blender -b --python Tools/make_items.py -- Nooki/Resources/Shop [item_id ...]

Writes Item_<id>.usdz and Item_<id>.png (1024², transparent, soft contact shadow) into the
output folder. Pass item ids to rebuild only those.

Style rules: rounded "clay" shapes from beveled primitives,
one matte material per color from the Ourio palette, emission only for light sources.

Blender space: Z up, items face -Y, units are meters at real-world size.
"""

import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:]
OUT_DIR = args[0]
ONLY = set(args[1:])
os.makedirs(OUT_DIR, exist_ok=True)


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgba(hex_color):
    return tuple(srgb_to_linear(((hex_color >> s) & 0xFF) / 255) for s in (16, 8, 0)) + (1.0,)


_materials = {}


def mat(hex_color, rough=0.8, emit=0.0, sheen=0.0):
    key = (hex_color, rough, emit, sheen)
    if key in _materials:
        return _materials[key]
    m = bpy.data.materials.new(f"M_{hex_color:06X}")
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = rgba(hex_color)
    bsdf.inputs["Roughness"].default_value = rough
    if emit:
        bsdf.inputs["Emission Color"].default_value = rgba(hex_color)
        bsdf.inputs["Emission Strength"].default_value = emit
    if sheen:
        # The soft rim light of fabric and felt.
        bsdf.inputs["Sheen Weight"].default_value = sheen
        bsdf.inputs["Sheen Tint"].default_value = (1, 1, 1, 1)
    _materials[key] = m
    return m


def _finish(obj, material, bevel=0.0, segments=4):
    obj.data.materials.append(material)
    if bevel:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE"
        mod.harden_normals = True
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def _scaled(obj, scale):
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def box(size, loc, material, bevel=0.01, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    return _finish(_scaled(bpy.context.object, size), material, bevel)


def cyl(radius, depth, loc, material, bevel=0.006, rot=(0, 0, 0), verts=48):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=verts, location=loc, rotation=rot)
    return _finish(bpy.context.object, material, bevel)


def cone(r1, r2, depth, loc, material, bevel=0.004, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r2, depth=depth, vertices=48, location=loc, rotation=rot)
    return _finish(bpy.context.object, material, bevel)


def ball(radius, loc, material, scale=(1, 1, 1), rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=48, ring_count=24, location=loc, rotation=rot)
    return _finish(_scaled(bpy.context.object, scale), material)


def ring(major, minor, loc, material, rot=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=72,
                                     minor_segments=24, location=loc, rotation=rot)
    return _finish(_scaled(bpy.context.object, scale), material)


def tube(points, radius, material):
    curve = bpy.data.curves.new("Tube", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 6
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for bp, p in zip(spline.bezier_points, points):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    obj = bpy.data.objects.new("Tube", curve)
    bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    return _finish(bpy.context.object, material)


def aligned(z_axis, x_hint=None):
    """Rotation taking local Z to `z_axis`, local X as close to `x_hint` as it can be."""
    z = Vector(z_axis).normalized()
    x = Vector(x_hint) if x_hint is not None else Vector((1, 0, 0) if abs(z.x) < 0.9 else (0, 1, 0))
    x = (x - z * x.dot(z)).normalized()
    return Matrix((x, z.cross(x), z)).transposed()


def put(obj, at, z_axis, x_hint=None):
    obj.matrix_world = Matrix.Translation(at) @ aligned(z_axis, x_hint).to_4x4()
    return obj


def rod(p0, p1, radius, material, bevel=0.003):
    p0, p1 = Vector(p0), Vector(p1)
    return put(cyl(radius, (p1 - p0).length, (0, 0, 0), material, bevel=bevel), (p0 + p1) / 2, p1 - p0)


def surface(fn, nu, nv, material, wrap_v=True, thickness=0.0):
    """A grid mesh through fn(s, t), s and t running 0-1; s always wraps around, t when `wrap_v`."""
    verts = [tuple(fn(i / nu, j / nv if wrap_v else j / (nv - 1))) for i in range(nu) for j in range(nv)]
    faces = []
    for i in range(nu):
        for j in range(nv if wrap_v else nv - 1):
            k = (i + 1) % nu
            faces.append((i * nv + j, k * nv + j, k * nv + (j + 1) % nv, i * nv + (j + 1) % nv))
    mesh = bpy.data.meshes.new("Surface")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("Surface", mesh)
    bpy.context.scene.collection.objects.link(obj)
    if thickness:
        mod = obj.modifiers.new("Solidify", "SOLIDIFY")
        mod.thickness = thickness
        mod.offset = 0
    return _finish(obj, material)


def flat(points, y, depth, material):
    """A flat shape facing -Y: the polygon `points` (x, z) at depth `y`, `depth` thick."""
    mesh = bpy.data.meshes.new("Flat")
    mesh.from_pydata([(x, y, z) for x, z in points], [], [list(range(len(points)))])
    mesh.update()
    obj = bpy.data.objects.new("Flat", mesh)
    bpy.context.scene.collection.objects.link(obj)
    mod = obj.modifiers.new("Solidify", "SOLIDIFY")
    mod.thickness = depth
    mod.offset = 0
    obj.data.materials.append(material)
    return obj


# ---------------------------------------------------------------- palette

CREAM = 0xF6E8D4
OAT = 0xE9D2B0
HONEY = 0xF2A65E
TERRACOTTA = 0xC8653F
WOOD = 0xB9784A
WOOD_DARK = 0x8A5434
BLUSH = 0xF4A7B4
ROSE = 0xE07B8E
SAGE = 0x8DAA7E
LEAF = 0x5E8F5A
LEAF_DARK = 0x3F6E46
SKY = 0x9DBBF5
INK = 0x4A3A33
GLOW = 0xFFE2AE


# ---------------------------------------------------------------- items


def cloud_armchair():
    body, cushion = mat(OAT), mat(CREAM)
    box((0.86, 0.74, 0.24), (0, 0, 0.2), body, bevel=0.08)
    box((0.62, 0.6, 0.14), (0, -0.04, 0.38), cushion, bevel=0.065)
    box((0.86, 0.22, 0.56), (0, 0.27, 0.56), body, bevel=0.1)
    for x in (-0.37, 0.37):
        box((0.2, 0.74, 0.4), (x, 0, 0.42), body, bevel=0.09)
        for y in (-0.28, 0.28):
            cyl(0.03, 0.1, (x, y, 0.05), mat(WOOD_DARK), bevel=0.01)
    ball(0.15, (0.12, 0.12, 0.56), mat(BLUSH), scale=(1.1, 0.45, 0.9), rot=(math.radians(-15), 0, 0))


def mushroom_lamp():
    cyl(0.16, 0.04, (0, 0, 0.02), mat(WOOD), bevel=0.015)
    cone(0.05, 0.035, 0.42, (0, 0, 0.25), mat(CREAM), bevel=0.0)
    ball(0.24, (0, 0, 0.47), mat(HONEY, rough=0.5, emit=1.4), scale=(1, 1, 0.55))
    cyl(0.235, 0.02, (0, 0, 0.46), mat(GLOW, emit=3.0), bevel=0.008)
    # Spots lie on the cap, the ellipsoid of radii (0.24, 0.24, 0.132) around z = 0.47.
    for angle, r, s in ((0.3, 0.17, 0.034), (2.2, 0.15, 0.03), (4.1, 0.18, 0.028), (5.3, 0.08, 0.026),
                        (1.2, 0.07, 0.022), (3.2, 0.2, 0.024)):
        x, y = r * math.cos(angle), r * math.sin(angle)
        dz = 0.132 * math.sqrt(1 - (r / 0.24) ** 2)
        normal = Vector((x / 0.24 ** 2, y / 0.24 ** 2, dz / 0.132 ** 2))
        put(ball(s, (0, 0, 0), mat(CREAM), scale=(1, 1, 0.28)), Vector((x, y, 0.47 + dz)), normal)


def monstera():
    pot = mat(TERRACOTTA)
    cone(0.17, 0.21, 0.3, (0, 0, 0.15), pot, bevel=0.01)
    ring(0.205, 0.025, (0, 0, 0.3), pot)
    cyl(0.19, 0.02, (0, 0, 0.29), mat(INK), bevel=0)
    leaves = [(0.0, 0.62, 25, LEAF), (1.2, 0.55, 40, LEAF_DARK), (2.4, 0.66, 30, LEAF),
              (3.5, 0.5, 45, LEAF_DARK), (4.6, 0.6, 35, LEAF), (5.6, 0.52, 42, LEAF_DARK)]
    for angle, height, tilt, color in leaves:
        d = Vector((math.cos(angle), math.sin(angle), 0))
        tip = Vector((0, 0, 0.3)) + d * 0.2 + Vector((0, 0, height))
        tube([(0, 0, 0.3), (d.x * 0.08, d.y * 0.08, 0.3 + height * 0.6), tuple(tip)], 0.008, mat(LEAF_DARK))
        ball(0.15, tuple(tip + d * 0.08), mat(color), scale=(1.0, 0.7, 0.12),
             rot=(0, math.radians(-tilt), angle))


def little_bookcase():
    wood = mat(WOOD)
    w, d, h = 0.7, 0.28, 0.86
    box((w, d, 0.04), (0, 0, 0.02), wood, bevel=0.012)
    box((w, d, 0.04), (0, 0, h), wood, bevel=0.012)
    box((w, 0.03, h), (0, d / 2 - 0.015, h / 2), mat(WOOD_DARK), bevel=0.008)
    for x in (-w / 2 + 0.02, w / 2 - 0.02):
        box((0.04, d, h), (x, 0, h / 2), wood, bevel=0.012)
    box((w - 0.04, d - 0.02, 0.03), (0, 0, h / 2), wood, bevel=0.008)
    colors = [ROSE, HONEY, SAGE, SKY, CREAM, TERRACOTTA, BLUSH]
    x = -w / 2 + 0.07
    for i, (width, height) in enumerate([(0.05, 0.3), (0.06, 0.34), (0.045, 0.28), (0.07, 0.32), (0.05, 0.3)]):
        box((width, 0.2, height), (x + width / 2, 0, 0.04 + height / 2), mat(colors[i]), bevel=0.008)
        x += width + 0.008
    box((0.06, 0.2, 0.26), (x + 0.04, 0, 0.17), mat(colors[5]), bevel=0.008, rot=(0, math.radians(-14), 0))
    for i, (width, height) in enumerate([(0.07, 0.24), (0.05, 0.3)]):
        box((width, 0.2, height), (-0.25 + i * 0.08, 0, h / 2 + 0.015 + height / 2), mat(colors[(i + 3) % 7]),
            bevel=0.008)
    ball(0.07, (0.15, 0, h / 2 + 0.09), mat(OAT), scale=(1, 1, 0.9))
    cyl(0.07, 0.1, (0.2, 0, h + 0.07), mat(TERRACOTTA), bevel=0.01)
    for a in range(5):
        ang = a * 1.25
        ball(0.05, (0.2 + 0.04 * math.cos(ang), 0.04 * math.sin(ang), h + 0.15), mat(LEAF), scale=(1, 1, 0.7))


def woven_rug():
    cyl(0.6, 0.03, (0, 0, 0.015), mat(OAT, rough=1), bevel=0.012)
    for r, color in ([(0.5, HONEY), (0.38, CREAM), (0.26, BLUSH), (0.14, HONEY)]):
        ring(r, 0.022, (0, 0, 0.03), mat(color, rough=1), scale=(1, 1, 0.45))
    for k in range(24):
        a = k / 24 * math.tau
        ball(0.025, (0.62 * math.cos(a), 0.62 * math.sin(a), 0.015), mat(OAT, rough=1), scale=(1.2, 1.2, 0.5))


def yarn_ball():
    random.seed(4)
    ball(0.155, (0, 0, 0.16), mat(0xD06A7E, rough=1, sheen=0.5))
    # Strands wound every which way over the core.
    for _ in range(30):
        ring(0.153 + random.random() * 0.006, 0.0075, (0, 0, 0.16), mat(ROSE, rough=1, sheen=0.5),
             rot=(random.uniform(0, math.tau), random.uniform(0, math.tau), random.uniform(0, math.tau)))
    # The loose end runs down to the floor and lies there.
    tube([(0.11, -0.1, 0.06), (0.19, -0.18, 0.012), (0.3, -0.15, 0.009), (0.4, -0.26, 0.009), (0.5, -0.22, 0.009)],
         0.009, mat(ROSE, rough=1, sheen=0.5))
    ball(0.012, (0.505, -0.22, 0.01), mat(ROSE, rough=1, sheen=0.5))
    # Two knitting needles pushed in crosswise, a wooden knob on each.
    center = Vector((0, 0, 0.16))
    for direction in (Vector((0.5, 0.25, 0.83)), Vector((-0.35, 0.45, 0.82))):
        d = direction.normalized()
        rod(center - d * 0.05, center + d * 0.34, 0.008, mat(WOOD), bevel=0.002)
        ball(0.018, tuple(center + d * 0.345), mat(WOOD_DARK))


def toy_mouse():
    grey = mat(0xB9B2AE)
    ball(0.12, (0, 0, 0.09), grey, scale=(0.75, 1.15, 0.72))
    ball(0.035, (0, -0.135, 0.085), grey)
    ball(0.016, (0, -0.172, 0.085), mat(ROSE))
    for x in (-0.055, 0.055):
        ball(0.05, (x, -0.07, 0.17), grey, scale=(1, 0.35, 1))
        ball(0.036, (x, -0.087, 0.17), mat(BLUSH), scale=(1, 0.2, 1))
        ball(0.011, (x * 0.55, -0.15, 0.115), mat(INK, rough=0.3))
    # The tail curls away along the floor.
    tube([(0, 0.13, 0.05), (0.04, 0.22, 0.01), (-0.02, 0.3, 0.008), (0.05, 0.37, 0.008), (0.11, 0.35, 0.008)],
         0.007, mat(ROSE))
    for side in (-1, 1):
        for k in (-1, 0, 1):
            rod((side * 0.02, -0.16, 0.088), (side * 0.11, -0.18 + 0.01 * k, 0.088 + 0.022 * k), 0.0016,
                mat(INK, rough=0.4), bevel=0)


def cat_tower():
    rope, carpet = mat(0xD9B98C, rough=1), mat(CREAM, rough=1)
    box((0.6, 0.5, 0.06), (0, 0, 0.03), carpet, bevel=0.025)
    for x, y, top in ((-0.15, 0.08, 0.5), (0.17, -0.06, 0.95)):
        cyl(0.05, top, (x, y, top / 2 + 0.06), rope, bevel=0)
        for z in range(int(top / 0.05)):
            ring(0.052, 0.008, (x, y, 0.08 + z * 0.05), rope)
    cyl(0.2, 0.05, (-0.12, 0.06, 0.58), carpet, bevel=0.02)
    cyl(0.22, 0.06, (0.17, -0.06, 1.04), carpet, bevel=0.025)
    ring(0.17, 0.045, (0.17, -0.06, 1.09), mat(HONEY, rough=1))
    tube([(-0.25, 0.06, 0.57), (-0.27, 0.06, 0.45), (-0.26, 0.06, 0.36)], 0.004, mat(INK))
    ball(0.035, (-0.26, 0.06, 0.33), mat(TERRACOTTA))


def sunset_print():
    frame = mat(WOOD)
    # Frame, mount and the picture, standing upright before it is leaned back.
    for z in (0.025, 0.695):
        box((0.56, 0.04, 0.05), (0, 0, z), frame, bevel=0.012)
    for x in (-0.255, 0.255):
        box((0.05, 0.04, 0.72), (x, 0, 0.36), frame, bevel=0.012)
    box((0.47, 0.012, 0.63), (0, 0.012, 0.36), mat(CREAM, rough=1), bevel=0)
    left, right, bottom, top, horizon = -0.18, 0.18, 0.13, 0.59, 0.33
    for z0, z1, color in ((0.47, top, 0xF9D9A8), (0.39, 0.47, 0xF6B98A), (horizon, 0.39, 0xEE9A7A)):
        flat([(left, z0), (right, z0), (right, z1), (left, z1)], 0.004, 0.002, mat(color, rough=1))
    sun = [(0.05 + 0.075 * math.cos(a), horizon + 0.075 * math.sin(a)) for a in
           (k / 32 * math.pi for k in range(33))]
    flat(sun, 0.002, 0.002, mat(0xFFF1D6, rough=1, emit=0.4))
    for y, color, phase, height in ((0.0015, SAGE, 0.0, 0.07), (0.0005, 0x7A9A6C, 1.7, 0.045)):
        hill = [(left + (right - left) * k / 40, horizon - 0.02 + height * (0.5 + 0.5 * math.sin(k / 40 * 7 + phase)))
                for k in range(41)]
        flat([(left, bottom)] + hill + [(right, bottom)], y, 0.002, mat(color, rough=1))
    lean = Matrix.Rotation(math.radians(-12), 4, "X")
    for obj in bpy.context.scene.objects:
        obj.matrix_world = lean @ obj.matrix_world
    # A strut at the back holds it up, like a desk frame's.
    top_back = lean @ Vector((0, 0.03, 0.5))
    foot = Vector((0, top_back.y + 0.2, 0.01))
    put(box((0.05, 0.02, (foot - top_back).length), (0, 0, 0), mat(WOOD_DARK), bevel=0.006),
        (top_back + foot) / 2, foot - top_back)


def tea_table():
    wood = mat(WOOD)
    cyl(0.36, 0.05, (0, 0, 0.36), wood, bevel=0.018)
    for k in range(3):
        a = k / 3 * math.tau + 0.4
        cyl(0.025, 0.34, (0.22 * math.cos(a), 0.22 * math.sin(a), 0.17), mat(WOOD_DARK), bevel=0.008)
    pot = mat(SKY, rough=0.45)
    ball(0.11, (-0.06, 0.04, 0.47), pot, scale=(1, 1, 0.82))
    cyl(0.045, 0.03, (-0.06, 0.04, 0.565), pot, bevel=0.008)
    ball(0.02, (-0.06, 0.04, 0.59), mat(CREAM))
    cone(0.03, 0.012, 0.12, (0.07, 0.02, 0.5), pot, rot=(0, math.radians(55), 0))
    ring(0.05, 0.012, (-0.17, 0.05, 0.48), pot, rot=(math.radians(90), 0, 0))
    for x, y in ((0.16, -0.12), (0.2, 0.12)):
        cyl(0.04, 0.05, (x, y, 0.41), mat(CREAM, rough=0.4), bevel=0.008)
        cyl(0.034, 0.005, (x, y, 0.434), mat(0xC98A4B, rough=0.2), bevel=0)


def donut_bed():
    random.seed(9)
    big, small, squash = 0.3, 0.13, 0.85

    def thickness(u):
        # Stuffed in eight soft puffs around the ring.
        return small * (1 + 0.05 * math.cos(8 * u))

    def at(u, v, grow=0.0):
        r = thickness(u) + grow
        rho = big + r * math.cos(v)
        return Vector((rho * math.cos(u), rho * math.sin(u), small * squash + r * math.sin(v) * squash))

    def normal(u, v):
        return Vector((math.cos(v) * math.cos(u), math.cos(v) * math.sin(u), math.sin(v) / squash)).normalized()

    surface(lambda s, t: at(s * math.tau, t * math.tau), 192, 48, mat(0xF3DDBF, rough=1, sheen=0.7))
    # Icing over the top, running down the outside in drips.
    def outer(u):
        return 0.35 - 0.55 * max(0.0, math.sin(7 * u + 0.6 * math.sin(3 * u))) ** 6

    def inner(u):
        return 2.6 + 0.12 * math.sin(5 * u + 1)

    surface(lambda s, t: at(s * math.tau, outer(s * math.tau) + t * (inner(s * math.tau) - outer(s * math.tau)), 0.005),
            288, 24, mat(BLUSH, rough=0.35), wrap_v=False, thickness=0.006)
    ball(0.21, (0, 0, 0.06), mat(OAT, rough=1, sheen=0.7), scale=(1, 1, 0.3))
    colors = [CREAM, HONEY, SKY, SAGE, ROSE]
    for k in range(44):
        u, v = random.uniform(0, math.tau), random.uniform(0.75, 2.3)
        n = normal(u, v)
        along = Vector((-math.sin(u), math.cos(u), 0))
        across = n.cross(along)
        turn = random.uniform(0, math.pi)
        put(ball(0.016, (0, 0, 0), mat(colors[k % 5], rough=0.4), scale=(1, 0.32, 0.32)),
            at(u, v, 0.009), n, along * math.cos(turn) + across * math.sin(turn))


def paper_lantern():
    shade = mat(0xFFD49A, rough=0.6, emit=2.2)
    ball(0.22, (0, 0, 0.42), shade, scale=(1, 1, 1.15))
    for z in (0.22, 0.32, 0.42, 0.52, 0.62):
        r = 0.22 * math.sqrt(max(0.0, 1 - ((z - 0.42) / 0.253) ** 2))
        ring(r + 0.002, 0.004, (0, 0, z), mat(WOOD_DARK))
    cyl(0.09, 0.05, (0, 0, 0.7), mat(TERRACOTTA), bevel=0.012)
    cyl(0.08, 0.04, (0, 0, 0.15), mat(TERRACOTTA), bevel=0.012)
    cyl(0.006, 0.25, (0, 0, 0.85), mat(INK), bevel=0)
    # A tassel hangs from the bottom cap and just touches the floor.
    rod((0, 0, 0.13), (0, 0, 0.075), 0.004, mat(ROSE), bevel=0)
    ball(0.016, (0, 0, 0.072), mat(ROSE))
    cone(0.026, 0.009, 0.06, (0, 0, 0.03), mat(ROSE, rough=1, sheen=0.5))


ITEMS = {
    "armchair": cloud_armchair,
    "lamp": mushroom_lamp,
    "monstera": monstera,
    "bookcase": little_bookcase,
    "rug": woven_rug,
    "yarn": yarn_ball,
    "mouse": toy_mouse,
    "tower": cat_tower,
    "print": sunset_print,
    "teatable": tea_table,
    "donutbed": donut_bed,
    "lantern": paper_lantern,
}


# ---------------------------------------------------------------- export + thumbnail


def export_usdz(path):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.wm.usd_export(
        filepath=path,
        selected_objects_only=True,
        export_materials=True,
        generate_preview_surface=True,
        export_animation=False,
        convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y",
        evaluation_mode="RENDER",
    )


def bounds():
    deps = bpy.context.evaluated_depsgraph_get()
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        ev = obj.evaluated_get(deps)
        for v in ev.data.vertices:
            p = ev.matrix_world @ v.co
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
    return lo, hi


# Items whose silhouette throws a longer shadow need a slightly higher sun, otherwise the
# shadow tail still touches the frame edge. Values are sun pitch in degrees.
SUN_PITCH = {"bookcase": 16.0, "print": 16.0, "tower": 16.0}


def render_thumbnail(path, sun_pitch=22.0):
    scene = bpy.context.scene
    lo, hi = bounds()
    center = (lo + hi) / 2
    radius = (hi - lo).length / 2

    # The camera looks past the catcher's edge at the top of the frame with a small plane,
    # which leaves a faint cut in the corner; a much larger catcher covers the whole frame.
    bpy.ops.mesh.primitive_plane_add(size=radius * 40, location=(center.x, center.y, lo.z))
    bpy.context.object.is_shadow_catcher = True

    world = bpy.data.worlds.new("World")
    world.color = (0.95, 0.82, 0.7)
    scene.world = world

    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 2.6
    sun.data.angle = math.radians(35)
    sun.data.color = (1.0, 0.93, 0.84)
    # A high sun keeps the contact shadow short enough to stay inside the frame.
    sun.rotation_euler = (math.radians(sun_pitch), 0, math.radians(-35))
    scene.collection.objects.link(sun)
    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "SUN"))
    fill.data.energy = 1.0
    fill.data.angle = math.radians(90)
    fill.data.use_shadow = False
    fill.rotation_euler = (math.radians(60), 0, math.radians(30))
    scene.collection.objects.link(fill)

    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 70
    scene.collection.objects.link(cam)
    fov = 2 * math.atan(18 / cam.data.lens)
    direction = Vector((0.55, -1.0, 0.62)).normalized()
    # Pull the camera back a little so the contact shadow never reaches the frame edge.
    cam.location = center + direction * (radius / math.sin(fov / 2)) * 1.2
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (center - cam.location).to_track_quat("-Z", "Y")
    scene.camera = cam

    scene.render.engine = "CYCLES"
    # The Mac's GPU through Metal; Cycles falls back to the CPU where there is none.
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"
    prefs.get_devices()
    for device in prefs.devices:
        device.use = True
    scene.cycles.device = "GPU"
    scene.cycles.samples = 128
    scene.cycles.use_denoising = True
    scene.view_settings.view_transform = "Standard"
    scene.render.film_transparent = True
    # Cards show these at up to ~800 px on a 3x screen.
    scene.render.resolution_x = scene.render.resolution_y = 1024
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# Tools/make_room.py imports the builders above, so the catalog only builds when this file is run.
if __name__ == "__main__":
    for item_id, build in ITEMS.items():
        if ONLY and item_id not in ONLY:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        _materials.clear()
        build()
        export_usdz(os.path.join(OUT_DIR, f"Item_{item_id}.usdz"))
        render_thumbnail(os.path.join(OUT_DIR, f"Item_{item_id}.png"), SUN_PITCH.get(item_id, 22.0))
        print("ITEM", item_id)
