"""Builds Nibbles, the golden Syrian hamster, in Blender and exports it as USDZ.

Run:
  blender -b --python Tools/make_hamster.py -- Nooki/Resources/Hamster.usdz [preview.png [portrait.png]]

Modelled after the turnaround sheet in docs/hamster/turnaround.png: a squat pear with no neck,
big round mouse ears on the top corners, black bead eyes on the orange/cream border, a cream
front that runs unbroken from the cheeks to the feet and a golden back, short cream arms
holding a sunflower seed at the chest and two soft pink feet. Same pipeline as Mochi the cat
(Tools/make_cat.py):

1. Body = a signed distance field: a squat egg (wide hips, broad crown, upright face) smoothly
   merged with big cheek pads, a small muzzle, forehead and belly; a dense sphere is
   shrink-wrapped onto it.
2. Coat (golden back, cream front, blush) painted into vertex colors with smooth falloffs.
3. Arms and ear backs are joined into the body so they share its fur and ambient occlusion.
4. Eyes, highlights, inner ears, paws, feet, nose, mouth and the seed are small separate meshes.
5. Tools/plush.py bakes strands that follow the coat's growth direction, plus ambient
   occlusion from all the details, into 1024 color + normal textures, so RealityKit only
   sees plain image-textured PBR.

Blender space: Z up, the hamster faces +Y, units are meters.
"""

import math
import os
import sys
import tempfile

import bpy
from mathutils import Matrix, Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import plush  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:]
OUT_USDZ = args[0]
OUT_PNG = args[1] if len(args) > 1 else None
OUT_PORTRAIT = args[2] if len(args) > 2 else None
TEXTURE_SIZE = 1024

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
collection = scene.collection


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgb(hex_color):
    return Vector([srgb_to_linear(((hex_color >> s) & 0xFF) / 255) for s in (16, 8, 0)])


def new_material(name):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except AttributeError:
        pass
    return m


def flat_material(name, hex_color, roughness):
    m = new_material(name)
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb(hex_color), 1)
    bsdf.inputs["Roughness"].default_value = roughness
    return m


def emissive_material(name, hex_color, strength):
    m = new_material(name)
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb(hex_color), 1)
    bsdf.inputs["Roughness"].default_value = 0.2
    bsdf.inputs["Emission Color"].default_value = (*rgb(hex_color), 1)
    bsdf.inputs["Emission Strength"].default_value = strength
    return m


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


GOLD = rgb(0xEBA04A)
GOLD_DEEP = rgb(0xDF903C)
CREAM = rgb(0xFAF1E4)
BLUSH = rgb(0xF4A0AA)
STRIPE = rgb(0xD98330)

NOSE_PINK = flat_material("Nose", 0xF2A0AA, 0.4)
PAW = flat_material("Paw", 0xF5B9B6, 0.7)
MOUTH_INK = flat_material("Mouth", 0x7A4A35, 0.55)
GLINT = emissive_material("Glint", 0xFFFFFF, 5.0)

# ---------------------------------------------------------------- body

# Measured from docs/hamster/turnaround.png (front and side views), in meters.
HALF_W = 0.0515   # half width at the belly: the widest part of the body
HALF_D = 0.046     # half depth, front to back
HEIGHT = 0.106     # crown height without the ears
FLOOR = 0.002

# A squat pear with big cheek pads, a small muzzle and a round belly as soft swellings on its
# front. The cheeks sit low, at the bottom edge of the eyes, so they widen the face.
EGG_CENTER = Vector((0.0, 0.0, HEIGHT * 0.5))
CHEEKS = [Vector((s * 0.029, 0.034, 0.058)) for s in (-1, 1)]
MUZZLE = Vector((0.0, 0.040, 0.062))
SWELLINGS = [
    (CHEEKS[0], (0.022, 0.016, 0.019)),
    (CHEEKS[1], (0.022, 0.016, 0.019)),
    (MUZZLE, (0.013, 0.012, 0.0115)),
    (Vector((0.0, 0.016, 0.084)), (0.026, 0.024, 0.019)),   # forehead: keeps the face upright in profile
    (Vector((0.0, 0.020, 0.030)), (0.033, 0.026, 0.027)),   # round belly
    (Vector((-0.026, 0.020, 0.016)), (0.016, 0.014, 0.013)),  # haunch over each hind foot
    (Vector((0.026, 0.020, 0.016)), (0.016, 0.014, 0.013)),
]
BLEND = 0.008


