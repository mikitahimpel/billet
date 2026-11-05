"""Renders Coat-<coat>.png, Mochi's card in the onboarding coat carousel, from Cat.usdz.

Run:
  blender -b --python Tools/make_coat_card.py -- Nooki/Resources/Coats/Coat-grey.png [width] [samples]

The whole seated cat in three-quarter view, lit like MochiPortrait.png, on a transparent 3:4 canvas.
scripts/coats/coat-cards.sh runs it once per coat on a copy of Cat.usdz holding that coat's colour atlas.
"""

import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
OUT = args[0]
WIDTH = int(args[1]) if len(args) > 1 else 1200
SAMPLES = int(args[2]) if len(args) > 2 else 512
ROOT = __file__.rsplit("/Tools/", 1)[0]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=f"{ROOT}/Nooki/Resources/Cat.usdz")
scene = bpy.context.scene

# As in make_portrait.py: the fur shells and fins read as grain in a still; the baked colours carry the pattern.
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

bpy.context.view_layer.update()
corners = [obj.matrix_world @ Vector(c) for obj in scene.objects if obj.type == "MESH" for c in obj.bound_box]
low = Vector(tuple(min(c[i] for c in corners) for i in range(3)))
high = Vector(tuple(max(c[i] for c in corners) for i in range(3)))
centre = (low + high) / 2
height = high.z - low.z


def light(name, kind, energy, location, size=0.3, color=(1, 1, 1)):
    data = bpy.data.lights.new(name, kind)
    data.energy = energy
    data.color = color
    if kind == "AREA":
        data.size = size
    obj = bpy.data.objects.new(name, data)
    obj.location = centre + Vector(location)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (centre - obj.location).to_track_quat("-Z", "Y")
    scene.collection.objects.link(obj)


# make_portrait.py's key, fill and rim, moved back to light the whole body.
light("Key", "AREA", 30, (-0.5, 0.8, 0.5), size=0.8, color=(1.0, 0.92, 0.82))
light("Fill", "AREA", 14, (0.7, 0.65, 0.15), size=1.2, color=(0.88, 0.92, 1.0))
light("Rim", "AREA", 34, (0.2, -0.65, 0.6), size=0.6, color=(1.0, 0.9, 0.8))
world = bpy.data.worlds.new("World")
world.color = (0.55, 0.48, 0.42)
scene.world = world

# Front is +Y here (make_portrait.py); the camera sits a little right of her and slightly above her middle.
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
cam.data.lens = 85
cam.data.sensor_fit = "VERTICAL"
scene.collection.objects.link(cam)
direction = Vector((0.28, 1.0, 0.18)).normalized()
scene.camera = cam
scene.render.resolution_x = WIDTH
scene.render.resolution_y = WIDTH * 4 // 3
cam.rotation_mode = "QUATERNION"
cam.rotation_quaternion = (-direction).to_track_quat("-Z", "Y")
# Fit the camera to every vertex from this angle, then back off so she fills 80% of the card's height.
points = [c for obj in scene.objects if obj.type == "MESH" for v in obj.data.vertices for c in obj.matrix_world @ v.co]
fit, _ = cam.camera_fit_coords(bpy.context.evaluated_depsgraph_get(), points)
cam.location = fit + direction * ((fit - centre).dot(direction) * (1 / 0.8 - 1))

scene.render.engine = "CYCLES"
prefs = bpy.context.preferences.addons["cycles"].preferences
prefs.compute_device_type = "METAL"
prefs.get_devices()
for device in prefs.devices:
    device.use = True
scene.cycles.device = "GPU"
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Medium High Contrast"
scene.render.film_transparent = True
scene.render.image_settings.color_mode = "RGBA"
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
