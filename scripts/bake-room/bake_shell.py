"""Bakes one room's static shell into a single lightmapped USDZ.

Run by bake.sh, headless:

  blender -b -P bake_shell.py -- <room> <shell.json> <out.usdz> [--size 2048] [--samples 128] [--furniture <usdz>]

`shell.json` is what the app's BakedShellTests.export wrote: the room's static boxes, spheres and cylinders with
their transforms and materials, in the room's own space (meters, Y up). Everything is merged into one mesh, unwrapped to one atlas
and baked with Cycles (direct and indirect light, ambient occlusion, the albedo) into one texture; the model carries
that texture alone, and the app draws it unlit.

The lights are a copy of the Swift scene's, in the `ROOMS` table below. Update them with the Swift if those change.
"""

import json
import math
import os
import sys
import time

import bpy
import bmesh
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
room, source, out = argv[0], argv[1], argv[2]


def option(name, default):
    return argv[argv.index(name) + 1] if name in argv else default


SIZE = int(option("--size", 2048))
SAMPLES = int(option("--samples", 128))
FURNITURE = option("--furniture", None)
QUALITY = int(option("--quality", 88))
# Cycles' scene-linear result is scaled by this before it is written, to match the look RealityKit gives the live
# room (compared on screenshots of both). One number per room.
EXPOSURE = float(option("--exposure", 1.0))

# Lights as the Swift scenes set them: RealityKit lux for the directional, lumens for the points. `to_blender` below
# turns them into Blender's units. Positions are in the room's space, Y up.
ROOMS = {
    "room": {
        # DioramaScene.buildLighting: warm sun 800 lux from (1.4, 2.2, 0.9) at the origin, the window's point light,
        # buildCandle: the candle and the stool lamp. The ambient is the two-tone gradient, exponent -0.4.
        "sun": {"color": 0xFFE2BC, "lux": 800, "from": (1.4, 2.2, 0.9)},
        "points": [
            {"color": 0xFFB866, "lumens": 1800, "at": (-0.3, 0.47, 0.02), "radius": 1.1},
            {"color": 0xFFC27A, "lumens": 700, "at": (-0.15, 0.314, -0.34), "radius": 0.7},
            {"color": 0xFFAA55, "lumens": 450, "at": (-0.37, 0.33, 0.38), "radius": 0.6},
        ],
        "sky": (0xFFE7C4, 0xB97A45, 0.76),
    },
    "city": {
        # CityRoomScene at 15:00 with the lamps off: the sun 320 * lightIntensity, the fill 300, the sky light
        # 2500 * (1 - darkness * 0.85) at the window. The lamps are on only at night, which the tint covers.
        "sun": {"color": 0xFFE9D0, "lux": 700, "from": (-0.9, 2.1, -1.1)},
        "fill": {"color": 0xDCE8FF, "lux": 260, "from": (1.5, 1.4, 1.6)},
        "points": [
            {"color": 0xCDE5FF, "lumens": 1200, "at": (0.0, 0.5, -0.38), "radius": 1.2},
        ],
        "sky": (0xFFE7C4, 0xB97A45, 0.76),
    },
}[room]

# RealityKit's units are not Blender's. These two factors are the calibration: a directional of N lux and a point of
# N lumens become `N * factor` watts of Blender light.
SUN_PER_LUX = 0.8 / 1000
AMBIENT = 0.6
POINT_W_PER_LUMEN = 1 / 300


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_linear(h):
    return tuple(srgb_to_linear(((h >> s) & 255) / 255) for s in (16, 8, 0))


def to_blender(p):
    """RealityKit's Y-up (x, y, z) to Blender's Z-up (x, -z, y)."""
    return Vector((p[0], -p[2], p[1]))


def log(*args):
    print("[bake]", *args, flush=True)


t0 = time.time()
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# ---- the shell's parts, merged ---------------------------------------------------------------------------------
# RealityKit tessellates a rounded box into thousands of triangles. The app sends each part's shape and transform
# instead, and the shapes are rebuilt here with a few: the same silhouette, and the same analytic normals, so the
# shading reads alike.
import numpy as np  # noqa: E402

BEVEL_STEPS = 3
SPHERE = (20, 12)
RING = 28


