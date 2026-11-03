"""Builds the 3D night street outside Window Seat's window: models it, bakes its light into one
atlas, and writes the meshes the app draws through the window.

The street is laid out in the view's own frame, in room units (half a metre): x to the right, y
away from the window, z up, with the eye of the camera at its home place at height 0. The app
turns this frame so that its y runs from the home camera through the window's middle, so at home
the street is seen straight on, as the flat views are, and any orbit shows it with true depth.

    near    a picket fence, a hedge, a tree, the mailbox (8-16 units out)
    street  the road, the parked car, the street lamp (24-40)
    middle  the houses across the road and the corner shop (48-60)
    cards   a roofline of the next street and a far skyline, as alpha planes (110, 220)

The lighting is Cycles, baked once: a white sky light that leaves each colour as the palette
gives it, the street lamp's and porch lights' warm pools, the room's window spilling onto the
fence, and lit windows that glow. The app draws it all unlit, so it costs no real-time light.

    Blender -b --factory-startup -t 4 -P make_street_view.py -- <out dir> [samples]

Writes <out>/street.bin (see `write_bin`), <out>/street-atlas.png (1024 px), <out>/cards.json for
paint_street_cards.py, and <out>/preview.png from the home camera.
"""

import json
import math
import random
import struct
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
OUT = Path(argv[0] if argv else "street-out")
SAMPLES = int(argv[1]) if len(argv) > 1 else 96
OUT.mkdir(parents=True, exist_ok=True)
ATLAS_PX = 1024
GROUND = -5.0
# The face of the houses across the road.
FRONT = 54.0
GLOWS = []  # (x, y, z, radius) of glow sprites
# The houses across the road are cottages, built at a house's size and then shrunk towards the
# window's line by this much, so three or four fit in the window as in the flat view.
MID_SCALE = 0.7


def mid_pt(x, y, z):
    """A point built at full size across the road, where it ends up once shrunk."""
    return (x * MID_SCALE, FRONT + (y - FRONT) * MID_SCALE, GROUND + (z - GROUND) * MID_SCALE)
random.seed(7)

# The night palette of the flat views (ViewPalette, night, clear), sRGB.
PAL = {
    "far": 0x20365A,
    "middle": 0x14233D,
    "street": 0x0E1A2E,
    "near": 0x0A1220,
    "horizon": 0x3A5A86,
    "lamp": 0xFFC36B,
    "lampCore": 0xFFE2B0,
    "tv": 0x7FB2FF,
    "porchRed": 0xE5503A,
}


def srgb(hex_value):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (lin((hex_value >> 16) & 255), lin((hex_value >> 8) & 255), lin(hex_value & 255), 1)


def lit(hex_value, share):
    """The flat views' `lit`: towards white for a positive share, black for a negative one."""
    r, g, b = (hex_value >> 16) & 255, (hex_value >> 8) & 255, hex_value & 255
    t = 255 if share >= 0 else 0
    s = abs(share)
    mix = lambda c: int(round(c + (t - c) * s))
    return (mix(r) << 16) | (mix(g) << 8) | mix(b)


def mixed(a, b, share):
    ca = [(a >> k) & 255 for k in (16, 8, 0)]
    cb = [(b >> k) & 255 for k in (16, 8, 0)]
    c = [int(round(x + (y - x) * share)) for x, y in zip(ca, cb)]
    return (c[0] << 16) | (c[1] << 8) | c[2]


# MARK: - Scene and materials

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.render.threads_mode = "FIXED"
scene.render.threads = 4
scene.cycles.samples = SAMPLES
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"

ATLAS = bpy.data.images.new("street-atlas", ATLAS_PX, ATLAS_PX, alpha=False)
ATLAS.colorspace_settings.name = "sRGB"
MATERIALS = {}


def material(name, colour, emit=0.0, emit_colour=None):
    """A matte material of `colour`, glowing `emit` strong, with the atlas as its bake target."""
    key = (name, colour, emit, emit_colour)
    if key in MATERIALS:
        return MATERIALS[key]
    mat = bpy.data.materials.new(f"{name}-{len(MATERIALS)}")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = srgb(colour)
    bsdf.inputs["Roughness"].default_value = 0.95
    bsdf.inputs["Specular IOR Level"].default_value = 0.1
    if emit > 0:
        bsdf.inputs["Emission Color"].default_value = srgb(emit_colour or colour)
        bsdf.inputs["Emission Strength"].default_value = emit
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = ATLAS
    nodes.active = tex
    MATERIALS[key] = mat
    return mat


# MARK: - Shapes

PARTS = []  # (object, layer)