def ellipsoid_sdf(p, center, radii):
    q = Vector(((p.x - center[0]) / radii[0], (p.y - center[1]) / radii[1], (p.z - center[2]) / radii[2]))
    return (q.length - 1.0) * min(radii)


EGG_POWER = 2.0   # a plain superellipse: round sides without boxy shoulders


def egg_sdf(p):
    zn = (p.z - EGG_CENTER.z) / (HEIGHT * 0.5)
    z_shape = zn if zn >= 0 else zn * 0.65     # keeps the base full: a squat pear, not an egg
    t = smoothstep(-0.4, 1.0, zn)
    q = p - EGG_CENTER
    s = 1.03 - 0.15 * t                                    # an egg: the hips are wider than the crown
    s_y = s if q.y < 0 else 1.03 - 0.06 * t                # but the face stays upright, not sloped back
    k = ((abs(q.x) / (HALF_W * s)) ** EGG_POWER + (abs(q.y) / (HALF_D * s_y)) ** EGG_POWER
         + abs(z_shape) ** EGG_POWER) ** (1 / EGG_POWER)
    return (k - 1.0) * HALF_D


def body_sdf(p):
    d = egg_sdf(p)
    for center, radii in SWELLINGS:   # polynomial smooth minimum
        e = ellipsoid_sdf(p, center, radii)
        h = max(BLEND - abs(d - e), 0.0) / BLEND
        d = min(d, e) - h * h * BLEND * 0.25
    return max(d, FLOOR - p.z)   # flat seat


# A dense sphere is shrink-wrapped onto that surface by bisecting each vertex's ray.
INSIDE = Vector((0.0, 0.004, 0.053))
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=6, radius=1.0)
body = bpy.context.active_object
body.name = "Body"
for v in body.data.vertices:
    d = v.co.normalized()
    lo, hi = 0.0, 0.12
    for _ in range(26):
        mid = (lo + hi) / 2
        if body_sdf(INSIDE + d * mid) < 0:
            lo = mid
        else:
            hi = mid
    v.co = INSIDE + d * lo
body.data.update()
mod = body.modifiers.new("Relax", "SMOOTH")   # soften the crease the flat seat leaves
mod.factor = 0.5
mod.iterations = 4
bpy.ops.object.modifier_apply(modifier="Relax")
bpy.ops.object.shade_smooth()

NOSE_TIP = MUZZLE + Vector((0.0, 0.012, 0.002))


def fur_flow(p):
    """Hamster fur grows back from the nose and drapes down over the body."""
    return (p - NOSE_TIP).normalized() + Vector((0.0, -0.25, -0.55))


plush.set_flow(body.data, fur_flow)
tex_dir = tempfile.mkdtemp(prefix="nibbles_")

# ---------------------------------------------------------------- details placement helpers

FRONT = Vector((0, -1, 0))   # rays travel toward the face from the front


def surface(point, direction):
    hit, loc, normal, _ = body.ray_cast(point - direction * 0.3, direction)
    if not hit:
        _, loc, normal, _ = body.closest_point_on_mesh(point)
    return loc, normal


EYE_X, EYE_Z = 0.018, 0.069
eye_spots = [surface(Vector((s * EYE_X, 0, EYE_Z)), FRONT) for s in (-1, 1)]
blush_spots = [surface(Vector((s * 0.030, 0, 0.058)), FRONT)[0] for s in (-1, 1)]

# ---------------------------------------------------------------- coat pattern


def forehead_stripe(p):
    """Faint darker lanes running from between the ears down toward the eyes."""
    if p.z < 0.066 or p.y <= 0.0:
        return 0.0
    band = smoothstep(0.068, 0.078, p.z) * (1 - smoothstep(0.094, 0.104, p.z))
    lanes = max(1 - smoothstep(0.0012, 0.0022, abs(p.x - c)) for c in (-0.013, 0.0, 0.013))
    return band * lanes * smoothstep(0.0, 0.30, p.y / HALF_D)


