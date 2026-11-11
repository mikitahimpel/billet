"""Bakes light and contact shadow into a USDZ's own surfaces, so the app can draw it unlit with no lights or shadows.

  blender -b -P bake_model.py -- <model.usdz> <lights.json> <out.usdz> [--occluder a.usdz,b.usdz] [--size 2048]
                                 [--samples 128] [--quality 88] [--exposure 1.0]

The model's flat-colour materials are merged into one mesh and unwrapped to one atlas; Cycles bakes direct and indirect
light with ambient occlusion and the albedo into one JPEG, and the model is written with that texture alone. Occluders
(the room's shell, say) cast shadows and occlusion into the bake but are not written. `lights.json` is
`{"sun": {...}, "fill": {...}?, "points": [...], "sky": [top, bottom, scale]}` in RealityKit units and Y-up room space,
the same table as scripts/bake-room/bake_shell.py's `ROOMS`; tools/scene-bake/lights/ holds the rooms'.
"""

import json
import math
import os
import sys
import time

import bmesh
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
model, lights_path, out = argv[0], argv[1], argv[2]


def option(name, default):
    return argv[argv.index(name) + 1] if name in argv else default


SIZE = int(option("--size", 2048))
SAMPLES = int(option("--samples", 128))
QUALITY = int(option("--quality", 88))
EXPOSURE = float(option("--exposure", 1.0))
OCCLUDERS = [p for p in option("--occluder", "").split(",") if p]
LIGHTS = json.load(open(lights_path))
SUN_PER_LUX = 0.8 / 1000
AMBIENT = 0.6
POINT_W_PER_LUMEN = 1 / 300


def log(*args):
    print("[bake-model]", *args, flush=True)


def linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_linear(h):
    return tuple(linear(((h >> s) & 255) / 255) for s in (16, 8, 0))


def to_blender(p):
    return Vector((p[0], -p[2], p[1]))


t0 = time.time()
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

before = set(bpy.data.objects)
bpy.ops.wm.usd_import(filepath=model)
meshes = [o for o in set(bpy.data.objects) - before if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = "Body"
log("model:", len(meshes), "meshes,", len(body.data.polygons), "faces", f"{time.time() - t0:.0f}s")

# Faces nobody sees: those lying on the floor and facing down.
bm = bmesh.new()
bm.from_mesh(body.data)
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.normal.z < -0.7 and f.calc_center_median().z < 0.01], context="FACES")
bm.to_mesh(body.data)
bm.free()

occluders = []
for path in OCCLUDERS:
    pre = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=path)
    for o in set(bpy.data.objects) - pre:
        o.visible_camera = False
        occluders.append(o)

bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.0015, scale_to_bounds=False)
bpy.ops.uv.pack_islands(margin=0.0015, rotate=True)
bpy.ops.object.mode_set(mode="OBJECT")

image = bpy.data.images.new("lightmap", SIZE, SIZE, alpha=False)
image.colorspace_settings.name = "sRGB"
for slot in body.data.materials:
    slot.use_nodes = True
    node = slot.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = image
    slot.node_tree.nodes.active = node
    node.select = True


def sun(spec, name):
    light = bpy.data.lights.new(name, "SUN")
    light.color = hex_linear(spec["color"])
    light.energy = spec["lux"] * SUN_PER_LUX
    light.angle = math.radians(2.5)
    obj = bpy.data.objects.new(name, light)
    scene.collection.objects.link(obj)
    at = to_blender(spec["from"])
    obj.location = at
    obj.rotation_euler = (-at).to_track_quat("-Z", "Y").to_euler()


if "sun" in LIGHTS:
    sun(LIGHTS["sun"], "Sun")
if "fill" in LIGHTS:
    sun(LIGHTS["fill"], "Fill")
for i, spec in enumerate(LIGHTS["points"]):
    light = bpy.data.lights.new(f"Point{i}", "POINT")
    light.color = hex_linear(spec["color"])
    light.energy = spec["lumens"] * POINT_W_PER_LUMEN
    light.shadow_soft_size = 0.03
    light.use_custom_distance = True
    light.cutoff_distance = spec["radius"]
    obj = bpy.data.objects.new(f"Point{i}", light)
    obj.location = to_blender(spec["at"])
    scene.collection.objects.link(obj)

top, bottom, scale = LIGHTS["sky"]
world = bpy.data.worlds.new("Sky")
world.use_nodes = True
mean = tuple((x + y) / 2 for x, y in zip(hex_linear(top), hex_linear(bottom)))
world.node_tree.nodes["Background"].inputs["Color"].default_value = (*mean, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = scale * AMBIENT
scene.world = world

scene.render.engine = "CYCLES"
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.cycles.max_bounces = 6
prefs = bpy.context.preferences.addons["cycles"].preferences
for kind in ("METAL", "OPTIX", "CUDA"):
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
scene.view_settings.view_transform = "Standard"
scene.view_settings.exposure = math.log2(EXPOSURE) if EXPOSURE > 0 else 0
bake = scene.render.bake
bake.margin = 8
bake.use_clear = True
bake.use_pass_direct = bake.use_pass_indirect = bake.use_pass_color = True
bake.use_pass_diffuse = True
bake.use_pass_glossy = bake.use_pass_transmission = bake.use_pass_emit = False
bake.target = "IMAGE_TEXTURES"
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.context.view_layer.objects.active = body
log("baking", SIZE, "px,", SAMPLES, "samples")
bpy.ops.object.bake(type="COMBINED")

png = os.path.splitext(out)[0] + "_lightmap.jpg"
image.filepath_raw = png
image.file_format = "JPEG"
scene.render.image_settings.quality = QUALITY
image.save_render(png, scene=scene)
image = bpy.data.images.load(png)
image.colorspace_settings.name = "sRGB"

atlas = bpy.data.materials.new("Baked")
atlas.use_nodes = True
tex = atlas.node_tree.nodes.new("ShaderNodeTexImage")
tex.image = image
bsdf = atlas.node_tree.nodes["Principled BSDF"]
atlas.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 1
bsdf.inputs["Specular IOR Level"].default_value = 0
body.data.materials.clear()
body.data.materials.append(atlas)
for o in occluders:
    bpy.data.objects.remove(o, do_unlink=True)
for o in list(bpy.data.objects):
    if o.type == "LIGHT":
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
props = {p.identifier for p in bpy.ops.wm.usd_export.get_rna_type().properties}
args = dict(filepath=out, selected_objects_only=True, export_materials=True, generate_preview_surface=True,
            export_normals=True, export_uvmaps=True, convert_scene_units="METERS", root_prim_path="/Baked")
if "export_textures_mode" in props:
    args["export_textures_mode"] = "NEW"
elif "export_textures" in props:
    args["export_textures"] = True
bpy.ops.wm.usd_export(**{k: v for k, v in args.items() if k in props})
log("wrote", out, f"{os.path.getsize(out) / 1e6:.2f} MB", f"{time.time() - t0:.0f}s")
