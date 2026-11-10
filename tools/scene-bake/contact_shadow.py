"""Bakes a room's soft contact shadows and ambient occlusion on its floor into one transparent top-down image.

  blender -b -P contact_shadow.py -- <out.png> <floor_y> <model.usdz[,more.usdz]> [--size 1024] [--samples 256]
                                     [--sky 0.9] [--bounds x0,z0,x1,z1]

A flat quad at `floor_y` (RealityKit metres) with the image on it, drawn unlit and alpha-blended over the floor, gives
every piece on it a soft shadow where it touches the floor and the walls their occlusion at the foot, with no light and
no shadow in the app. The sky lights the models evenly (ambient occlusion); the image is black with the shadow in alpha.
Writes <out>.json with the covered rectangle: x0, z0, x1, z1 in room space, top of the image at z0 (the back).
"""

import json
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out, floor_y, models = argv[0], float(argv[1]), argv[2].split(",")


def option(name, default):
    return argv[argv.index(name) + 1] if name in argv else default


SIZE = int(option("--size", 1024))
SAMPLES = int(option("--samples", 256))
SKY = float(option("--sky", 0.9))
BOUNDS = option("--bounds", None)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
objects = []
for path in models:
    before = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=path)
    objects += [o for o in set(bpy.data.objects) - before if o.type == "MESH"]
for o in objects:
    o.visible_camera = False

if BOUNDS:
    x0, z0, x1, z1 = (float(v) for v in BOUNDS.split(","))
else:
    bpy.context.view_layer.update()
    corners = [o.matrix_world @ Vector(c) for o in objects for c in o.bound_box]
    x0, x1 = min(c.x for c in corners), max(c.x for c in corners)
    z0, z1 = -max(c.y for c in corners), -min(c.y for c in corners)
width, depth = x1 - x0, z1 - z0

bpy.ops.mesh.primitive_plane_add(size=1, location=((x0 + x1) / 2, -(z0 + z1) / 2, floor_y))
floor = bpy.context.active_object
floor.scale = (width, depth, 1)
floor.is_shadow_catcher = True

cam = bpy.data.cameras.new("top")
cam.type = "ORTHO"
cam.ortho_scale = max(width, depth)
o = bpy.data.objects.new("top", cam)
o.location = ((x0 + x1) / 2, -(z0 + z1) / 2, 5)
scene.collection.objects.link(o)
scene.camera = o
scene.render.resolution_x = SIZE if width >= depth else int(SIZE * width / depth)
scene.render.resolution_y = SIZE if depth >= width else int(SIZE * depth / width)

world = bpy.data.worlds.new("sky")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Strength"].default_value = SKY
scene.world = world
scene.render.engine = "CYCLES"
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.render.film_transparent = True
scene.view_settings.view_transform = "Standard"
prefs = bpy.context.preferences.addons["cycles"].preferences
for kind in ("METAL", "OPTIX", "CUDA"):
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
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.filepath = out
bpy.ops.render.render(write_still=True)
json.dump({"x0": round(x0, 4), "z0": round(z0, 4), "x1": round(x1, 4), "z1": round(z1, 4), "floor_y": floor_y},
          open(os.path.splitext(out)[0] + ".json", "w"))