def rounded_box(size, radius):
    """Vertices, triangles and normals of a box of `size` with corners rounded to `radius`, centered on the origin."""
    half = np.array(size[:3]) / 2
    inner = np.maximum(half - radius, 0)
    # Along each axis the grid passes through the flat part's edges and then rounds the corner in BEVEL_STEPS.
    axes = []
    for a in range(3):
        steps = np.linspace(0, math.pi / 2, BEVEL_STEPS + 1)
        if radius <= 0:
            ticks = [-half[a], half[a]]
        else:
            corner = inner[a] + radius * np.sin(steps)
            ticks = sorted(set([*(-corner), *corner]))
        axes.append(np.array(ticks))
    verts, tris = [], []
    for face_axis in range(3):
        # u x v is the face's own axis, so the quads below wind outwards on the + side.
        u, v = ((1, 2), (2, 0), (0, 1))[face_axis]
        for sign in (-1, 1):
            base = len(verts)
            nu, nv = len(axes[u]), len(axes[v])
            for iu in range(nu):
                for iv in range(nv):
                    p = np.zeros(3)
                    p[face_axis] = sign * half[face_axis]
                    p[u] = axes[u][iu]
                    p[v] = axes[v][iv]
                    verts.append(p)
            for iu in range(nu - 1):
                for iv in range(nv - 1):
                    a0 = base + iu * nv + iv
                    quad = (a0, a0 + nv, a0 + nv + 1, a0 + 1)
                    tris += ([(quad[0], quad[1], quad[2]), (quad[0], quad[2], quad[3])] if sign > 0
                             else [(quad[0], quad[2], quad[1]), (quad[0], quad[3], quad[2])])
    verts = np.array(verts)
    # Each vertex is pushed out to the rounded surface: the nearest point of the inner box plus `radius` along the
    # direction away from it, which is also its normal.
    nearest = np.clip(verts, -inner, inner)
    away = verts - nearest
    length = np.linalg.norm(away, axis=1, keepdims=True)
    face_normal = np.zeros_like(verts)
    for i, p in enumerate(verts):
        a = int(np.argmax(np.abs(p) / np.maximum(half, 1e-9)))
        face_normal[i, a] = np.sign(p[a])
    normals = np.where(length > 1e-9, away / np.maximum(length, 1e-9), face_normal)
    if radius > 0:
        verts = np.where(length > 1e-9, nearest + normals * radius, verts)
    return verts, np.array(tris), normals


def sphere():
    segments, rings = SPHERE
    verts = [(0, 1, 0)]
    for r in range(1, rings):
        phi = math.pi * r / rings
        for s in range(segments):
            theta = 2 * math.pi * s / segments
            verts.append((math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta)))
    verts.append((0, -1, 0))
    tris = []
    for s in range(segments):
        tris.append((0, 1 + s, 1 + (s + 1) % segments))
    for r in range(rings - 2):
        for s in range(segments):
            a = 1 + r * segments + s
            b = 1 + r * segments + (s + 1) % segments
            tris += [(a, a + segments, b), (b, a + segments, b + segments)]
    last = len(verts) - 1
    for s in range(segments):
        tris.append((last, last - segments + (s + 1) % segments, last - segments + s))
    verts = np.array(verts, dtype=float)
    return verts, np.array(tris), verts.copy()


def cylinder():
    """The unit cylinder: radius 1, height 1 along Y, as RealityKit's `generateCylinder(height: 1, radius: 1)`."""
    verts, normals, tris = [], [], []
    for y in (0.5, -0.5):
        for s in range(RING):
            t = 2 * math.pi * s / RING
            verts.append((math.cos(t), y, math.sin(t)))
            normals.append((math.cos(t), 0, math.sin(t)))
    for s in range(RING):
        n = (s + 1) % RING
        tris += [(s, RING + s, n), (n, RING + s, RING + n)]
    for y, sign in ((0.5, 1), (-0.5, -1)):
        center = len(verts)
        verts.append((0, y, 0))
        normals.append((0, sign, 0))
        ring = len(verts)
        for s in range(RING):
            t = 2 * math.pi * s / RING
            verts.append((math.cos(t), y, math.sin(t)))
            normals.append((0, sign, 0))
        for s in range(RING):
            n = (s + 1) % RING
            tris.append((center, ring + s, ring + n) if sign > 0 else (center, ring + n, ring + s))
    return np.array(verts, dtype=float), np.array(tris), np.array(normals, dtype=float)


UNIT = {"sphere": sphere(), "cylinder": cylinder()}

data = json.load(open(source))
materials = {}
for part in data["parts"]:
    materials.setdefault(part["material"], {"color": part["color"], "roughness": part["roughness"], "parts": []})
    materials[part["material"]]["parts"].append(part)


def weld(verts, tris, normals):
    """Shares the vertices a shape's faces have at the same place, so the unwrap sees one connected surface."""
    _, first, inverse = np.unique(np.round(verts, 6), axis=0, return_index=True, return_inverse=True)
    return verts[first], inverse.reshape(-1)[tris], normals[first]