class Part:
    """One piece of the street being built as a bmesh, one material per face."""

    def __init__(self, name, layer):
        self.name, self.layer = name, layer
        self.bm = bmesh.new()
        self.mats = []

    def slot(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def face(self, points, mat):
        verts = [self.bm.verts.new(p) for p in points]
        f = self.bm.faces.new(verts)
        f.material_index = self.slot(mat)
        return f

    def box(self, x0, y0, z0, x1, y1, z1, mat, skip=()):
        """An axis-aligned box. `skip` leaves out faces nobody sees: 'bottom', 'back', ..."""
        c = [
            (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
            (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
        ]
        faces = {
            "bottom": (0, 3, 2, 1), "top": (4, 5, 6, 7), "front": (0, 1, 5, 4),
            "back": (2, 3, 7, 6), "left": (3, 0, 4, 7), "right": (1, 2, 6, 5),
        }
        for side, idx in faces.items():
            if side not in skip:
                self.face([c[i] for i in idx], mat)

    def gable(self, x0, y0, x1, y1, z, rise, mat, overhang=0.5, end=None):
        """A gable roof over the box x0..x1, y0..y1 with its ridge along x, and the two gable
        ends filled with `end` (the wall's material)."""
        o = overhang
        xa, xb, ya, yb, ym = x0 - o, x1 + o, y0 - o, y1 + o, (y0 + y1) / 2
        top = z + rise
        low = z - o * rise / ((y1 - y0) / 2)
        self.face([(xa, ya, low), (xb, ya, low), (xb, ym, top), (xa, ym, top)], mat)
        self.face([(xb, yb, low), (xa, yb, low), (xa, ym, top), (xb, ym, top)], mat)
        if end is not None:
            self.face([(x0, y0, z), (x0, y1, z), (x0, ym, top)], end)
            self.face([(x1, y1, z), (x1, y0, z), (x1, ym, top)], end)

    def cylinder(self, x, y, z0, z1, radius, mat, sides=8, top=True):
        ring0, ring1 = [], []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            ring0.append(self.bm.verts.new((x + radius * math.cos(a), y + radius * math.sin(a), z0)))
            ring1.append(self.bm.verts.new((x + radius * math.cos(a), y + radius * math.sin(a), z1)))
        for k in range(sides):
            n = (k + 1) % sides
            f = self.bm.faces.new((ring0[k], ring0[n], ring1[n], ring1[k]))
            f.material_index = self.slot(mat)
        if top:
            f = self.bm.faces.new(ring1)
            f.material_index = self.slot(mat)

    def blob(self, centre, radius, mat, squash=1.0, subdiv=1, seed=0):
        """A lumpy icosphere: a tree's canopy, a hedge's top."""
        rng = random.Random(seed)
        tmp = bmesh.new()
        bmesh.ops.create_icosphere(tmp, subdivisions=subdiv, radius=radius)
        waves = [(Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized(),
                  rng.uniform(0, 6)) for _ in range(3)]
        for v in tmp.verts:
            n = v.co.normalized()
            v.co *= 1 + sum(0.07 * math.sin(3.2 * n.dot(d) + phase) for d, phase in waves)
            v.co.z *= squash
        mapping = {}
        for v in tmp.verts:
            mapping[v] = self.bm.verts.new(v.co + Vector(centre))
        for f in tmp.faces:
            nf = self.bm.faces.new([mapping[v] for v in f.verts])
            nf.material_index = self.slot(mat)
        tmp.free()

    def done(self):
        if self.layer == "middle":
            for v in self.bm.verts:
                v.co = Vector(mid_pt(*v.co))
        mesh = bpy.data.meshes.new(self.name)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for m in self.mats:
            mesh.materials.append(m)
        obj = bpy.data.objects.new(self.name, mesh)
        scene.collection.objects.link(obj)
        PARTS.append((obj, self.layer))
        return obj


# MARK: - Idol pieces

# Pieces made by FLUX -> Idol -> remesh_prop.py (an .obj, y up, front to +z, base centred, and its
# colour .png), used in place of the modelled ones when present. Their colours are already the
# night's, so the bake keeps them under the same white sky light and adds the lamps' pools.
IDOL_DIR = Path(__file__).resolve().parent.parent / "assets-source" / "street"
# kind: which measure fits, and the turn (degrees about up) that puts its front to the road.
IDOL_FIT = {
    "tree": ("height", 0), "mailbox": ("height", 0), "streetlamp": ("height", 0),
    "car": ("width", 0), "cottage": ("width", 0), "house2": ("width", 0), "shop": ("width", 0),
}
IDOL_YAW = {}
if (IDOL_DIR / "yaw.json").exists():
    IDOL_YAW = json.loads((IDOL_DIR / "yaw.json").read_text())


def idol(kind, name, layer, size, at, front=None):
    """Places the Idol `kind` as part `name`: its fit measure `size` units, standing on the ground
    at `at` (x, y), or with its front face on y = `front`. False when there is no such piece."""
    obj_path = IDOL_DIR / f"{kind}.obj"
    if not obj_path.exists():
        return False
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.wm.obj_import(filepath=str(obj_path), forward_axis="NEGATIVE_Z", up_axis="Y")
    obj = bpy.context.selected_objects[0]
    obj.name = name
    obj.rotation_euler = (0, 0, math.radians(IDOL_FIT[kind][1] + IDOL_YAW.get(kind, 0)))
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mesh = obj.data
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    measure = (max(zs) - min(zs)) if IDOL_FIT[kind][0] == "height" else max(max(xs) - min(xs), 0.01)
    k = size / measure
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    for v in mesh.vertices:
        x = at[0] + (v.co.x - cx) * k
        y = (front + (v.co.y - min(ys)) * k) if front is not None else at[1] + (v.co.y - cy) * k
        z = GROUND + (v.co.z - min(zs)) * k
        v.co = Vector(mid_pt(x, y, z) if layer == "middle" else (x, y, z))
    # Its own colour, read through its own UVs; the atlas is baked through new ones.
    mesh.uv_layers[0].name = "src"
    image = bpy.data.images.load(str(IDOL_DIR / f"{kind}.png"))
    mat = bpy.data.materials.new(f"idol-{kind}")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.95
    bsdf.inputs["Specular IOR Level"].default_value = 0.1
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = "src"
    colour = nodes.new("ShaderNodeTexImage")
    colour.image = image
    links.new(uv.outputs["UV"], colour.inputs["Vector"])
    links.new(colour.outputs["Color"], bsdf.inputs["Base Color"])
    target = nodes.new("ShaderNodeTexImage")
    target.image = ATLAS
    nodes.active = target
    mesh.materials.clear()
    mesh.materials.append(mat)
    atlas_uv = mesh.uv_layers.new(name="atlas")
    mesh.uv_layers.active = atlas_uv
    PARTS.append((obj, layer))
    return True


# Distances and how much atlas each layer gets per unit of surface, as a share of the near one.
WEIGHT = {"near": 1.0, "street": 0.8, "middle": 0.6, "ground": 0.3, "car": 1.2}


# MARK: - Ground, road and pavements

def build_ground():
    g = Part("ground", "ground")
    lawn = material("lawn", lit(PAL["near"], 0.06))
    far_lawn = material("far-lawn", lit(PAL["street"], 0.02))
    pave = material("pavement", lit(PAL["street"], 0.10))
    kerb = material("kerb", lit(PAL["street"], 0.16))
    road = material("road", mixed(lit(PAL["street"], -0.22), 0x070C18, 0.1))
    line = material("road-line", 0xE8D28A, emit=0.0)
    y = 0.0
    bands = [(0, 26, lawn), (26, 29, pave), (29, 29.3, kerb), (29.3, 40.7, road),
             (40.7, 41, kerb), (41, 44, pave), (44, 90, far_lawn)]
    for y0, y1, mat in bands:
        g.face([(-250, y0, GROUND), (250, y0, GROUND), (250, y1, GROUND), (-250, y1, GROUND)], mat)
    # The dashed middle line, a hair above the road.
    dim = material("road-line-dim", mixed(0xE8D28A, lit(PAL["street"], -0.22), 0.72))
    x = -248.0
    while x < 248:
        g.face([(x, 34.85, GROUND + 0.02), (x + 3.2, 34.85, GROUND + 0.02),
                (x + 3.2, 35.15, GROUND + 0.02), (x, 35.15, GROUND + 0.02)], dim)
        x += 7
    # A path from our gate to the pavement.
    g.face([(-2.2, 9, GROUND + 0.01), (2.2, 9, GROUND + 0.01), (2.2, 26, GROUND + 0.01),
            (-2.2, 26, GROUND + 0.01)], pave)
    g.done()


# MARK: - Near: the fence, the hedge, the tree, the mailbox

def build_near():
    p = Part("fence", "near")
    wood = material("fence", lit(PAL["near"], 0.14))
    rail = material("fence-rail", lit(PAL["near"], 0.08))
    fy = 9.0
    for x0, x1 in [(-46, -2.2), (2.2, 46)]:
        x = x0
        while x < x1 - 0.2:
            h = 1.9
            p.box(x, fy, GROUND, x + 0.3, fy + 0.14, GROUND + h, wood, skip=("bottom",))
            # A pointed top.
            p.face([(x, fy, GROUND + h), (x + 0.3, fy, GROUND + h), (x + 0.15, fy, GROUND + h + 0.28)], wood)
            p.face([(x + 0.3, fy + 0.14, GROUND + h), (x, fy + 0.14, GROUND + h),
                    (x + 0.15, fy + 0.14, GROUND + h + 0.28)], wood)
            x += 0.72
        for z in (GROUND + 0.5, GROUND + 1.4):
            p.box(x0, fy + 0.14, z, x1, fy + 0.28, z + 0.18, rail, skip=("bottom", "left", "right"))
    # Gate posts.
    for x in (-2.6, 2.2):
        p.box(x, fy - 0.1, GROUND, x + 0.4, fy + 0.3, GROUND + 2.5, rail, skip=("bottom",))
    p.done()

    h = Part("hedge", "near")
    leaf = material("hedge", lit(PAL["near"], 0.05))
    for k in range(8):
        h.blob((4.6 + k * 2.1, 11.2, GROUND + 1.4), 1.6, leaf, squash=0.85, subdiv=2, seed=10 + k)
    h.blob((-7.0, 11.0, GROUND + 1.0), 1.3, leaf, squash=0.8, seed=31)
    h.done()

    if not idol("tree", "tree", "near", 13.0, (-10.0, 14.0)):
        build_tree()
    if not idol("mailbox", "mailbox", "near", 3.6, (-13.05, 27.15)):
        build_mailbox()


def build_tree():
    t = Part("tree", "near")
    bark = material("bark", lit(PAL["near"], 0.02))
    canopy = material("canopy", mixed(lit(PAL["near"], 0.07), 0x0E2A2A, 0.35))
    tx, ty = -10.0, 14.0
    t.cylinder(tx, ty, GROUND, GROUND + 7.0, 0.45, bark, sides=7, top=False)
    t.box(tx - 0.15, ty - 0.15, GROUND + 4.5, tx + 3.0, ty + 0.15, GROUND + 4.8, bark)
    for k, (dx, dy, dz, r) in enumerate(
        [(0, 0, 9.0, 3.6), (2.8, -0.6, 8.2, 2.8), (-2.6, 0.8, 8.0, 2.9), (0.6, 1.4, 11.2, 2.6),
         (3.6, 0.2, 6.6, 1.9), (-1.2, -1.2, 6.9, 2.2)]
    ):
        t.blob((tx + dx, ty + dy, GROUND + dz), r, canopy, squash=0.9, subdiv=2, seed=50 + k)
    t.done()


def build_mailbox():
    m = Part("mailbox", "near")
    post = material("mail-post", lit(PAL["street"], -0.2))
    box = material("mail-box", lit(PAL["street"], 0.05))
    flag = material("mail-flag", mixed(PAL["porchRed"], PAL["near"], 0.45))
    m.box(-13.2, 27.0, GROUND, -12.9, 27.3, GROUND + 2.4, post, skip=("bottom",))
    m.box(-13.8, 26.6, GROUND + 2.4, -12.3, 27.7, GROUND + 3.1, box)
    m.cylinder(-13.05, 27.15, GROUND + 3.1, GROUND + 3.1, 0.75, box, sides=8)
    m.box(-12.3, 27.4, GROUND + 2.9, -12.2, 27.5, GROUND + 3.6, flag)
    m.done()


# MARK: - Street: the lamp and the parked car

LAMP_HEAD = (6.5, 42.0, GROUND + 8.6)
# Where the passing car is baked: in its far lane, clear of the lamp. It is exported centred.
MOVING = (24.0, 37.4)


def build_street():
    if idol("streetlamp", "lamp", "street", LAMP_HEAD[2] + 0.6 - GROUND, (LAMP_HEAD[0] + 0.8, LAMP_HEAD[1])):
        return
    s = Part("lamp", "street")
    metal = material("lamp-metal", lit(PAL["street"], -0.25))
    glass = material("lamp-glass", PAL["lampCore"], emit=4.0, emit_colour=PAL["lampCore"])
    x, y, z = LAMP_HEAD
    s.cylinder(x + 1.6, y, GROUND, z + 0.4, 0.22, metal, sides=6, top=False)
    s.cylinder(x + 1.6, y, GROUND, GROUND + 0.8, 0.42, metal, sides=6)
    s.box(x, y - 0.12, z + 0.3, x + 1.7, y + 0.12, z + 0.5, metal)
    s.box(x - 0.6, y - 0.45, z - 0.05, x + 0.6, y + 0.45, z + 0.35, metal, skip=("bottom",))
    s.box(x - 0.45, y - 0.32, z - 0.25, x + 0.45, y + 0.32, z - 0.05, glass)
    s.done()


def car(name, x, y, body_hex, layer):
    """A small rounded hatchback along x, nose to +x, wheels on the ground."""
    if idol("car", name, layer, 7.0, (x, y)):
        return bpy.data.objects[name]
    c = Part(name, layer)
    body = material(f"{name}-body", body_hex)
    dark = material("car-glass", mixed(PAL["near"], 0x3A5A86, 0.2))
    tyre = material("tyre", 0x05080E)
    head = material("headlight", PAL["lampCore"], emit=3.0)
    tail = material("taillight", 0xFF3B3B, emit=1.5)
    L, W = 7.0, 3.2
    z0 = GROUND + 0.55
    c.box(x - L / 2, y - W / 2, z0, x + L / 2, y + W / 2, z0 + 1.35, body)
    # Cabin with a sloped windscreen and back.
    cz = z0 + 1.35
    ch = 1.15
    pts = [(-1.9, 0), (2.0, 0), (1.1, ch), (-1.6, ch)]
    for sy in (y - W / 2 + 0.25, y + W / 2 - 0.25):
        c.face([(x + a, sy, cz + b) for a, b in pts], dark)
    for (a0, b0), (a1, b1), mat in [(pts[0], pts[3], dark), (pts[3], pts[2], body), (pts[2], pts[1], dark)]:
        c.face([(x + a0, y - W / 2 + 0.25, cz + b0), (x + a0, y + W / 2 - 0.25, cz + b0),
                (x + a1, y + W / 2 - 0.25, cz + b1), (x + a1, y - W / 2 + 0.25, cz + b1)], mat)
    for wx in (x - L / 2 + 1.4, x + L / 2 - 1.4):
        for wy in (y - W / 2 - 0.02, y + W / 2 - 0.5):
            tmp_y = wy
            c.box(wx - 0.62, tmp_y, GROUND, wx + 0.62, tmp_y + 0.52, GROUND + 1.25, tyre, skip=("bottom",))
    for sy in (y - W / 2 + 0.3, y + W / 2 - 0.9):
        c.box(x + L / 2, sy, z0 + 0.7, x + L / 2 + 0.05, sy + 0.6, z0 + 1.05, head)
        c.box(x - L / 2 - 0.05, sy, z0 + 0.75, x - L / 2, sy + 0.6, z0 + 1.05, tail)
    return c.done()


# MARK: - Middle: the houses across the road and the corner shop

SHOP_SPILL = []
WINDOWS_LIT = []
# Which houses across the road an Idol piece stands in for, when there is one.
IDOL_HOUSES = {"house-a": "cottage", "house-c": "cottage", "house-f": "cottage",
               "house-b": "house2", "house-e": "house2"}  # (x, y, z) of lit windows, for the porch-like glow of their light spilling out
PORCHES = []


def house(name, x0, width, depth, wall, rise, wall_hex, roof_hex, storeys, seed, garage=False):
    rng = random.Random(seed)
    kind = IDOL_HOUSES.get(name)
    if kind and idol(kind, name, "middle", width + (6 if garage else 0), (x0 + (width + (6 if garage else 0)) / 2, 0),
                     front=FRONT):
        return
    h = Part(name, "middle")
    y0, y1 = FRONT, FRONT + depth
    wall_m = material(f"wall", wall_hex)
    roof_m = material(f"roof", roof_hex)
    trim = material("trim", lit(wall_hex, 0.12))
    dark = material("window-dark", mixed(PAL["near"], PAL["horizon"], 0.12))
    warm = material("window-lit", PAL["lamp"], emit=1.6, emit_colour=PAL["lamp"])
    warm2 = material("window-lit-soft", mixed(PAL["lamp"], 0xFFE2B0, 0.5), emit=1.1,
                     emit_colour=mixed(PAL["lamp"], 0xFFE2B0, 0.5))
    tv = material("window-tv", PAL["tv"], emit=1.0, emit_colour=PAL["tv"])
    door_m = material("door", lit(wall_hex, -0.32))
    x1 = x0 + width
    h.box(x0, y0, GROUND, x1, y1, GROUND + wall, wall_m, skip=("bottom", "back"))
    h.gable(x0, y0, x1, y1, GROUND + wall, rise, roof_m, overhang=0.6, end=wall_m)
    # A chimney.
    cx = x0 + width * rng.uniform(0.62, 0.78)
    h.box(cx, y0 + depth * 0.35, GROUND + wall + rise * 0.3, cx + 1.0, y0 + depth * 0.35 + 1.0,
          GROUND + wall + rise + 1.0, roof_m, skip=("bottom",))
    # Windows on the face across the road: frames proud of the wall, panes a hair in front.
    rows = [GROUND + 1.6] if storeys == 1 else [GROUND + 1.4, GROUND + wall - 2.6]
    door_x = x0 + width * (0.18 if rng.random() < 0.5 else 0.62)
    for row, z in enumerate(rows):
        n = max(2, int(width // 4))
        for k in range(n):
            wx = x0 + width * (k + 0.5) / n - 0.85
            if row == 0 and abs(wx + 0.85 - (door_x + 0.8)) < 2.2:
                continue
            h.box(wx - 0.15, y0 - 0.12, z - 0.15, wx + 1.85, y0, z + 2.05, trim, skip=("back",))
            roll = rng.random()
            pane = tv if roll > 0.93 else warm if roll < 0.32 else warm2 if roll < 0.55 else dark
            h.face([(wx, y0 - 0.14, z), (wx + 1.7, y0 - 0.14, z), (wx + 1.7, y0 - 0.14, z + 1.9),
                    (wx, y0 - 0.14, z + 1.9)], pane)
            if pane is not dark:
                WINDOWS_LIT.append((wx + 0.85, y0 - 0.2, z + 0.9))
    # The door, its step and its porch light.
    h.box(door_x, y0 - 0.1, GROUND, door_x + 1.6, y0, GROUND + 3.0, door_m, skip=("back", "bottom"))
    h.box(door_x - 0.4, y0 - 1.0, GROUND, door_x + 2.0, y0, GROUND + 0.35, trim, skip=("bottom", "back"))
    porch = material("porch-lamp", PAL["lampCore"], emit=3.0)
    h.box(door_x + 2.05, y0 - 0.2, GROUND + 3.0, door_x + 2.35, y0, GROUND + 3.4, porch, skip=("back",))
    PORCHES.append(mid_pt(door_x + 2.2, y0 - 0.6, GROUND + 3.2))
    GLOWS.append(mid_pt(door_x + 2.2, y0 - 0.8, GROUND + 3.2) + (1.1 * MID_SCALE,))
    if garage:
        gx = x1
        h.box(gx, y0 + 0.5, GROUND, gx + 6, y1 - 1, GROUND + 3.8, wall_m, skip=("bottom", "back"))
        h.box(gx + 0.6, y0 + 0.4, GROUND, gx + 5.4, y0 + 0.5, GROUND + 3.1,
              material("garage-door", lit(wall_hex, 0.07)), skip=("back", "bottom"))
        h.box(gx - 0.2, y0 + 0.2, GROUND + 3.8, gx + 6.2, y1 - 0.8, GROUND + 4.1, roof_m)
    h.done()


def shop(name, x0, width):
    if idol("shop", name, "middle", width, (x0 + width / 2, 0), front=FRONT + 0.5):
        GLOWS.append(mid_pt(x0 + width / 2, FRONT - 1.0, GROUND + 2.2) + (3.2 * MID_SCALE,))
        SHOP_SPILL.append(mid_pt(x0 + width / 2, FRONT - 1.5, GROUND + 2.0))
        return
    s = Part(name, "middle")
    y0, y1 = FRONT + 0.5, FRONT + 9
    wall_hex = mixed(lit(PAL["middle"], 0.06), 0x3A2A30, 0.25)
    wall_m = material("shop-wall", wall_hex)
    trim = material("shop-trim", lit(wall_hex, 0.14))
    display = material("shop-window", mixed(PAL["lampCore"], PAL["lamp"], 0.3), emit=2.2)
    sign = material("shop-sign", mixed(PAL["porchRed"], 0xFFE2B0, 0.25), emit=1.4)
    stripe_a = material("awning-a", mixed(PAL["porchRed"], PAL["middle"], 0.35))
    stripe_b = material("awning-b", mixed(0xF6F0E2, PAL["middle"], 0.45))
    x1 = x0 + width
    top = GROUND + 7.5
    s.box(x0, y0, GROUND, x1, y1, top, wall_m, skip=("bottom", "back"))
    s.box(x0 - 0.2, y0 - 0.2, top, x1 + 0.2, y1, top + 0.5, trim, skip=("back",))
    # The shop front: two lit windows either side of a lit door.
    s.face([(x0 + 0.8, y0 - 0.05, GROUND + 0.6), (x0 + width * 0.42, y0 - 0.05, GROUND + 0.6),
            (x0 + width * 0.42, y0 - 0.05, GROUND + 3.6), (x0 + 0.8, y0 - 0.05, GROUND + 3.6)], display)
    s.face([(x0 + width * 0.58, y0 - 0.05, GROUND + 0.6), (x1 - 0.8, y0 - 0.05, GROUND + 0.6),
            (x1 - 0.8, y0 - 0.05, GROUND + 3.6), (x0 + width * 0.58, y0 - 0.05, GROUND + 3.6)], display)
    s.face([(x0 + width * 0.45, y0 - 0.05, GROUND), (x0 + width * 0.55, y0 - 0.05, GROUND),
            (x0 + width * 0.55, y0 - 0.05, GROUND + 3.2), (x0 + width * 0.45, y0 - 0.05, GROUND + 3.2)],
           material("shop-door", mixed(PAL["lamp"], wall_hex, 0.4), emit=0.9))
    s.box(x0 + 1.5, y0 - 0.3, GROUND + 5.0, x1 - 1.5, y0, GROUND + 6.2, sign, skip=("back",))
    GLOWS.append(mid_pt(x0 + width / 2, y0 - 1.5, GROUND + 2.2) + (3.2 * MID_SCALE,))
    GLOWS.append(mid_pt(x0 + width / 2, y0 - 0.8, GROUND + 5.6) + (2.2 * MID_SCALE,))
    SHOP_SPILL.append(mid_pt(x0 + width / 2, y0 - 2.0, GROUND + 2.0))
    # The flat upstairs windows.
    for k in range(3):
        wx = x0 + width * (k + 0.5) / 3 - 0.8
        lit_up = k != 1
        pane = material("window-lit", PAL["lamp"], emit=1.6, emit_colour=PAL["lamp"]) if lit_up else \
            material("window-dark", mixed(PAL["near"], PAL["horizon"], 0.12))
        s.face([(wx, y0 - 0.05, GROUND + 6.4), (wx + 1.6, y0 - 0.05, GROUND + 6.4),
                (wx + 1.6, y0 - 0.05, GROUND + 7.2), (wx, y0 - 0.05, GROUND + 7.2)], pane)
    # A striped awning sloping out over the pavement.
    n = 8
    for k in range(n):
        ax0 = x0 + 0.4 + (width - 0.8) * k / n
        ax1 = x0 + 0.4 + (width - 0.8) * (k + 1) / n
        mat = stripe_a if k % 2 == 0 else stripe_b
        s.face([(ax0, y0 - 2.6, GROUND + 3.9), (ax1, y0 - 2.6, GROUND + 3.9),
                (ax1, y0, GROUND + 4.9), (ax0, y0, GROUND + 4.9)], mat)
        s.face([(ax0, y0 - 2.6, GROUND + 3.4), (ax1, y0 - 2.6, GROUND + 3.4),
                (ax1, y0 - 2.6, GROUND + 3.9), (ax0, y0 - 2.6, GROUND + 3.9)], mat)
    s.done()


def build_middle():
    mid = PAL["middle"]
    # The note is taped over the window's middle, so the shop and the tall houses stand to its
    # sides and a low garage sits behind it.
    house("house-a", -46, 10, 9, 5.2, 3.6, lit(mid, 0.05), lit(mid, -0.12), 1, 1)
    house("house-b", -33, 9, 9, 7.5, 3.4, lit(mid, 0.09), lit(mid, -0.08), 2, 2)
    house("house-c", -21, 10, 9, 5.0, 3.8, lit(mid, 0.03), lit(mid, -0.14), 1, 3)
    house("house-d", -8, 9, 9, 5.4, 3.5, lit(mid, 0.07), lit(mid, -0.1), 1, 4, garage=True)
    shop("shop", 9.5, 12)
    house("house-e", 24.5, 9.5, 9, 7.4, 3.6, lit(mid, 0.04), lit(mid, -0.12), 2, 5)
    house("house-f", 37, 10, 9, 5.2, 3.4, lit(mid, 0.08), lit(mid, -0.1), 1, 6)
    # More of the street to either side, for the ends of an orbit.
    x = 50.0
    for k in range(5):
        width = 9 + (k % 3)
        house(f"house-r{k}", x, width, 9, 5.2 + 2.2 * (k % 2), 3.5, lit(mid, 0.03 + 0.02 * (k % 3)),
              lit(mid, -0.11), 1 + k % 2, 20 + k, garage=k == 2)
        x += width + (9 if k == 2 else 3.5)
    x = -49.0
    for k in range(6):
        width = 9 + ((k + 1) % 3)
        house(f"house-l{k}", x - width, width, 9, 5.0 + 2.4 * ((k + 1) % 2), 3.6,
              lit(mid, 0.04 + 0.02 * (k % 2)), lit(mid, -0.12), 1 + (k + 1) % 2, 40 + k)
        x -= width + 3.5
    # Trees behind and between the houses.
    t = Part("back-trees", "middle")
    leaf = material("back-tree", mixed(lit(mid, -0.04), 0x10302C, 0.25))
    for k, (x, y, r) in enumerate([(-35.5, 67, 3.2), (-10.5, 68, 3.6), (4.0, 69, 3.0), (22.5, 67, 3.4),
                                   (35.5, 68, 2.8), (-49, 66, 3.0), (48, 66, 3.3)]):
        t.cylinder(x, y, GROUND, GROUND + 5.5, 0.35, leaf, sides=5, top=False)
        t.blob((x, y, GROUND + 6.5 + r * 0.6), r, leaf, squash=1.1, subdiv=2, seed=70 + k)
    t.done()


# MARK: - Lights for the bake

def lights():
    world = bpy.data.worlds.new("sky")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1)
    bg.inputs["Strength"].default_value = 1.0

    def point(name, loc, colour, power, radius=0.3):
        data = bpy.data.lights.new(name, "POINT")
        data.color = srgb(colour)[:3]
        data.energy = power
        data.shadow_soft_size = radius
        obj = bpy.data.objects.new(name, data)
        obj.location = loc
        scene.collection.objects.link(obj)

    x, y, z = LAMP_HEAD
    point("street-lamp", (x, y, z - 0.5), PAL["lamp"], 2600, 0.4)
    for k, loc in enumerate(PORCHES):
        point(f"porch-{k}", loc, PAL["lamp"], 90, 0.2)
    for loc in SHOP_SPILL:
        point("shop-spill", loc, PAL["lampCore"], 260, 1.5)
    # Our own window, spilling the room's warm light onto the fence and the lawn.
    data = bpy.data.lights.new("our-window", "AREA")
    data.shape = "RECTANGLE"
    data.size, data.size_y = 6.4, 3.7
    data.color = srgb(PAL["lamp"])[:3]
    data.energy = 900
    obj = bpy.data.objects.new("our-window", data)
    obj.location = (0, 0.3, 0)
    obj.rotation_euler = (-math.pi / 2, 0, 0)
    scene.collection.objects.link(obj)
    moon = bpy.data.lights.new("moon", "SUN")
    moon.color = srgb(0xB8C8F0)[:3]
    moon.energy = 0.35
    moon.angle = 0.1
    mobj = bpy.data.objects.new("moon", moon)
    mobj.rotation_euler = (math.radians(50), math.radians(-25), math.radians(200))
    scene.collection.objects.link(mobj)


# MARK: - Unwrap, pack, bake

def area_3d(obj):
    return sum(p.area for p in obj.data.polygons)


def area_uv(obj):
    uv = obj.data.uv_layers.active.data
    total = 0.0
    for p in obj.data.polygons:
        pts = [uv[i].uv for i in p.loop_indices]
        for k in range(1, len(pts) - 1):
            a, b, c = pts[0], pts[k], pts[k + 1]
            total += abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2
    return total


def select_only(objs, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or objs[0]


def unwrap(parts):
    for obj, layer in parts:
        layers = obj.data.uv_layers
        if "atlas" not in layers:
            layers.new(name="atlas")
        layers.active = layers["atlas"]
        select_only([obj])
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.quads_convert_to_tris()
        bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.0)
        bpy.ops.object.mode_set(mode="OBJECT")
        # Each part's islands sized to its surface and how close it stands.
        scale = WEIGHT[layer] * math.sqrt(area_3d(obj) / max(area_uv(obj), 1e-9))
        for loop in obj.data.uv_layers.active.data:
            loop.uv *= scale
    objs = [o for o, _ in parts]
    select_only(objs)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, scale=True, margin=0.006)
    bpy.ops.object.mode_set(mode="OBJECT")


def bake(objs):
    select_only(objs)
    scene.cycles.bake_type = "COMBINED"
    scene.render.bake.use_clear = True
    scene.render.bake.margin = 6
    bpy.ops.object.bake(type="COMBINED")
    ATLAS.filepath_raw = str(OUT / "street-atlas.png")
    ATLAS.file_format = "PNG"
    ATLAS.save()


# MARK: - The window, the camera at home, and what can be seen through the window

# The room's numbers (GenzLayout.windowSeat, GenzCamera), in the room's scene space: y up.
WINDOW = dict(x0=0.6, x1=7.0, z0=1.3, z1=5.0, wall=0.35)
TARGET = Vector((4.3, 1.9, 2.4))
HOME = dict(yaw=0.34, pitch=0.42, distance=19.5, fov=40.0)


def eye(yaw, pitch, reach):
    flat = math.cos(pitch)
    return TARGET + reach * Vector((flat * math.sin(yaw), math.sin(pitch), flat * math.cos(yaw)))


def frame():
    """The view's frame in scene space: its origin at the window's middle, and its right, up and
    out (away from the home camera) axes."""
    origin = Vector(((WINDOW["x0"] + WINDOW["x1"]) / 2, (WINDOW["z0"] + WINDOW["z1"]) / 2, -WINDOW["wall"]))
    out = (origin - eye(HOME["yaw"], HOME["pitch"], HOME["distance"])).normalized()
    up = (Vector((0, 1, 0)) - out * out.y).normalized()
    right = out.cross(up)
    return origin, right, up, out


def to_view(p_scene):
    origin, right, up, out = frame()
    d = p_scene - origin
    return Vector((d.dot(right), d.dot(out), d.dot(up)))


def window_corners_scene():
    w = WINDOW
    return [Vector((x, z, -w["wall"])) for x, z in
            [(w["x0"], w["z1"]), (w["x1"], w["z1"]), (w["x1"], w["z0"]), (w["x0"], w["z0"])]]


def reach_through(distance):
    """What rays through the window from every camera the orbit allows meet at `distance` out:
    the x and z extent a card there must cover."""
    xs, zs = [], []
    corners = [to_view(c) for c in window_corners_scene()]
    for yaw in [-0.36 + 0.1 * k for k in range(21)]:
        for pitch in [0.12, 0.3, 0.42, 0.6, 0.86]:
            for zoom in [0.85, 1.0, 2.2]:
                e = to_view(eye(yaw, pitch, HOME["distance"] * zoom))
                for c in corners:
                    d = c - e
                    if d.y <= 0.01:
                        continue
                    t = (distance - e.y) / d.y
                    hit = e + d * t
                    xs.append(hit.x)
                    zs.append(hit.z)
    return min(xs), max(xs), min(zs), max(zs)


# MARK: - Cards

CARDS = [
    # name, distance, bottom, top: z extent of what is painted on it
    ("roofline", 120.0, GROUND, 14.0),
    ("skyline", 230.0, GROUND - 2, 34.0),
]
CARD_TEX = (4096, 1024)
# How far round to either side of straight out a card reaches. Past it the card fades out into
# the sky, which only the far ends of an orbit ever show.
CARD_REACH = math.radians(58)


def card_layout():
    """Each card's place in the cards texture, and the quad it is drawn on."""
    layout, top = [], 0
    for name, distance, bottom, height in CARDS:
        x0, x1, _, _ = reach_through(distance)
        side = math.tan(CARD_REACH) * distance
        x0, x1 = max(x0 - 10, -side), min(x1 + 10, side)
        px_h = int(round(CARD_TEX[0] * (height - bottom) / (x1 - x0) / 8)) * 8
        layout.append(dict(name=name, distance=distance, x0=x0, x1=x1, z0=bottom, z1=height,
                           px=[0, top, CARD_TEX[0], px_h]))
        top += px_h + 8
    # A glow sprite and the far ground's fade share the last strip.
    layout.append(dict(name="glow", px=[0, top, 128, 128]))
    layout.append(dict(name="ground", px=[136, top, 32, 128]))
    assert top + 128 <= CARD_TEX[1], f"cards need {top + 128} px rows"
    return layout


def uv_of(px, u, v):
    """Texture coordinates of the point (u, v) in a pixel rect, v from its top, flipped for USD."""
    x, y, w, h = px
    return ((x + u * w) / CARD_TEX[0], 1 - (y + v * h) / CARD_TEX[1])


def card_mesh(layout):
    verts, tris = [], []

    def quad(corners, uvs):
        base = len(verts)
        for p, t in zip(corners, uvs):
            verts.append((p, t))
        tris.extend([(base, base + 1, base + 2), (base, base + 2, base + 3)])

    # Drawn in this order, from the back, as one mesh: the transparent parts never hide what
    # stands behind them. The far ground runs from the end of the modelled ground to the far card.
    cards = sorted((c for c in layout if "distance" in c), key=lambda c: -c["distance"])
    ground = next(c for c in layout if c["name"] == "ground")
    far = cards[0]
    for card in cards:
        d, x0, x1, z0, z1 = card["distance"], card["x0"], card["x1"], card["z0"], card["z1"]
        quad([(x0, d, z1), (x1, d, z1), (x1, d, z0), (x0, d, z0)],
             [uv_of(card["px"], 0, 0), uv_of(card["px"], 1, 0), uv_of(card["px"], 1, 1),
              uv_of(card["px"], 0, 1)])
        if card is far:
            gx0, gx1 = far["x0"], far["x1"]
            quad([(gx0, d + 1, GROUND - 0.05), (gx1, d + 1, GROUND - 0.05),
                  (gx1, 79.5, GROUND - 0.05), (gx0, 79.5, GROUND - 0.05)],
                 [uv_of(ground["px"], 0, 0.02), uv_of(ground["px"], 1, 0.02),
                  uv_of(ground["px"], 1, 0.98), uv_of(ground["px"], 0, 0.98)])
    # Glows round the lamps: flat sprites turned to the home camera.
    glow = next(c for c in layout if c["name"] == "glow")
    home_eye = to_view(eye(HOME["yaw"], HOME["pitch"], HOME["distance"]))
    spots = [(LAMP_HEAD[0], LAMP_HEAD[1] - 0.6, LAMP_HEAD[2] - 0.3, 3.4)] + GLOWS
    for x, y, z, r in spots:
        c = Vector((x, y, z))
        to_eye = (home_eye - c).normalized()
        right = Vector((0, 0, 1)).cross(to_eye).normalized()
        up = to_eye.cross(right).normalized()
        cs = [c - right * r + up * r, c + right * r + up * r, c + right * r - up * r, c - right * r - up * r]
        quad([tuple(p) for p in cs],
             [uv_of(glow["px"], 0, 0), uv_of(glow["px"], 1, 0), uv_of(glow["px"], 1, 1),
              uv_of(glow["px"], 0, 1)])
    return verts, tris


# MARK: - Export

def mesh_of(obj, offset=(0.0, 0.0, 0.0)):
    """Triangles of `obj` as (position, uv) corners, one vertex per distinct pair, moved by
    `offset`."""
    mesh = obj.data
    uv = mesh.uv_layers.active.data
    index, verts, tris = {}, [], []
    for p in mesh.polygons:
        corner = []
        for li in p.loop_indices:
            co = tuple(round(c + o, 5) for c, o in zip(mesh.vertices[mesh.loops[li].vertex_index].co, offset))
            t = (round(uv[li].uv.x, 6), round(uv[li].uv.y, 6))
            key = (co, t)
            if key not in index:
                index[key] = len(verts)
                verts.append(key)
            corner.append(index[key])
        for k in range(1, len(corner) - 1):
            tris.append((corner[0], corner[k], corner[k + 1]))
    return verts, tris


def write_bin(path, meshes):
    """`BSV1`, a mesh count, then per mesh: a name (u8 length + utf-8), vertex and index counts
    (u32), vertices as x y z u v (f32, RealityKit's frame: x right, y up, z towards the camera),
    and u16 indices. Texture rows run down from the top, so v is flipped here."""
    with open(path, "wb") as f:
        f.write(b"BSV1")
        f.write(struct.pack("<I", len(meshes)))
        for name, (verts, tris) in meshes.items():
            assert len(verts) < 65536, name
            raw = name.encode()
            f.write(struct.pack("<B", len(raw)))
            f.write(raw)
            f.write(struct.pack("<II", len(verts), len(tris) * 3))
            for (x, y, z), (u, v) in verts:
                f.write(struct.pack("<5f", x, z, -y, u, 1 - v))
            for t in tris:
                f.write(struct.pack("<3H", *t))


def join(objs, name):
    select_only(objs)
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.uv_layers.active = obj.data.uv_layers["atlas"]
    return obj


def main():
    build_ground()
    build_near()
    build_street()
    build_middle()
    parked = car("car-parked", -11.0, 32.4, mixed(lit(PAL["street"], -0.3), 0x5A2430, 0.4), "street")
    moving = car("car", MOVING[0], MOVING[1], mixed(lit(PAL["street"], -0.3), 0x23324A, 0.5), "car")
    lights()
    unwrap(PARTS)
    objs = [o for o, _ in PARTS]
    bake(objs)
    street = join([o for o in objs if o.name != "car"], "street")
    layout = card_layout()
    card_verts, card_tris = card_mesh(layout)
    meshes = {"street": mesh_of(street), "car": mesh_of(moving, (-MOVING[0], -MOVING[1], 0.0)), "cards": (card_verts, card_tris)}
    write_bin(OUT / "street.bin", meshes)
    origin, right, up, out = frame()
    info = dict(
        cards=layout, ground=GROUND, lamp=LAMP_HEAD, porches=PORCHES,
        road=dict(lanes=[32.6, 37.4], ground=GROUND),
        frame=dict(origin=list(origin), right=list(right), up=list(up), out=list(out)),
        tris={k: len(t) for k, (_, t) in meshes.items()},
    )
    (OUT / "cards.json").write_text(json.dumps(info, indent=1))
    print("STREET", info["tris"], "cards", [(c["name"], c.get("px")) for c in layout])


main()