def coat_color(p):
    """Orange crown and back; one continuous cream mask over the face, chin, chest and belly."""
    jitter = noise.noise(p * 120) * 0.0012
    # the border runs under the eyes and drops into a soft V between them, above the nose
    border = 0.066 - 0.0022 * (1 - smoothstep(0.0, 0.012, abs(p.x)))
    below = 1 - smoothstep(border - 0.003, border + 0.003, p.z + jitter)
    # cream wraps the front ~70% of the width and leaves the back orange
    radius = math.hypot(p.x, p.y)
    front = smoothstep(0.62, 0.78, p.y / max(radius, 1e-6))
    cream = front * below

    ny = p.y / HALF_D
    spine = smoothstep(0.1, -0.9, ny) * 0.45   # a touch deeper along the back
    color = GOLD.lerp(GOLD_DEEP, spine)
    color = color.lerp(STRIPE, forehead_stripe(p) * 0.35)
    color = color.lerp(CREAM, cream)
    blush = max(1 - smoothstep(0.003, 0.009, (p - b).length + jitter * 2) for b in blush_spots)
    return color.lerp(BLUSH, blush * 0.55)


attr = body.data.color_attributes.new("Coat", "FLOAT_COLOR", "POINT")
for v, c in zip(body.data.vertices, attr.data):
    col = coat_color(v.co)
    c.color = (col.x, col.y, col.z, 1)

# ---------------------------------------------------------------- sunflower seed

SEED_DARK = Vector([((0x463A31 >> s) & 0xFF) / 255 for s in (16, 8, 0)])
SEED_GREY = Vector([((0xB8ADA0 >> s) & 0xFF) / 255 for s in (16, 8, 0)])


def seed_material():
    size = 256
    img = bpy.data.images.new("SeedCoat", size, size, alpha=False)
    px = [0.0] * (size * size * 4)
    for y in range(size):
        v = y / (size - 1)
        for x in range(size):
            u = x / (size - 1)
            band = math.cos(2 * math.pi * (u * 6.0 + 0.10 * math.sin(v * math.pi * 2)))
            stripe = smoothstep(0.10, 0.75, band)
            shade = 0.86 + 0.18 * math.sin(v * math.pi)
            c = SEED_DARK.lerp(SEED_GREY, stripe * 0.8) * shade
            i = (y * size + x) * 4
            px[i:i + 4] = [c.x, c.y, c.z, 1.0]
    # 8-bit generated images store the values as-is, so write plain sRGB bytes here.
    img.pixels = px
    img.filepath_raw = os.path.join(tex_dir, "seed_coat.png")
    img.file_format = "PNG"
    img.save()

    m = new_material("Seed")
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.45
    bsdf.inputs["Specular IOR Level"].default_value = 0.6
    tex = m.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return m


SEED = seed_material()

# ---------------------------------------------------------------- details


def orient(obj, normal, tangent=Vector((1, 0, 0))):
    """Local +Y along the normal, local +X as close to the tangent as possible."""
    y = normal.normalized()
    x = (tangent - y * tangent.dot(y)).normalized()
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Matrix((x, y, x.cross(y))).transposed().to_quaternion()


def sphere(name, radius, mat, scale=(1, 1, 1), segments=24, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=segments, ring_count=rings)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return obj