def place(part):
    """A part's vertices, triangles and normals in Blender's space."""
    if part["shape"] == "mesh":
        verts = np.array(part["positions"]).reshape(-1, 3)
        normals = np.array(part["normals"]).reshape(-1, 3)
        tris = np.array(part["indices"]).reshape(-1, 3)
    else:
        if part["shape"] == "box":
            verts, tris, normals = rounded_box(part["size"], part["size"][3])
        else:
            verts, tris, normals = UNIT[part["shape"]]
        m = np.array(part["matrix"]).reshape(4, 4).T
        verts = verts @ m[:3, :3].T + m[:3, 3]
        normals = normals @ np.linalg.inv(m[:3, :3])
        normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-9)
    if part["shape"] != "mesh":
        verts, tris, normals = weld(verts, tris, normals)
        # Triangles must wind outwards: RealityKit culls the back faces.
        centers = verts[tris].mean(axis=1)
        facing = np.cross(verts[tris[:, 1]] - verts[tris[:, 0]], verts[tris[:, 2]] - verts[tris[:, 0]])
        if (np.einsum("ij,ij->i", facing, centers - verts.mean(axis=0)) > 0).mean() < 0.5:
            tris = tris[:, ::-1]
    # RealityKit's Y-up to Blender's Z-up: (x, y, z) -> (x, -z, y).
    flip = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]])
    return verts @ flip.T, tris, normals @ flip.T


objects = []
for name, info in materials.items():
    all_verts, all_tris, all_normals = [], [], []
    for part in info["parts"]:
        verts, tris, normals = place(part)
        all_tris.append(tris + sum(len(v) for v in all_verts))
        all_verts.append(verts)
        all_normals.append(normals)
    verts = np.concatenate(all_verts)
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts.tolist(), [], np.concatenate(all_tris).tolist())
    mesh.update()
    for poly in mesh.polygons:
        poly.use_smooth = True
    mesh.normals_split_custom_set_from_vertices(np.concatenate(all_normals).tolist())
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    r, g, b = (srgb_to_linear(c) for c in info["color"])
    bsdf.inputs["Base Color"].default_value = (r, g, b, 1)
    bsdf.inputs["Roughness"].default_value = info["roughness"]
    bsdf.inputs["Metallic"].default_value = 0
    obj.data.materials.append(material)
    objects.append(obj)

bpy.ops.object.select_all(action="DESELECT")
for obj in objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = objects[0]
bpy.ops.object.join()
shell = bpy.context.view_layer.objects.active
shell.name = "Shell"
log("merged", len(objects), "materials,", len(shell.data.polygons), "triangles", f"{time.time() - t0:.0f}s")

# Faces nobody sees: the underside of the base slab and anything flat on the ground facing down.
bm = bmesh.new()
bm.from_mesh(shell.data)
doomed = [f for f in bm.faces if f.normal.z < -0.7 and f.calc_center_median().z < 0.01]
bmesh.ops.delete(bm, geom=doomed, context="FACES")
bm.to_mesh(shell.data)
bm.free()
log("kept", len(shell.data.polygons), "triangles after removing hidden faces")

# ---- the furniture, as a shadow caster only ---------------------------------------------------------------------
occluders = []
if FURNITURE:
    before = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=FURNITURE)
    for obj in set(bpy.data.objects) - before:
        obj.visible_camera = False
        obj.is_shadow_catcher = False
        occluders.append(obj)
    # RealityKit's USD is Y up; Blender's importer turns it into Z up.
    log("furniture:", len(occluders), "objects")

# ---- the atlas ---------------------------------------------------------------------------------------------------
bpy.ops.object.select_all(action="DESELECT")
shell.select_set(True)
bpy.context.view_layer.objects.active = shell
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.0015, scale_to_bounds=False)
bpy.ops.uv.pack_islands(margin=0.0015, rotate=True)
bpy.ops.object.mode_set(mode="OBJECT")
log("unwrapped", f"{time.time() - t0:.0f}s")

image = bpy.data.images.new("lightmap", SIZE, SIZE, alpha=False)
image.colorspace_settings.name = "sRGB"
atlas = bpy.data.materials.new("Shell")
atlas.use_nodes = True
tree = atlas.node_tree
tex = tree.nodes.new("ShaderNodeTexImage")
tex.image = image
# The bake needs the image node selected and active in every material it bakes; the original materials stay on the
# object for it and are swapped for the atlas material afterwards.
for slot in shell.data.materials:
    node = slot.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = image
    slot.node_tree.nodes.active = node
    node.select = True

# ---- the lights ------------------------------------------------------------------------------------------------


def sun(spec, name):
    light = bpy.data.lights.new(name, "SUN")
    light.color = hex_linear(spec["color"])
    light.energy = spec["lux"] * SUN_PER_LUX
    light.angle = math.radians(2.5)
    obj = bpy.data.objects.new(name, light)
    scene.collection.objects.link(obj)
    source_at = to_blender(spec["from"])
    obj.location = source_at
    obj.rotation_euler = (-source_at).to_track_quat("-Z", "Y").to_euler()


