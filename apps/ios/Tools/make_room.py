"""Builds the furniture of Mochi's room (DioramaScene) in Blender: one USDZ per file below.

Run:
  blender -b --python Tools/make_room.py -- Nooki/Resources/Room [name ...]
  FULL=1 blender -b --python Tools/make_room.py -- <dir> [name ...]   (every circle at its full segment count)

Writes Room_<name>.usdz (furniture: what never moves; ball, yarn: toys) and Base_<name>.usdz, one per piece of the
room's own furniture that the player can move (name `Base_<piece>` selects one). The furniture is modelled in the room's own coordinates (meters, floor top at
y = 0.014, the room spanning x and z -0.5...0.5), so the app adds it at the pivot's origin as it is; the toys are
modelled around their own origin, because the app moves them. Objects named Glow_<part> stay separate: the app
gives them its emissive material (see DioramaScene.glows). Everything else in a file is joined into one mesh.

Shapes and materials come from Tools/make_items.py, so the room matches the shop's items.
"""

import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_items as kit  # noqa: E402
from make_items import mat  # noqa: E402

OUT_DIR = kit.OUT_DIR
ONLY = kit.ONLY
# The shapes get the facets their size on screen can show (make_items.facets): a third of the triangles. FULL=1 builds
# them at full detail, as `scripts/bake-room/Room_furniture.usdz` is, which the bake casts shadows with.
kit.LOD = os.environ.get("FULL") != "1"

# The room's palette (DioramaScene.Tone), so the models sit with the walls and floor drawn in code.
WOOD, WOOD_DARK, WOOD_LIGHT = 0xB46C3C, 0x8C4F2B, 0xCF8E58
PLUSH, PLUSH_SHADE = 0xFBF1E3, 0xEADBC6
RUG, RUG_EDGE = 0xDDB98A, 0xC39A69
LEAF, LEAF_DARK, LEAF_PALE = 0x93A86A, 0x6F8A4E, 0xB9C68A
POT, SOIL, BLANKET = 0xC7744A, 0x4A3328, 0xE98A5B
CERAMIC, WAX, ROPE = 0xF3EDE4, 0xFFF3E0, 0xD9B98C

FLOOR = 0.014


# ---------------------------------------------------------------- room-space helpers


def R(x, y, z):
    """Room point (x, y up, z toward the viewer) in Blender space, where the export turns Z up into Y up."""
    return Vector((x, -z, y))


def S(w, h, d):
    return (w, d, h)


def named(obj, name):
    obj.name = name
    obj.data.name = name
    return obj


def rbox(size, at, m, bevel=0.004, yaw=0.0):
    return kit.box(S(*size), R(*at), m, bevel=bevel, rot=(0, 0, yaw))


def rcyl(radius, height, at, m, bevel=0.003, verts=40):
    return kit.cyl(radius, height, R(*at), m, bevel=bevel, verts=verts)


def rcone(r_bottom, r_top, height, at, m, bevel=0.002):
    return kit.cone(r_bottom, r_top, height, R(*at), m, bevel=bevel)


