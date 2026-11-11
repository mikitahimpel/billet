"""Renders remeshed props: contact-sheet views or the shop tile.

Blender -b --factory-startup -P render_props.py -- <mode sheet|tile> <remeshed dir> <out dir> <name>...
sheet: 3 views (front, 3/4, back) on a neutral grey backdrop, 384 px each -> <out>/<name>_sheet.png
tile : 512x512 transparent, one fixed 3/4 camera direction and light, soft contact shadow -> <out>/<name>_tile.png
Prop frame: metres, y-up, base centre at origin, front +Z (OBJ import is converted to Blender z-up).
"""
import math, sys
from pathlib import Path
import bpy
from mathutils import Vector

mode, SRC, OUT = sys.argv[sys.argv.index("--") + 1], *[Path(a) for a in sys.argv[sys.argv.index("--") + 2:sys.argv.index("--") + 4]]
names = sys.argv[sys.argv.index("--") + 4:]
OUT.mkdir(parents=True, exist_ok=True)

def setup(px, transparent):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "CUDA"; prefs.get_devices()
    for d in prefs.devices: d.use = d.type == "CUDA"
    s.cycles.device = "GPU"; s.cycles.samples = 48; s.cycles.use_denoising = False
    s.render.resolution_x = s.render.resolution_y = px
    s.render.film_transparent = transparent
    s.view_settings.view_transform = "Standard"
    return s

def load(name):
    bpy.ops.wm.obj_import(filepath=str(SRC / f"{name}.obj"), forward_axis="NEGATIVE_Z", up_axis="Y")
    ob = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    img = bpy.data.images.load(str(SRC / f"{name}.png"))
    m = bpy.data.materials.new("m"); m.use_nodes = True
    n = m.node_tree.nodes; t = n.new("ShaderNodeTexImage"); t.image = img
    b = n["Principled BSDF"]; b.inputs["Roughness"].default_value = 0.85
    m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
    ob.data.materials.clear(); ob.data.materials.append(m)
    bpy.context.view_layer.update()
    lo = min((ob.matrix_world @ Vector(c)).z for c in ob.bound_box)
    ob.location.z -= lo
    bpy.context.view_layer.update()
    return ob

def light_rig(s):
    w = bpy.data.worlds.new("w"); s.world = w; w.use_nodes = True
    bg = w.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.9, 0.88, 0.85, 1); bg.inputs[1].default_value = 0.45
    for loc, e, size in (((-2.5, -3, 4), 160, 3.0), ((3, 1.5, 2), 40, 4.0)):
        l = bpy.data.lights.new("l", "AREA"); l.energy = e; l.size = size
        o = bpy.data.objects.new("l", l); s.collection.objects.link(o); o.location = loc
        d = (Vector((0, 0, 0.3)) - Vector(loc)); o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()

def camera(s, ob, yaw, elev, margin):
    bb = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    ctr = sum(bb, Vector()) / 8; ext = max((max(v[i] for v in bb) - min(v[i] for v in bb)) for i in range(3))
    diag = math.sqrt(sum((max(v[i] for v in bb) - min(v[i] for v in bb)) ** 2 for i in range(3)))
    cam = bpy.data.cameras.new("c"); cam.type = "ORTHO"; cam.ortho_scale = diag * margin
    co = bpy.data.objects.new("c", cam); s.collection.objects.link(co); s.camera = co
    d = Vector((math.sin(yaw) * math.cos(elev), -math.cos(yaw) * math.cos(elev), math.sin(elev)))
    co.location = ctr + d * 6; co.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    return co

for name in names:
    if mode == "tile":
        s = setup(512, True)
        ob = load(name); light_rig(s)
        bpy.ops.mesh.primitive_plane_add(size=6); fl = bpy.context.active_object; fl.is_shadow_catcher = True
        camera(s, ob, math.radians(35), math.radians(30), 1.12)
        s.render.filepath = str(OUT / f"{name}_tile.png"); bpy.ops.render.render(write_still=True)
    else:
        views = []
        for k, yaw in enumerate((0, 40, 180)):
            s = setup(384, False)
            ob = load(name); light_rig(s)
            bpy.ops.mesh.primitive_plane_add(size=6); fl = bpy.context.active_object
            fm = bpy.data.materials.new("f"); fm.diffuse_color = (0.7, 0.7, 0.72, 1); fm.use_nodes = True
            fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.72, 0.72, 0.74, 1); fl.data.materials.append(fm)
            camera(s, ob, math.radians(yaw), math.radians(25), 0.95)
            p = OUT / f"{name}_v{k}.png"; s.render.filepath = str(p); bpy.ops.render.render(write_still=True)
