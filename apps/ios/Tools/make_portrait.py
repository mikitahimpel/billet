"""Renders MochiPortrait.png, the round avatar of Mochi on the pet button and in the widgets, from Cat.usdz.

Run:
  blender -b --python Tools/make_portrait.py -- Shared/Resources/MochiPortrait.png [size]

A three-quarter close-up of her face, softly lit, on a transparent background; the app puts it on its own warm disc.
"""

import math
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
OUT = args[0]
SIZE = int(args[1]) if len(args) > 1 else 768
ROOT = __file__.rsplit("/Tools/", 1)[0]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=f"{ROOT}/Nooki/Resources/Cat.usdz")
scene = bpy.context.scene

# The fur shells and fins read as grain this close; the body's baked colors carry the fur pattern on their own.
for obj in scene.objects:
    if obj.type != "MESH":
        continue
    furry = {i for i, m in enumerate(obj.data.materials) if m and (m.name.startswith("Fur") or m.name == "Fins")}
    bpy.context.view_layer.objects.active = obj
    for poly in obj.data.polygons:
        poly.select = poly.material_index in furry
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.delete(type="FACE")
    bpy.ops.object.mode_set(mode="OBJECT")

# Cat.usdz is in the splat's model space, front -Z, which lands facing +Y here; her eyes sit about 0.195 m up.
face = Vector((-0.01, 0.06, 0.175))


def light(name, kind, energy, location, size=0.3, color=(1, 1, 1)):
    data = bpy.data.lights.new(name, kind)
    data.energy = energy
    data.color = color
    if kind == "AREA":
        data.size = size
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (face - Vector(location)).to_track_quat("-Z", "Y")
    scene.collection.objects.link(obj)


# Warm key from the upper left, a cool soft fill, and a rim behind to lift the fur off the background.
light("Key", "AREA", 11, (-0.35, 0.55, 0.5), size=0.5, color=(1.0, 0.92, 0.82))
light("Fill", "AREA", 5, (0.5, 0.45, 0.2), size=0.8, color=(0.88, 0.92, 1.0))
light("Rim", "AREA", 14, (0.15, -0.45, 0.45), size=0.4, color=(1.0, 0.9, 0.8))
world = bpy.data.worlds.new("World")
world.color = (0.55, 0.48, 0.42)
scene.world = world

cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
cam.data.lens = 85
scene.collection.objects.link(cam)
direction = Vector((0.28, 1.0, 0.12)).normalized()
cam.location = face + direction * 0.5
cam.rotation_mode = "QUATERNION"
cam.rotation_quaternion = (face - cam.location).to_track_quat("-Z", "Y")
scene.camera = cam

scene.render.engine = "CYCLES"
prefs = bpy.context.preferences.addons["cycles"].preferences
prefs.compute_device_type = "METAL"
prefs.get_devices()
for device in prefs.devices:
    device.use = True
scene.cycles.device = "GPU"
scene.cycles.samples = 512
scene.cycles.use_denoising = True
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Medium High Contrast"
scene.render.film_transparent = True
scene.render.resolution_x = scene.render.resolution_y = SIZE
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