def rball(radius, at, m, scale=(1, 1, 1), detail=(32, 16)):
    around = kit.facets(radius * max(scale), detail[0])
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=around, ring_count=max(4, min(detail[1], around // 2)),
                                         location=R(*at))
    return kit._finish(kit._scaled(bpy.context.object, S(*scale)), m)


# Torus axes in Blender rotations: lying flat (normal up), facing the room's x, facing its z.
AXES = {"y": (0, 0, 0), "x": (0, math.pi / 2, 0), "z": (math.pi / 2, 0, 0)}


def rring(major, minor, at, m, axis="y", squash=1.0, detail=(48, 12)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     major_segments=kit.facets(major * squash if squash > 1 else major, detail[0]),
                                     minor_segments=kit.facets(minor, detail[1], minimum=6), location=R(*at),
                                     rotation=AXES[axis])
    obj = bpy.context.object
    if squash != 1.0:
        obj.scale = {"y": (1, 1, squash), "x": (squash, 1, 1), "z": (1, squash, 1)}[axis]
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return kit._finish(obj, m)


def rdisc(radius, thickness, at, m, axis="y", bevel=0.002, verts=48):
    obj = rcyl(radius, thickness, at, m, bevel=bevel, verts=verts)
    obj.rotation_euler = AXES[axis]
    return obj


def rrod(p0, p1, radius, m, bevel=0.0):
    return kit.rod(R(*p0), R(*p1), radius, m, bevel=bevel)


def rtube(points, radius, m):
    return kit.tube([tuple(R(*p)) for p in points], radius, m)


def leaf(base, direction, length, width, m, thickness=0.3):
    """A plump pointed leaf from `base` along room `direction`: an ellipsoid with its long axis on it."""
    d = R(*direction).normalized()
    obj = rball(1, (0, 0, 0), m, detail=(20, 10))
    obj.scale = (width, width * thickness, length / 2)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return kit.put(obj, R(*base) + d * length / 2, d)


def blade(base, height, width, angle, lean, m, twist=0.6):
    """A tall sword leaf, as a snake plant grows them: flat, widest low down, curving out and twisting a little."""
    b = R(*base)
    out = Vector((math.cos(angle), math.sin(angle), 0))

    def at(s, t):
        centre = b + Vector((0, 0, height * t)) + out * lean * t * t
        w = width * (1 - t ** 2.4) * (0.55 + 0.45 * min(t * 5, 1))
        phi = angle + math.pi / 2 + twist * t
        across = Vector((math.cos(phi), math.sin(phi), 0))
        a = s * math.tau
        return centre + across * w * math.cos(a) + out * w * 0.16 * math.sin(a)

    return kit.surface(at, 24, 28, m, wrap_v=False)


def pot(at, r_bottom, r_top, height, m, soil=True):
    x, y, z = at
    rcone(r_bottom, r_top, height, (x, y + height / 2, z), m)
    rring(r_top, height * 0.09, (x, y + height, z), m, detail=(40, 10))
    if soil:
        rcyl(r_top * 0.92, 0.004, (x, y + height - 0.006, z), mat(SOIL, rough=1), bevel=0)


def rosette(at, size, m_outer, m_inner, count=9):
    """A succulent: two rings of plump leaves opening out of the soil, a tight bud in the middle."""
    x, y, z = at
    for k in range(count):
        a = k / count * math.tau
        leaf((x, y, z), (math.cos(a), 0.55, math.sin(a)), size, size * 0.32, m_outer, thickness=0.45)
    for k in range(count - 3):
        a = (k + 0.5) / (count - 3) * math.tau
        leaf((x, y, z), (math.cos(a) * 0.6, 1, math.sin(a) * 0.6), size * 0.7, size * 0.26, m_inner, thickness=0.5)
    rball(size * 0.22, (x, y + size * 0.15, z), m_inner, scale=(1, 1.3, 1), detail=(16, 8))


# ---------------------------------------------------------------- the furniture


def window():
    wood, light = mat(WOOD, rough=0.6), mat(WOOD_LIGHT, rough=0.6)
    cx, cy, cz = -0.49, 0.47, 0.02
    # Round frame: a deep reveal in the wall, a rounded outer ring and a thinner inner bead round the glass.
    rring(0.192, 0.026, (-0.476, cy, cz), wood, axis="x", detail=(96, 16))
    rring(0.168, 0.008, (-0.468, cy, cz), light, axis="x", detail=(96, 10))
    rdisc(0.2, 0.012, (-0.499, cy, cz), mat(WOOD_DARK, rough=0.8), axis="x")
    named(rdisc(0.17, 0.006, (-0.489, cy, cz), mat(0xFFE0A0), axis="x", bevel=0), "Glow_window")
    # Muntins, slightly rounded and proud of the glass.
    for dz in (-0.06, 0.06):
        rbox((0.014, 0.335, 0.014), (-0.472, cy, cz + dz), wood, bevel=0.004)
    for dy in (-0.06, 0.06):
        rbox((0.014, 0.014, 0.335), (-0.472, cy + dy, cz), wood, bevel=0.004)



def window_seat():
    wood, light = mat(WOOD, rough=0.6), mat(WOOD_LIGHT, rough=0.6)
    # The deep sill Mochi sits on, with a rounded nose, an apron under it and two corbels.
    rbox((0.19, 0.022, 0.42), (-0.41, 0.262, 0.0), light, bevel=0.007)
    rbox((0.024, 0.034, 0.4), (-0.322, 0.238, 0.0), wood, bevel=0.008)
    for z in (-0.15, 0.15):
        rbox((0.07, 0.05, 0.022), (-0.465, 0.226, z), wood, bevel=0.01)
    # Her cushion: plump, piped round the edge, two buttons pulling the top in.
    cushion = mat(BLANKET, rough=1, sheen=0.6)
    rbox((0.15, 0.026, 0.19), (-0.4, 0.286, 0.0), cushion, bevel=0.012)
    for z in (-0.045, 0.045):
        rball(0.006, (-0.4, 0.299, z), mat(0xC8633F, rough=0.7), scale=(1, 0.5, 1), detail=(12, 6))
    # A succulent in a little pot at the back end, a candle jar at the front end.
    pot((-0.44, 0.273, -0.16), 0.019, 0.025, 0.036, mat(POT, rough=0.7))
    rosette((-0.44, 0.305, -0.16), 0.03, mat(LEAF, rough=0.6), mat(LEAF_PALE, rough=0.6))
    rcyl(0.022, 0.036, (-0.44, 0.291, 0.17), mat(CERAMIC, rough=0.35), bevel=0.004)
    rcyl(0.018, 0.004, (-0.44, 0.308, 0.17), mat(WAX, rough=0.5), bevel=0)
    rrod((-0.44, 0.308, 0.17), (-0.44, 0.318, 0.17), 0.0012, mat(0x2E241F))


def nightstand():
    wood, front, dark = mat(WOOD, rough=0.6), mat(WOOD_LIGHT, rough=0.6), mat(WOOD_DARK, rough=0.6)
    x, z = -0.39, 0.33
    rbox((0.21, 0.02, 0.23), (x, 0.207, z), wood, bevel=0.007)
    rbox((0.19, 0.17, 0.21), (x - 0.005, 0.112, z), wood, bevel=0.01)
    for dx in (-0.08, 0.075):
        for dz in (-0.088, 0.088):
            rcone(0.009, 0.012, 0.03, (x + dx, 0.015 + FLOOR / 2, z + dz), dark)
    # Two drawers facing the room, each with a round knob.
    for y in (0.07, 0.15):
        rbox((0.012, 0.068, 0.18), (x + 0.094, y, z), front, bevel=0.005)
        rball(0.009, (x + 0.106, y, z), dark, scale=(0.7, 1, 1), detail=(16, 8))
    # A pillar candle on a saucer; DioramaScene draws its flame.
    rcyl(0.03, 0.006, (x - 0.02, 0.22, z + 0.05), mat(CERAMIC, rough=0.35), bevel=0.003)
    rcyl(0.021, 0.05, (x - 0.02, 0.248, z + 0.05), mat(WAX, rough=0.55), bevel=0.006)
    rrod((x - 0.02, 0.27, z + 0.05), (x - 0.02, 0.279, z + 0.05), 0.0012, mat(0x2E241F))
    # A small fern in a pot.
    pot((x, 0.217, z - 0.06), 0.022, 0.03, 0.04, mat(POT, rough=0.7))
    random.seed(5)
    for k in range(11):
        a = k / 11 * math.tau + random.uniform(-0.2, 0.2)
        rise = random.uniform(0.6, 1.4)
        leaf((x, 0.252, z - 0.06), (math.cos(a), rise, math.sin(a)), random.uniform(0.05, 0.075), 0.012,
             mat(LEAF if k % 2 else LEAF_DARK, rough=0.6), thickness=0.25)


def corner_plant():
    x, z = -0.4, -0.4
    pot((x, FLOOR, z), 0.05, 0.062, 0.1, mat(POT, rough=0.7))
    random.seed(8)
    tones = [mat(LEAF_DARK, rough=0.55), mat(LEAF, rough=0.55)]
    for k in range(7):
        a = k / 7 * math.tau + random.uniform(-0.25, 0.25)
        r = random.uniform(0.008, 0.028)
        blade((x + r * math.cos(a), FLOOR + 0.09, z + r * math.sin(a)), random.uniform(0.2, 0.33),
              random.uniform(0.028, 0.036), a, random.uniform(0.02, 0.05), tones[k % 2], twist=random.uniform(-0.5, 0.5))


def shelf():
    wood, dark = mat(WOOD, rough=0.6), mat(WOOD_DARK, rough=0.6)
    cx, cy, cz = 0.04, 0.55, -0.455
    rbox((0.2, 0.018, 0.08), (cx, cy, cz), wood, bevel=0.005)
    # Two brackets: an arm under the board and a strut back to the wall.
    for dx in (-0.07, 0.07):
        rbox((0.014, 0.012, 0.06), (cx + dx, cy - 0.015, cz - 0.005), dark, bevel=0.003)
        rbox((0.014, 0.05, 0.012), (cx + dx, cy - 0.035, -0.49), dark, bevel=0.003)
        rrod((cx + dx, cy - 0.055, -0.488), (cx + dx, cy - 0.012, cz + 0.02), 0.004, dark)
    # Books with a band on each spine; the last one leans on the row.
    tones = [0xC0563A, 0x7C9A7E, 0xE3B45C, 0x9A7BB8]
    x = cx - 0.085
    for i, tone in enumerate(tones):
        h = 0.06 + (i % 3) * 0.01
        rbox((0.02, h, 0.058), (x, cy + 0.009 + h / 2, cz), mat(tone, rough=0.7), bevel=0.003)
        rbox((0.0205, 0.006, 0.059), (x, cy + 0.009 + h * 0.78, cz), mat(0xF3E2C0, rough=0.5), bevel=0.001)
        x += 0.023
    lean = rbox((0.02, 0.06, 0.055), (x + 0.008, cy + 0.037, cz), mat(0x6F8FB0, rough=0.7), bevel=0.003)
    lean.rotation_euler = (0, math.radians(20), 0)
    # A jar of fairy light, and a tiny succulent at the end.
    named(rcyl(0.018, 0.045, (cx + 0.045, cy + 0.032, cz), mat(0xFFE7B8), bevel=0.006), "Glow_jar")
    rcyl(0.012, 0.008, (cx + 0.045, cy + 0.058, cz), mat(WOOD_LIGHT, rough=0.6), bevel=0.003)
    pot((cx + 0.083, cy + 0.009, cz), 0.013, 0.017, 0.024, mat(POT, rough=0.7))
    rosette((cx + 0.083, cy + 0.03, cz), 0.018, mat(LEAF, rough=0.6), mat(LEAF_PALE, rough=0.6), count=7)


def stool_lamp():
    wood, dark = mat(WOOD, rough=0.6), mat(WOOD_DARK, rough=0.6)
    x, z = -0.1, -0.42
    rcyl(0.062, 0.022, (x, 0.16, z), wood, bevel=0.008)
    for k in range(3):
        a = k / 3 * math.tau + 0.5
        rrod((x + 0.035 * math.cos(a), 0.152, z + 0.035 * math.sin(a)),
             (x + 0.055 * math.cos(a), FLOOR, z + 0.055 * math.sin(a)), 0.0075, dark)
    rring(0.043, 0.004, (x, 0.07, z), dark, detail=(32, 8))
    # A round ceramic lamp with a pleated-looking drum shade.
    rball(0.032, (x, 0.198, z), mat(0xE7B98F, rough=0.3), scale=(1, 0.9, 1))
    rcyl(0.007, 0.035, (x, 0.24, z), mat(0xC9A77C, rough=0.3), bevel=0.002)
    named(rcone(0.058, 0.045, 0.052, (x, 0.272, z), mat(0xFFE2AE), bevel=0.003), "Glow_lamp")
    rring(0.058, 0.0025, (x, 0.246, z), mat(0xE9C9A0, rough=0.6), detail=(48, 8))
    rring(0.045, 0.0025, (x, 0.298, z), mat(0xE9C9A0, rough=0.6), detail=(48, 8))


def cat_tree():
    x, z = 0.36, -0.36
    carpet, rope = mat(PLUSH_SHADE, rough=1, sheen=0.5), mat(ROPE, rough=1)
    rbox((0.2, 0.03, 0.2), (x, FLOOR + 0.015, z), carpet, bevel=0.012)
    rcyl(0.03, 0.32, (x, FLOOR + 0.18, z), mat(0xC8A576, rough=1), bevel=0)
    # Sisal wound round the post: one ring per turn.
    for k in range(25):
        rring(0.031, 0.0045, (x, FLOOR + 0.045 + k * 0.0118, z), rope, detail=(28, 6))
    rcyl(0.1, 0.03, (x, FLOOR + 0.35, z), carpet, bevel=0.012)
    # Her cushion on the top: a soft ring round a padded middle, where she sits at y = 0.396.
    rring(0.072, 0.019, (x, FLOOR + 0.372, z), mat(BLANKET, rough=1, sheen=0.6), squash=0.8, detail=(48, 14))
    rcyl(0.065, 0.016, (x, FLOOR + 0.37, z), mat(0xF2A77C, rough=1, sheen=0.6), bevel=0.007)
    # A pompom on a cord, swinging off the platform's edge.
    rtube([(x + 0.08, FLOOR + 0.335, z + 0.04), (x + 0.082, FLOOR + 0.28, z + 0.041), (x + 0.08, FLOOR + 0.228, z + 0.04)],
          0.0016, mat(0x5B3A28, rough=0.8))
    random.seed(3)
    fluff = mat(BLANKET, rough=1, sheen=0.7)
    rball(0.018, (x + 0.08, FLOOR + 0.21, z + 0.04), fluff, detail=(20, 10))
    for _ in range(18):
        d = Vector((random.gauss(0, 1), random.gauss(0, 1), random.gauss(0, 1))).normalized() * 0.016
        rball(0.007, (x + 0.08 + d.x, FLOOR + 0.21 + d.y, z + 0.04 + d.z), fluff, detail=(10, 6))


def bed():
    """The shop's donut bed, at the room's bed spot and size."""
    before = set(bpy.context.scene.objects)
    kit.donut_bed()
    s = 0.4
    for obj in set(bpy.context.scene.objects) - before:
        obj.matrix_world = Matrix.Translation(R(0.06, FLOOR, -0.04)) @ Matrix.Scale(s, 4) @ obj.matrix_world


def rug():
    cx, cz = 0.0, 0.04
    rcyl(0.318, 0.008, (cx, FLOOR + 0.004, cz), mat(RUG, rough=1, sheen=0.4), bevel=0.003, verts=96)
    # Braided rings, as on a woven rag rug.
    for r, tone in ((0.31, RUG_EDGE), (0.255, 0xF2D7AE), (0.2, 0xE9A27A), (0.14, RUG_EDGE), (0.075, 0xF2D7AE)):
        rring(r, 0.007, (cx, FLOOR + 0.008, cz), mat(tone, rough=1, sheen=0.4), squash=0.5, detail=(128, 8))
    for k in range(40):
        a = k / 40 * math.tau
        rball(0.011, (cx + 0.322 * math.cos(a), FLOOR + 0.004, cz + 0.322 * math.sin(a)), mat(RUG_EDGE, rough=1),
              scale=(1, 0.45, 1), detail=(12, 6))


def basket():
    x, z = 0.37, 0.36
    weave = [mat(0xC9A06A, rough=0.9), mat(0xB48A55, rough=0.9)]
    rcyl(0.064, 0.008, (x, FLOOR + 0.004, z), weave[1], bevel=0.003)
    rcyl(0.062, 0.06, (x, FLOOR + 0.038, z), mat(0x6E4F33, rough=1), bevel=0)
    for k in range(8):
        rring(0.068 + k * 0.0012, 0.0062, (x, FLOOR + 0.008 + k * 0.0094, z), weave[k % 2], squash=0.85, detail=(48, 8))
    rring(0.078, 0.009, (x, FLOOR + 0.084, z), weave[0], detail=(56, 10))


def bowls():
    for x, water in ((0.06, False), (0.155, True)):
        z = -0.37
        rcone(0.03, 0.04, 0.026, (x, FLOOR + 0.013, z), mat(CERAMIC, rough=0.25))
        rring(0.039, 0.004, (x, FLOOR + 0.026, z), mat(CERAMIC, rough=0.25), detail=(40, 8))
        rring(0.0305, 0.0022, (x, FLOOR + 0.004, z), mat(0xE48E9C, rough=0.4), detail=(40, 6))
        if water:
            rcyl(0.033, 0.003, (x, FLOOR + 0.02, z), mat(0x6FA3CF, rough=0.15), bevel=0)
        else:
            random.seed(2)
            for _ in range(22):
                a, r = random.uniform(0, math.tau), random.uniform(0, 0.027)
                rball(0.0055, (x + r * math.cos(a), FLOOR + 0.022 + random.uniform(0, 0.004), z + r * math.sin(a)),
                      mat(0xB77A4A, rough=0.8), scale=(1, 0.7, 1), detail=(8, 5))
    # A felt mat under them.
    rbox((0.2, 0.004, 0.09), (0.107, FLOOR + 0.002, -0.37), mat(0x9DB08A, rough=1), bevel=0.0018)


def picture():
    x, y, z = -0.496, 0.52, 0.36
    rring(0.068, 0.009, (x + 0.008, y, z), mat(WOOD, rough=0.6), axis="x", detail=(64, 10))
    rdisc(0.064, 0.006, (x + 0.003, y, z), mat(0xFBE9D6, rough=0.9), axis="x")
    paw = mat(0xE89AA8, rough=0.8)
    rball(0.02, (x + 0.008, y - 0.012, z), paw, scale=(0.25, 0.9, 1.05), detail=(20, 10))
    for py, pz in ((0.014, -0.022), (0.027, -0.008), (0.027, 0.008), (0.014, 0.022)):
        rball(0.0085, (x + 0.008, y + py, z + pz), paw, scale=(0.3, 1.1, 0.9), detail=(14, 8))


def floor_books():
    # No two faces share a plane, or they flicker against each other as the room turns: the lower book sinks a
    # little into the floor, the upper one into the lower, and each block of pages stands just proud of its
    # cover's open side.
    base = 0.014 - 0.0015
    for (w, h, d), yaw, tone in (((0.12, 0.024, 0.09), 0.3, 0x7C9A7E), ((0.1, 0.022, 0.08), 0.1, 0xE3B45C)):
        y = base + h / 2
        rbox((w, h, d), (0.2, y, 0.4), mat(tone, rough=1.0), bevel=0.004, yaw=yaw)
        out = 0.004 + 0.0012
        rbox((w - 0.008, h * 0.7, d - 0.01), (0.2 + out * math.cos(yaw), y, 0.4 - out * math.sin(yaw)),
             mat(0xF7EBD3, rough=1.0), bevel=0.001, yaw=yaw)
        base += h - 0.0015


def wires():
    """The fairy lights' wire along the top of both walls; the bulbs themselves are drawn in code."""
    top, count = 0.75, 13
    m = mat(0x3B2C24, rough=0.6)
    for wall in range(2):
        points = []
        for k in range(count * 3 - 2):
            t = k / (count * 3 - 3)
            sag = 0.05 * abs(math.sin(t * math.pi * 2))
            u = -0.47 + t * 0.94
            points.append((u, top - sag + 0.006, -0.475) if wall == 0 else (-0.475, top - sag + 0.006, u))
        rtube(points, 0.0014, m)


def furniture():
    """What never moves: the round window, the shelf, the picture, the fairy lights' wire."""
    for build in (window, shelf, picture, wires):
        build()


# The room's own furniture, one file each: `Base_<name>.usdz`, its origin on the floor (y 0 at the boards' top) at
# the middle of the cell the piece stands in when the room is as it always was (grid cells of 5 cm, as
# tools/decor-lod/catalog.py BASE). A holder at that cell's middle, on the floor, puts it where it stood.
PIECES = {
    "windowseat": (window_seat, (-8, 0)),
    "nightstand": (nightstand, (-8, 7)),
    "plant": (corner_plant, (-8, -8)),
    "lamp": (stool_lamp, (-2, -8)),
    "cattree": (cat_tree, (7, -7)),
    "bowls": (bowls, (2, -7)),
    "donutbed": (bed, (1, -1)),
    "basket": (basket, (7, 7)),
    "books": (floor_books, (4, 8)),
    "rug": (rug, (0, 1)),
}


# ---------------------------------------------------------------- toys, around their own origin


def ball_toy():
    rball(0.028, (0, 0, 0), mat(0xF28FA6, rough=0.6, sheen=0.5), detail=(40, 20))
    for tilt in (0.35, -0.9):
        r = rring(0.0285, 0.0035, (0, 0, 0), mat(PLUSH, rough=0.5), detail=(48, 8))
        r.rotation_euler = (tilt, 0.4, 0)
    rball(0.008, (0, 0.03, 0), mat(0xE8C25A, rough=0.25), detail=(16, 8))


def yarn():
    """The three yarn balls in the basket, each a core with strands wound over it."""
    random.seed(4)
    for (x, y, z), r, tone, strand in (((-0.02, 0.09, 0.0), 0.03, BLANKET, 0xF0A07A),
                                       ((0.025, 0.088, 0.015), 0.028, 0xF2D3A0, 0xF8E2BC),
                                       ((0.0, 0.092, -0.03), 0.026, 0x9DB08A, 0xB2C49E)):
        rball(r, (x, y, z), mat(tone, rough=1, sheen=0.5), detail=(24, 12))
        for _ in range(14):
            ring = rring(r * 0.99, 0.0018, (x, y, z), mat(strand, rough=1, sheen=0.5), detail=(40, 5))
            ring.rotation_euler = (random.uniform(0, math.tau), random.uniform(0, math.tau), random.uniform(0, math.tau))
    rtube([(0.03, 0.09, 0.03), (0.06, 0.09, 0.06), (0.075, 0.06, 0.07), (0.08, 0.0, 0.09), (0.12, -0.08, 0.11)],
          0.0018, mat(0xF0A07A, rough=1))


FILES = {"furniture": furniture, "ball": ball_toy, "yarn": yarn}


def join_solid():
    """One mesh for everything but the Glow_ parts, so the room is a handful of draw calls."""
    bpy.ops.object.select_all(action="DESELECT")
    solid = [o for o in bpy.context.scene.objects if o.type == "MESH" and not o.name.startswith("Glow_")]
    for o in solid:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        for mod in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.context.view_layer.objects.active = solid[0]
    for o in solid:
        o.select_set(True)
    bpy.ops.object.join()
    named(bpy.context.object, "Solid")


def move_origin(u, v):
    """Shifts everything so the origin is the middle of cell (u, v) on the boards, baked into the meshes."""
    delta = Vector((-u * 0.05, v * 0.05, -FLOOR))
    for o in bpy.context.scene.objects:
        o.location += delta
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)


for name, build in FILES.items():
    if ONLY and name not in ONLY:
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit._materials.clear()
    build()
    join_solid()
    kit.export_usdz(os.path.join(OUT_DIR, f"Room_{name}.usdz"))
    print("ROOM", name)

for name, (build, (u, v)) in PIECES.items():
    if ONLY and f"Base_{name}" not in ONLY:
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit._materials.clear()
    build()
    join_solid()
    move_origin(u, v)
    kit.export_usdz(os.path.join(OUT_DIR, f"Base_{name}.usdz"))
    print("BASE", name)