sun(ROOMS["sun"], "Sun") if "sun" in ROOMS else None
if "fill" in ROOMS:
    sun(ROOMS["fill"], "Fill")
for i, spec in enumerate(ROOMS["points"]):
    light = bpy.data.lights.new(f"Point{i}", "POINT")
    light.color = hex_linear(spec["color"])
    light.energy = spec["lumens"] * POINT_W_PER_LUMEN
    light.shadow_soft_size = 0.03
    # The point lights fall off to nothing at their attenuation radius, as RealityKit's do.
    light.use_custom_distance = True
    light.cutoff_distance = spec["radius"]
    obj = bpy.data.objects.new(f"Point{i}", light)
    obj.location = to_blender(spec["at"])
    scene.collection.objects.link(obj)

top, bottom, scale = ROOMS["sky"]
world = bpy.data.worlds.new("Sky")
world.use_nodes = True
nodes, links = world.node_tree.nodes, world.node_tree.links
background = nodes["Background"]
# A flat ambient of the two tones' mean: the world's directions are not a usable gradient across Blender's bake.
mean = tuple((x + y) / 2 for x, y in zip(hex_linear(top), hex_linear(bottom)))
background.inputs["Color"].default_value = (*mean, 1)
background.inputs["Strength"].default_value = scale * AMBIENT
scene.world = world

# ---- the bake ----------------------------------------------------------------------------------------------------
scene.render.engine = "CYCLES"
cycles = scene.cycles
cycles.samples = SAMPLES
cycles.use_denoising = True
cycles.denoiser = "OPENIMAGEDENOISE"
cycles.max_bounces = 6
prefs = bpy.context.preferences.addons["cycles"].preferences
try:
    prefs.compute_device_type = "METAL"
    prefs.get_devices()
    for device in prefs.devices:
        device.use = True
    cycles.device = "GPU"
except Exception as error:  # noqa: BLE001 - falls back to the CPU
    log("no GPU:", error)
scene.view_settings.view_transform = "Standard"
scene.view_settings.exposure = math.log2(EXPOSURE) if EXPOSURE > 0 else 0
bake = scene.render.bake
bake.margin = 8
bake.use_clear = True
bake.use_pass_direct = True
bake.use_pass_indirect = True
bake.use_pass_diffuse = True
bake.use_pass_color = True
bake.use_pass_glossy = False
bake.use_pass_transmission = False
bake.use_pass_emit = False
bake.target = "IMAGE_TEXTURES"
bpy.ops.object.select_all(action="DESELECT")
shell.select_set(True)
bpy.context.view_layer.objects.active = shell
log("baking", SIZE, "px,", SAMPLES, "samples", f"{time.time() - t0:.0f}s")
bpy.ops.object.bake(type="COMBINED")
log("baked", f"{time.time() - t0:.0f}s")

# ---- the model ---------------------------------------------------------------------------------------------------
workdir = os.path.dirname(os.path.abspath(out))
png = os.path.join(workdir, f"{room}_lightmap.jpg")
image.filepath_raw = png
image.file_format = "JPEG"
scene.render.image_settings.quality = QUALITY
image.save_render(png, scene=scene)
# The exporter copies a texture from a file, which the baked image is not until it is loaded back from it.
image = bpy.data.images.load(png)
image.colorspace_settings.name = "sRGB"
tex.image = image

shell.data.materials.clear()
shell.data.materials.append(atlas)
bsdf = tree.nodes["Principled BSDF"]
tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 1
bsdf.inputs["Specular IOR Level"].default_value = 0

for obj in occluders:
    bpy.data.objects.remove(obj, do_unlink=True)
for obj in list(bpy.data.objects):
    if obj.type == "LIGHT":
        bpy.data.objects.remove(obj, do_unlink=True)

bpy.ops.object.select_all(action="DESELECT")
shell.select_set(True)
props = {p.identifier for p in bpy.ops.wm.usd_export.get_rna_type().properties}
args = dict(filepath=out, selected_objects_only=True, export_materials=True, generate_preview_surface=True,
            export_normals=True, export_uvmaps=True, convert_scene_units="METERS", root_prim_path="/Shell")
if "export_textures_mode" in props:
    args["export_textures_mode"] = "NEW"
elif "export_textures" in props:
    args["export_textures"] = True
if "use_instancing" in props:
    args["use_instancing"] = False
args = {k: v for k, v in args.items() if k in props}
bpy.ops.wm.usd_export(**args)
log("wrote", out, f"{os.path.getsize(out) / 1e6:.2f} MB", f"{time.time() - t0:.0f}s")
