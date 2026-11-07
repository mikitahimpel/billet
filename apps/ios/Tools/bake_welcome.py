"""Renders the welcome screen's Mochi as PNG frames with alpha, from Cat.usdz posed bone by bone.

Run (scripts/welcome/bake-welcome.sh does this for you):
  blender -b --python Tools/bake_welcome.py -- <out dir> [--coat <jpg>] [--clip idle|wave] [--only <frame>] [--samples N]

Two clips at 24 fps: `idle` loops (breath, a blink, a tail swish, a slow head turn), `wave` is her hello on tap
(head dips and lifts, ears perk, tail flicks), and both start and end on the same rest pose so they join.
"""

import math
import sys

import bpy
from mathutils import Euler, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]


def option(name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default


CLIP = option("--clip", "idle")
ONLY = option("--only")
SAMPLES = int(option("--samples", "48"))
WIDTH, HEIGHT, FPS = 960, 1280, 24
FRAMES = {"idle": 96, "wave": 36}[CLIP]
ROOT = __file__.rsplit("/Tools/", 1)[0]

bpy.ops.wm.read_factory_settings(use_empty=True)
source = option("--usdz", f"{ROOT}/Nooki/Resources/Cat.usdz")
bpy.ops.wm.usd_import(filepath=source)
scene = bpy.context.scene
skel = next(o for o in scene.objects if o.type == "ARMATURE")
body = next(o for o in scene.objects if o.type == "MESH")

# At this size the body's baked colours carry the coat; the fur shells and fins only read as grain.
furry = {i for i, m in enumerate(body.data.materials) if m and (m.name.startswith("Fur") or m.name == "Fins")}
bpy.context.view_layer.objects.active = body
for poly in body.data.polygons:
    poly.select = poly.material_index in furry
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.delete(type="FACE")
bpy.ops.object.mode_set(mode="OBJECT")


def light(name, energy, location, size, color):
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.size, data.color = energy, size, color
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (Vector((0, 0, 0.12)) - Vector(location)).to_track_quat("-Z", "Y")
    scene.collection.objects.link(obj)


# The room's lamp is at her left: a warm key from there, a cool fill, a rim behind.
light("Key", 40, (-0.6, 0.7, 0.55), 0.7, (1.0, 0.9, 0.78))
light("Fill", 14, (0.7, 0.6, 0.25), 0.9, (0.88, 0.92, 1.0))
light("Rim", 22, (0.2, -0.6, 0.5), 0.5, (1.0, 0.9, 0.8))
world = bpy.data.worlds.new("World")
world.color = (0.5, 0.44, 0.4)
scene.world = world

cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
cam.data.lens = 70
scene.collection.objects.link(cam)
target = Vector((-0.005, 0.0, 0.125))
cam.location = target + Vector((0.12, 1.0, 0.1)).normalized() * 0.92
cam.rotation_mode = "QUATERNION"
cam.rotation_quaternion = (target - cam.location).to_track_quat("-Z", "Y")
scene.camera = cam

for bone in skel.pose.bones:
    bone.rotation_mode = "XYZ"


def pose(name, x=0.0, y=0.0, z=0.0):
    skel.pose.bones[name].rotation_euler = Euler((x, y, z), "XYZ")


def smooth(t):
    return t * t * (3 - 2 * t)


def bump(t, start, end):
    """0 to 1 and back to 0 between start and end, eased."""
    if t <= start or t >= end:
        return 0.0
    u = (t - start) / (end - start)
    return smooth(1 - abs(2 * u - 1))


def apply(frame):
    t = frame / FRAMES
    tau = 2 * math.pi * t
    if CLIP == "idle":
        breath = math.sin(tau)
        pose("chest", x=0.012 * breath)
        pose("head", x=-0.02 * breath, z=0.1 * math.sin(tau))
        blink = bump(t, 0.55, 0.65)
        tail = math.sin(tau)
        pose("tail0", y=0.12 * tail)
        pose("tail1", y=0.2 * math.sin(tau - 0.6))
        pose("tail2", y=0.28 * math.sin(tau - 1.2))
        ear = bump(t, 0.2, 0.3)
    else:
        nod = bump(t, 0.05, 0.95)
        pose("head", x=0.22 * bump(t, 0.1, 0.5) - 0.08 * bump(t, 0.5, 0.9), z=0.2 * nod)
        pose("chest", x=0.03 * nod)
        blink = bump(t, 0.4, 0.55)
        pose("tail0", y=0.25 * bump(t, 0.1, 0.9))
        pose("tail1", y=0.4 * math.sin(2 * tau))
        pose("tail2", y=0.5 * math.sin(2 * tau - 0.8))
        ear = bump(t, 0.1, 0.8)
    pose("earLeft", x=-0.35 * ear)
    pose("earRight", x=-0.35 * ear)
    for lid in ("lidLeft", "lidRight"):
        pose(lid, x=-1.1 * blink)
    for lid in ("lidLeftLow", "lidRightLow"):
        pose(lid, x=0.9 * blink)
    bpy.context.view_layer.update()


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
scene.render.resolution_x, scene.render.resolution_y = WIDTH, HEIGHT

for frame in ([int(ONLY)] if ONLY else range(FRAMES)):
    apply(frame)
    scene.render.filepath = f"{OUT}/{CLIP}-{frame:03d}.png"
    bpy.ops.render.render(write_still=True)
