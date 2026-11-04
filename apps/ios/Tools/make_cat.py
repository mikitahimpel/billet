"""Builds Mochi, the sleeping tabby kitten, in Blender and exports it as USDZ.

Run:
  blender -b --python Tools/make_cat.py -- Nooki/Resources/Cat.usdz [preview.png [portrait.png]]

Look follows the app's reference art: a gray tabby kitten curled up asleep, white muzzle,
chest and paws, pink ears, red collar with a gold bell. Proportions borrow from
"Chill Cat" by Shix (CC BY 4.0): one soft blob where head and body melt together.

Pipeline:
1. Body = one metaball family (head, muzzle, cheeks, chest, paws, tail) -> seamless mesh.
2. Small fur clumps roughen the silhouette on the cheeks, chest and tail.
3. Coat pattern painted into vertex colors with soft falloffs (stripes, socks, blush).
4. Ears, closed eyes with lashes, nose, mouth, toe beans, collar and bell are separate meshes;
   the ear backs are merged into the body so they share its fur.
5. Tools/plush.py bakes strands that follow the coat's growth direction, plus ambient
   occlusion from all the details, into color + normal textures, so RealityKit gets plain
   image-textured PBR.

Blender space: Z up, the kitten faces +Y, units are meters.
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


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


COAT = rgb(0xC9C3BE)
STRIPE = rgb(0x6F6863)
WHITE = rgb(0xFBF7F2)
BLUSH = rgb(0xF4A3A0)

PINK = flat_material("Pink", 0xF4A9AA, 0.55)
EAR_PINK = flat_material("EarPink", 0xF8BDB8, 0.7)
INK = flat_material("Ink", 0x3A2A24, 0.45)
RED = flat_material("Collar", 0xD8483F, 0.5)
GOLD = flat_material("Bell", 0xF0C04A, 0.22)
GOLD.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 1.0
SLOT = flat_material("BellSlot", 0x5A3A12, 0.5)
FUR_PART = new_material("FurPart")   # replaced by the body's baked fur once joined

# ---------------------------------------------------------------- body

HEAD = Vector((0.04, 0.06, 0.105))
MUZZLE = HEAD + Vector((0.0, 0.050, -0.028))
CHEST = Vector((0.045, 0.02, 0.06))
PAWS = [Vector((0.0, 0.125, 0.025)), Vector((0.075, 0.125, 0.025))]
HIND_PAW = Vector((-0.1, 0.05, 0.025))
CURL = Vector((-0.01, 0.0, 0.0))

mb = bpy.data.metaballs.new("Body")
mb.resolution = 0.0025
mb.render_resolution = 0.0025
mb.threshold = 0.6
mb_obj = bpy.data.objects.new("Body", mb)
collection.objects.link(mb_obj)


def ball(co, r, size=(1, 1, 1)):
    e = mb.elements.new(type="ELLIPSOID")
    e.co = co
    e.radius = r
    e.stiffness = 2.0
    e.size_x, e.size_y, e.size_z = size


# Metaball surfaces sit at roughly 0.7 x radius once neighbours blend in.
ball((-0.075, -0.035, 0.06), 0.12, (1.0, 1.0, 0.8))     # haunch
ball((-0.01, -0.03, 0.062), 0.13, (1.15, 1.0, 0.78))    # back
ball(CHEST, 0.11, (1.0, 1.0, 0.85))                     # chest
ball(HEAD, 0.132, (1.2, 1.0, 0.97))                     # big kawaii kitten head
ball(MUZZLE, 0.046, (1.3, 0.85, 0.78))                  # short soft snout
for side in (-1, 1):
    ball(HEAD + Vector((side * 0.056, 0.03, -0.03)), 0.066)  # round cheek buns
for p in PAWS:
    ball(p, 0.05, (0.8, 1.25, 0.6))
ball(HIND_PAW, 0.05, (1.2, 0.8, 0.6))
TAIL = []
for i in range(14):
    t = i / 13
    a = math.radians(205 - 128 * t)
    r = 0.13 + 0.012 * smoothstep(0.7, 1.0, t)
    p = Vector((CURL.x + r * math.cos(a), CURL.y + r * math.sin(a), 0.032 + 0.012 * smoothstep(0.75, 1.0, t)))
    TAIL.append((p, t))
    ball(p, 0.05 - 0.012 * t)

bpy.context.view_layer.objects.active = mb_obj
mb_obj.select_set(True)
bpy.ops.object.convert(target="MESH")
body = bpy.context.view_layer.objects.active
body.name = "Body"
bpy.ops.object.shade_smooth()

NOSE_TIP = MUZZLE + Vector((0.0, 0.03, 0.006))


def tail_tangent(p):
    a = math.atan2(p.y - CURL.y, p.x - CURL.x)
    return Vector((math.sin(a), -math.cos(a), 0.0))   # toward the tail tip


def fur_flow(p):
    """Fur grows back from the nose, down the flanks and along the tail to its tip."""
    tail_dist, _ = nearest_tail(p)
    if tail_dist < 0.045 and p.z < 0.075 and (p - HEAD).length > 0.1:
        return tail_tangent(p)
    return (p - NOSE_TIP).normalized() + Vector((0.0, 0.0, -0.35))


TUFT_ZONES = [
    (HEAD + Vector((0.083, 0.035, -0.035)), 0.03, 1.0),    # cheek buns
    (HEAD + Vector((-0.083, 0.035, -0.035)), 0.03, 1.0),
    (CHEST + Vector((0.0, 0.07, -0.005)), 0.04, 0.7),      # chest ruff
    (TAIL[-1][0], 0.04, 0.8),                               # tail tip
]


def nearest_tail(p):
    return min(((p - q).length, t) for q, t in TAIL)


plush.set_flow(body.data, fur_flow)
for v, f in zip(body.data.vertices, body.data.attributes["Flow"].data):
    p = v.co.copy()
    if p.z < 0.006:
        continue
    zone = max(w * (1 - smoothstep(r * 0.35, r, (p - c).length)) for c, r, w in TUFT_ZONES)
    face = smoothstep(0.035, 0.06, (p - (MUZZLE + Vector((0, 0.02, 0.02)))).length)   # keep the face clean
    lift = plush.fuzz(p, 150.0) * (0.0003 + 0.0042 * zone) * face
    v.co = p + (v.normal * 0.8 + Vector(f.vector) * 0.7) * lift
body.data.update()

# ---------------------------------------------------------------- coat pattern


def coat_color(p):
    d = p - HEAD
    jitter = noise.noise(p * 45) * 0.006
    width_var = 0.5 + 0.5 * noise.noise(p * 18 + Vector((3.1, 0.0, 0.0)))

    white = max(
        1 - smoothstep(0.03, 0.052, (p - (MUZZLE + Vector((0, 0.012, -0.008)))).length),
        1 - smoothstep(0.035, 0.065, (p - Vector((0.045, 0.085, 0.045))).length),
        max(1 - smoothstep(0.032, 0.05, (p - q).length) for q in PAWS),      # white socks
        1 - smoothstep(0.03, 0.048, (p - HIND_PAW).length),
    )
    # lighter undercoat on the cheek buns
    pale = 0.0
    for side in (-1, 1):
        pale = max(pale, 1 - smoothstep(0.02, 0.05, (p - (HEAD + Vector((side * 0.07, 0.04, -0.035)))).length))

    if d.length < 0.11:
        # tapered stripes running from the brow back over the crown
        bands = math.cos((d.x + jitter) * 2 * math.pi / 0.026)
        stripe = (smoothstep(0.55, 0.9, bands) * smoothstep(0.022, 0.05, d.z)
                  * (1 - smoothstep(0.035, 0.058, abs(d.x))))
    else:
        tail_dist, t = nearest_tail(p)
        if tail_dist < 0.05 and p.z < 0.08:
            rings = math.sin(t * math.pi * 8)
            stripe = max(smoothstep(0.15 + 0.2 * width_var, 0.75, rings), smoothstep(0.85, 0.97, t))
        else:
            # Bands across the back, curving with the body; soft edges, uneven widths.
            angle = math.atan2(p.y - CURL.y, p.x - CURL.x)
            bands = math.sin((angle + jitter * 8) * 9)
            stripe = smoothstep(0.05 + 0.35 * width_var, 0.85, bands) * smoothstep(0.05, 0.1, p.z)

    blush = 0.0
    for side in (-1, 1):
        cheek = HEAD + Vector((side * 0.052, 0.058, -0.016))
        blush = max(blush, 1 - smoothstep(0.006, 0.026, (p - cheek).length))

    color = COAT.lerp(STRIPE, stripe * (1 - white) * 0.92)
    color = color.lerp(WHITE, max(white, pale * 0.45))
    return color.lerp(BLUSH, blush * 0.7)


attr = body.data.color_attributes.new("Coat", "FLOAT_COLOR", "POINT")
for v, c in zip(body.data.vertices, attr.data):
    col = coat_color(v.co)
    c.color = (col.x, col.y, col.z, 1)

tex_dir = tempfile.mkdtemp(prefix="mochi_")

# ---------------------------------------------------------------- details

FRONT = Vector((0, -1, 0))   # rays travel toward the face from the front
DOWN = Vector((0, 0, -1))


def surface(point, direction):
    hit, loc, normal, _ = body.ray_cast(point - direction * 0.3, direction)
    if not hit:
        _, loc, normal, _ = body.closest_point_on_mesh(point)
    return loc, normal


def orient(obj, normal, tangent=Vector((1, 0, 0))):
    """Local +Y along the normal, local +X as close to the tangent as possible."""
    y = normal.normalized()
    x = (tangent - y * tangent.dot(y)).normalized()
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Matrix((x, y, x.cross(y))).transposed().to_quaternion()


def sphere(name, radius, mat, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=32, ring_count=16)
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
    curve.bevel_resolution = 4
    curve.use_fill_caps = True
    spline = curve.splines.new("NURBS")
    spline.points.add(len(points) - 1)
    for sp, (x, z) in zip(spline.points, points):
        sp.co = (x, 0, z, 1)
    spline.use_endpoint_u = True
    spline.order_u = 3
    spline.resolution_u = 16
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def rounded_cone(name, r1, depth, mat, flatten, rotation, location):
    bpy.ops.mesh.primitive_cone_add(vertices=40, radius1=r1, radius2=r1 * 0.2, depth=depth)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(mat)
    obj.scale = (1.0, flatten, 1.0)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = rotation
    obj.location = location
    mod = obj.modifiers.new("Round", "SUBSURF")
    mod.levels = 2
    bpy.ops.object.modifier_apply(modifier="Round")
    bpy.ops.object.shade_smooth()
    return obj


parts = []

for side in (-1, 1):
    loc, n = surface(HEAD + Vector((side * 0.033, 0, 0.006)), FRONT)
    eye = stroke(f"Eye{side}", [(-0.0125, 0.0025), (-0.006, -0.0038), (0.006, -0.0038), (0.0125, 0.0025)], 0.0023, INK)
    eye.location = loc + n * 0.0012
    orient(eye, n)
    parts.append(eye)
    for k, (dx, dz) in enumerate(((0.0050, 0.0016), (0.0058, -0.0012))):   # lashes at the outer corner
        lash = stroke(f"Lash{side}{k}", [(side * 0.0118, 0.0020 - 0.0016 * k),
                                         (side * (0.0118 + dx * 0.55), 0.0020 - 0.0016 * k + dz * 0.25),
                                         (side * (0.0118 + dx), 0.0020 - 0.0016 * k + dz)], 0.0009, INK)
        lash.location = loc + n * 0.0012
        orient(lash, n)
        parts.append(lash)

loc, n = surface(MUZZLE + Vector((0, 0, 0.006)), FRONT)
nose = sphere("Nose", 0.0075, PINK, (1.25, 0.55, 0.8))
nose.location = loc + n * 0.002
orient(nose, n)
parts.append(nose)

loc, n = surface(MUZZLE + Vector((0, 0, -0.006)), FRONT)
mouth = stroke("Mouth", [(-0.008, 0.002), (-0.0045, -0.003), (-0.0012, 0.0006), (0.0, 0.0012),
                         (0.0012, 0.0006), (0.0045, -0.003), (0.008, 0.002)], 0.0012, INK)
mouth.location = loc + n * 0.0016
orient(mouth, n)
parts.append(mouth)

furred = []      # ear backs, merged into the body before baking
for side in (-1, 1):
    loc, n = surface(HEAD + Vector((side * 0.056, -0.008, 0.0)), DOWN)
    tilt = (n + Vector((side * 0.42, 0.12, 0.45))).normalized()
    rotation = Vector((0, 0, 1)).rotation_difference(tilt)
    ear = rounded_cone(f"Ear{side}", 0.038, 0.058, FUR_PART, 0.55, rotation, loc + tilt * 0.01)
    furred.append(ear)
    inner = rounded_cone(f"EarInner{side}", 0.024, 0.040, EAR_PINK, 0.4, rotation,
                         ear.location + rotation @ Vector((0, 0.009, -0.004)))
    parts.append(inner)

# toe beans on the tucked front paws
for p in PAWS:
    loc, n = surface(p + Vector((0, 0.03, -0.004)), FRONT)
    pad = sphere("Pad", 0.0055, PINK, (1.2, 0.45, 0.9))
    pad.location = loc + n * 0.0008 + Vector((0, 0, -0.003))
    orient(pad, n)
    parts.append(pad)
    for k in (-1, 0, 1):
        bean = sphere("Bean", 0.0024, PINK, (1, 0.5, 1))
        bean.location = loc + n * 0.0008 + Vector((k * 0.0058, 0, 0.0042 - 0.0012 * abs(k)))
        orient(bean, n)
        parts.append(bean)

# Collar fitted to the thinnest direction of the neck, bell in front.
neck_axis = (HEAD - CHEST).normalized()
neck = CHEST.lerp(HEAD, 0.55)
side_axis = neck_axis.cross(Vector((0, 0, 1))).normalized()
up_axis = side_axis.cross(neck_axis).normalized()
neck_radius = 1.0
for i in range(24):
    a = i / 24 * 2 * math.pi
    hit, edge, _, _ = body.ray_cast(neck, side_axis * math.cos(a) + up_axis * math.sin(a))
    if hit:
        neck_radius = min(neck_radius, (edge - neck).length)
bpy.ops.mesh.primitive_torus_add(major_radius=neck_radius * 0.9, minor_radius=0.0075, major_segments=48, minor_segments=12)
collar = bpy.context.active_object
collar.name = "Collar"
collar.data.materials.append(RED)
collar.rotation_mode = "QUATERNION"
collar.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(neck_axis)
collar.location = neck
bpy.ops.object.shade_smooth()
parts.append(collar)

front = Vector((0, 1, 0))
front = (front - neck_axis * front.dot(neck_axis)).normalized()
hit, edge, _, _ = body.ray_cast(neck, front)
bell = sphere("Bell", 0.0145, GOLD)
bell.location = (edge if hit else neck + front * neck_radius) + front * 0.010
parts.append(bell)
slot = sphere("BellSlot", 1.0, SLOT, (0.0105, 0.0022, 0.0022))
slot.location = bell.location + front * 0.0128 + Vector((0, 0, -0.0058))
slot.rotation_mode = "QUATERNION"
slot.rotation_quaternion = Vector((0, 1, 0)).rotation_difference(front)
parts.append(slot)
for side in (-1, 1):
    hole = sphere("BellHole", 0.0021, SLOT, (1, 0.5, 1))
    hole.location = (bell.location + front * 0.0132 + Vector((0, 0, -0.0058))
                     + front.cross(Vector((0, 0, 1))) * (side * 0.0105))
    parts.append(hole)
ring = sphere("BellRing", 1.0, GOLD, (0.004, 0.0015, 0.004))
ring.location = bell.location + Vector((0, 0, 0.0145))
parts.append(ring)

for obj in parts:
    if obj.type == "CURVE":
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target="MESH")
        bpy.ops.object.shade_smooth()

def part_coat(part, p):
    return COAT.lerp(STRIPE, 0.35)


def part_flow(part, p):
    return Vector((0, 0, 1))


plush.join_furred(body, furred, part_coat, part_flow)
plush.bake_plush_coat(body, tex_dir, "Mochi", TEXTURE_SIZE, strand_scale=650.0, strand_length=6.0,
                      bump_strength=0.25, ao_strength=0.5, ao_distance=0.03, strand_contrast=0.10)

root = bpy.data.objects.new("Mochi", None)
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
print("EXPORTED", OUT_USDZ, faces, "faces")
corners = [o.matrix_world @ Vector(c) for o in [body, *parts] if o.type == "MESH" for c in o.bound_box]
print("BOUNDS", tuple(round(min(c[i] for c in corners), 4) for i in range(3)),
      tuple(round(max(c[i] for c in corners), 4) for i in range(3)))

# ---------------------------------------------------------------- preview

if OUT_PNG:
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.36, 0.25, 0.18, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    scene.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(18)
    sun.data.color = (1.0, 0.91, 0.80)
    sun.rotation_euler = (math.radians(45), 0, math.radians(-30))
    collection.objects.link(sun)
    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "AREA"))
    fill.data.energy = 30
    fill.data.size = 1.0
    fill.data.color = (0.95, 0.96, 1.0)
    fill.location = Vector((-0.6, 0.8, 0.4))
    fill.rotation_euler = (Vector((0, 0.02, 0.06)) - fill.location).to_track_quat("-Z", "Y").to_euler()
    collection.objects.link(fill)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 85
    collection.objects.link(cam)
    target = Vector((0.0, 0.02, 0.06))
    cam.location = target + Vector((0.45, 0.9, 0.6)).normalized() * 1.0
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (target - cam.location).to_track_quat("-Z", "Y")
    scene.camera = cam
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 800
    scene.render.resolution_y = 800
    scene.render.filepath = OUT_PNG
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", OUT_PNG)

# ---------------------------------------------------------------- portrait for the app's pet card

if OUT_PNG and OUT_PORTRAIT:
    face = HEAD + Vector((0.0, 0.02, -0.005))
    cam.data.lens = 85
    cam.location = face + Vector((0.15, 0.9, 0.35)).normalized() * 0.55
    cam.rotation_quaternion = (face - cam.location).to_track_quat("-Z", "Y")
    key = bpy.data.objects.new("Key", bpy.data.lights.new("Key", "POINT"))
    key.data.energy = 60
    key.data.color = (1.0, 0.94, 0.86)
    key.data.shadow_soft_size = 0.3
    key.location = face + Vector((0.3, 0.8, 0.6)).normalized() * 0.5
    collection.objects.link(key)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.1
    scene.render.film_transparent = True
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.filepath = OUT_PORTRAIT
    bpy.ops.render.render(write_still=True)
    print("PORTRAIT", OUT_PORTRAIT)