def stroke(name, points, radius, mat):
    """Smooth ink stroke in the local XZ plane (local +Y is the surface normal)."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 3
    curve.use_fill_caps = True
    spline = curve.splines.new("NURBS")
    spline.points.add(len(points) - 1)
    for sp, (x, z) in zip(spline.points, points):
        sp.co = (x, 0, z, 1)
    spline.use_endpoint_u = True
    spline.order_u = 3
    spline.resolution_u = 10
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


parts = []
UP = Vector((0, 0, 1))
EYE = plush.eye_material("NibblesEye", tex_dir, 0x16100D)
EAR_INNER = plush.gradient_material("NibblesEarInner", tex_dir, 0xF2A9AE, 0xF7C6C6)
FUR_PART = new_material("FurPart")   # replaced by the body's baked fur once joined
furred = []      # arms and ear backs, merged into the body before baking
arm_dirs = {}

# --- eyes: near-black glossy beads sitting on the orange/cream border
for side, (loc, n) in zip((-1, 1), eye_spots):
    eye = sphere(f"Eye{side}", 0.0050, EYE, (1.0, 0.68, 1.05), 32, 16)
    plush.planar_eye_uv(eye, 0.0050)
    eye.location = loc + n * 0.0006
    orient(eye, n)
    parts.append(eye)
    glint_dir = (n * 0.55 + UP * 0.65 + Vector((side * 0.50, 0, 0))).normalized()
    glint = sphere(f"Glint{side}", 0.0015, GLINT, (1, 1, 1), 14, 8)
    glint.location = eye.location + glint_dir * 0.0036
    parts.append(glint)

# --- nose: a small rounded inverted triangle on the cream
loc, n = surface(Vector((0.0, 0, 0.060)), FRONT)
nose = sphere("Nose", 0.00325, NOSE_PINK, (1.0, 0.62, 0.692), 24, 12)
for v in nose.data.vertices:   # taper the bottom into a rounded point
    v.co.x *= 0.30 + 0.70 * smoothstep(-0.9, 0.9, v.co.z / 0.00325)
nose.data.update()
nose.location = loc + n * 0.0009
orient(nose, n)
parts.append(nose)

loc, n = surface(Vector((0.0, 0, 0.0547)), FRONT)
mouth = stroke("Mouth", [(-0.0045, 0.0012), (-0.0031, -0.0008), (-0.0014, 0.0002),
                         (0.0, 0.0010), (0.0014, 0.0002), (0.0031, -0.0008), (0.0045, 0.0012)],
               0.00038, MOUTH_INK)
mouth.location = loc + n * 0.0005
orient(mouth, n)
parts.append(mouth)
philtrum = stroke("Philtrum", [(0.0, 0.0016), (0.0, 0.0029)], 0.00030, MOUTH_INK)
philtrum.location = loc + n * 0.0005
orient(philtrum, n)
parts.append(philtrum)

# --- ears: two big round cups on the top corners, turned out and slightly forward
ear_spots = []   # kept clear of render fuzz so the pink insides show
for side in (-1, 1):
    n_ear = Vector((side * 0.55, 0.80, 0.24)).normalized()
    ear = sphere(f"Ear{side}", 0.021, FUR_PART, (1.0, 0.40, 1.0), 32, 16)
    ear.location = Vector((side * 0.034, 0.004, 0.100))
    ear_spots.append(ear.location.copy())
    orient(ear, n_ear, tangent=UP)
    furred.append(ear)
    inner = sphere(f"EarInner{side}", 0.0168, EAR_INNER, (1.0, 0.26, 1.0), 28, 14)
    plush.planar_eye_uv(inner, 0.0168)
    inner.location = ear.location + n_ear * 0.0046
    orient(inner, n_ear, tangent=UP)
    parts.append(inner)

# --- sunflower seed held upright at the chest
SEED_POS = surface(Vector((0.0, 0, 0.043)), FRONT)[0] + Vector((0, 0.0038, 0))
seed = sphere("Seed", 1.0, SEED, (0.0047, 0.0032, 0.0100), 32, 16)
seed.location = SEED_POS
seed.rotation_mode = "XYZ"
seed.rotation_euler = (math.radians(-10), 0, math.radians(-8))
parts.append(seed)

# --- short cream arms hugging the chest, pink mittens and fingers around the seed
for side in (-1, 1):
    shoulder = Vector((side * 0.024, 0.030, 0.050))
    wrist = Vector((SEED_POS.x + side * 0.0068, SEED_POS.y - 0.001, SEED_POS.z - 0.001))
    arm_dir = (wrist - shoulder).normalized()
    arm = sphere(f"Arm{side}", 1.0, FUR_PART, (0.0065, 0.0060, 0.0105), 24, 12)
    arm.location = shoulder.lerp(wrist, 0.45)   # the shoulder end stays buried in the chest
    arm.rotation_mode = "QUATERNION"
    arm.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(arm_dir)
    furred.append(arm)
    arm_dirs[arm.name] = arm_dir
    paw = sphere(f"Paw{side}", 1.0, PAW, (0.0034, 0.0030, 0.0042), 20, 10)
    paw.location = wrist + arm_dir * 0.0015
    paw.rotation_mode = "QUATERNION"
    paw.rotation_quaternion = arm.rotation_quaternion   # the mitten continues the arm
    parts.append(paw)
    for k in range(4):   # tiny fingers wrapping around the front edge of the seed
        f = sphere(f"Finger{side}{k}", 0.0010, PAW, (1, 1, 1.3), 12, 6)
        f.location = Vector((side * 0.0039, SEED_POS.y + 0.0023, SEED_POS.z + 0.0033 - 0.0022 * k))
        parts.append(f)

# --- pink hind feet: toes forward, the back half tucked under the body
for side in (-1, 1):
    foot = sphere(f"Foot{side}", 1.0, PAW, (0.0060, 0.0090, 0.0032), 24, 12)
    foot.location = Vector((side * 0.022, 0.0335, 0.0035))
    turn = math.radians(side * 10)
    foot.rotation_mode = "XYZ"
    foot.rotation_euler = (0, 0, turn)
    parts.append(foot)
    for k in range(3):   # three toes on the front edge, half sunk into the foot
        toe = sphere(f"Toe{side}{k}", 0.0016, PAW, (1, 1, 1), 12, 6)
        dx = (k - 1) * 0.0030
        toe.location = foot.location + Vector((dx * math.cos(turn) - 0.0082 * math.sin(turn),
                                               dx * math.sin(turn) + 0.0082 * math.cos(turn),
                                               -0.0005))
        parts.append(toe)

for obj in parts:
    if obj.type == "CURVE":
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target="MESH")
        bpy.ops.object.shade_smooth()

def part_coat(part, p):
    return CREAM if part.name.startswith("Arm") else GOLD


def part_flow(part, p):
    return arm_dirs.get(part.name, UP)


plush.join_furred(body, furred, part_coat, part_flow)
plush.bake_plush_coat(body, tex_dir, "Nibbles", TEXTURE_SIZE, strand_scale=1400.0,
                      strand_length=3.0, bump_strength=0.25, ao_strength=0.45, ao_distance=0.016,
                      strand_contrast=0.10)

root = bpy.data.objects.new("Nibbles", None)
collection.objects.link(root)
for obj in [body, *parts]:
    obj.parent = root

# ---------------------------------------------------------------- export

body.data.color_attributes.remove(body.data.color_attributes["Coat"])
body.data.attributes.remove(body.data.attributes["Flow"])
bpy.ops.object.select_all(action="SELECT")
bpy.ops.wm.usd_export(
    filepath=OUT_USDZ,
    export_materials=True,
    generate_preview_surface=True,
    export_uvmaps=True,
    export_animation=False,
    convert_orientation=True,
    export_global_forward_selection="NEGATIVE_Z",
    export_global_up_selection="Y",
    evaluation_mode="RENDER",
)
faces = sum(len(o.data.polygons) for o in [body, *parts] if o.type == "MESH")
corners = [o.matrix_world @ Vector(c) for o in [body, *parts] if o.type == "MESH" for c in o.bound_box]
lo = Vector((min(c[i] for c in corners) for i in range(3)))
hi = Vector((max(c[i] for c in corners) for i in range(3)))
print("EXPORTED", OUT_USDZ, faces, "faces")
print("BOUNDS", tuple(round(v, 4) for v in lo), tuple(round(v, 4) for v in hi))


def add_render_fuzz(obj):
    """A short felt coat of legacy hair, for the preview and portrait renders only: it is added
    after the USDZ export and never reaches the app."""
    fuzz_len = 0.0008
    m = obj.modifiers.new("Fuzz", "PARTICLE_SYSTEM")
    s = m.particle_system.settings
    s.type = "HAIR"
    s.count = 120000
    s.child_type = "INTERPOLATED"
    s.rendered_child_count = 4
    s.child_length = 1.0
    s.roughness_2 = 0.08 * fuzz_len     # Blender reads these as meters, not fractions
    s.roughness_endpoint = 0.04 * fuzz_len
    s.root_radius = 0.00004
    s.tip_radius = 0.0            # meters, with radius_scale 1.0
    s.radius_scale = 1.0
    s.use_advanced_hair = True
    s.use_rotations = True
    s.normal_factor = 1.0
    m.particle_system.seed = 7
    s.hair_length = fuzz_len   # assigned last: 5.2 otherwise builds the paths at the 4.0 default

    # No fuzz grow over the ear cups or the face details, so the pink insides and the
    # eyes, nose and mouth stay readable under the coat; the density eases back in just
    # outside each clearing so the coat does not end in a shaved ring.
    clear = [(p, 0.024, 0.030) for p in ear_spots]
    clear += [(p, 0.006, 0.009) for p in [loc for loc, _ in eye_spots] + [nose.location, mouth.location]]
    group = obj.vertex_groups.new(name="FuzzDensity")
    for v in obj.data.vertices:
        weight = 1.0
        for spot, inner, outer in clear:
            weight = min(weight, smoothstep(inner, outer, (v.co - spot).length))
        group.add([v.index], weight, "REPLACE")
    m.particle_system.vertex_group_density = group.name

    # The hairs sample the baked coat under them, so they keep the orange/cream pattern,
    # slightly lifted and self-lit so the ivory does not read grey in shadow.
    source = next(n for n in obj.data.materials[0].node_tree.nodes if n.type == "TEX_IMAGE")
    mat = new_material("NibblesFuzz")
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.95
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = obj.data.uv_layers[0].name
    uv.from_instancer = True
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = source.image
    lift = nodes.new("ShaderNodeMixRGB")
    lift.blend_type = "MULTIPLY"
    lift.inputs["Factor"].default_value = 1.0
    lift.inputs["Color2"].default_value = (1.12, 1.12, 1.12, 1.0)
    links.new(uv.outputs["UV"], tex.inputs["Vector"])
    links.new(tex.outputs["Color"], lift.inputs["Color1"])
    links.new(lift.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(lift.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 0.08
    obj.data.materials.append(mat)
    s.material = len(obj.data.materials)

# ---------------------------------------------------------------- preview

if OUT_PNG:
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.36, 0.25, 0.18, 1)
    bg.inputs["Strength"].default_value = 0.35
    scene.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(18)
    sun.data.color = (1.0, 0.91, 0.80)
    sun.rotation_euler = (math.radians(52), 0, math.radians(-38))
    collection.objects.link(sun)
    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "AREA"))
    fill.data.energy = 2.2
    fill.data.size = 0.5
    fill.data.color = (0.95, 0.96, 1.0)
    fill.location = Vector((-0.28, 0.42, 0.20))
    fill.rotation_euler = (Vector((0, 0.02, 0.055)) - fill.location).to_track_quat("-Z", "Y").to_euler()
    collection.objects.link(fill)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 85
    collection.objects.link(cam)
    target = Vector((0.0, 0.004, 0.058))
    cam.location = target + Vector((0.42, 0.92, 0.30)).normalized() * 0.50
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (target - cam.location).to_track_quat("-Z", "Y")
    scene.camera = cam
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = False
    scene.render.resolution_x = 800
    scene.render.resolution_y = 800
    scene.render.filepath = OUT_PNG
    add_render_fuzz(body)
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", OUT_PNG)

# ---------------------------------------------------------------- portrait for the app's pet card

if OUT_PNG and OUT_PORTRAIT:
    face = Vector((0.0, 0.020, 0.0755))
    cam.data.lens = 85
    cam.location = Vector((0.0, 0.310, 0.076))
    cam.rotation_quaternion = (face - cam.location).to_track_quat("-Z", "Y")
    key = bpy.data.objects.new("Key", bpy.data.lights.new("Key", "AREA"))
    key.data.energy = 1.25
    key.data.size = 0.22
    key.data.color = (1.0, 0.92, 0.82)
    key.location = face + Vector((-0.22, 0.26, 0.22))
    key.rotation_euler = (face - key.location).to_track_quat("-Z", "Y").to_euler()
    collection.objects.link(key)
    fill = bpy.data.objects.new("PortraitFill", bpy.data.lights.new("PortraitFill", "AREA"))
    fill.data.energy = 0.50
    fill.data.size = 0.45
    fill.data.color = (1.0, 0.95, 0.90)
    fill.location = face + Vector((0.34, 0.16, 0.08))
    fill.rotation_euler = (face - fill.location).to_track_quat("-Z", "Y").to_euler()
    collection.objects.link(fill)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
    scene.view_settings.view_transform = "Standard"   # keeps the cream warm ivory, not AgX grey
    scene.render.film_transparent = True
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.filepath = OUT_PORTRAIT
    bpy.ops.render.render(write_still=True)
    print("PORTRAIT", OUT_PORTRAIT)
