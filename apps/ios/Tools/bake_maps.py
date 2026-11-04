"""Bakes a tangent-space normal map and ambient occlusion from a detailed mesh onto a low one's UVs, for
make_mochi_mesh.py.

Run:
  blender -b --python Tools/bake_maps.py -- high.obj low.obj normal.png ao.png [size]
"""
import sys
import bpy

args = sys.argv[sys.argv.index("--") + 1:]
high_path, low_path, normal_out, ao_out = args[:4]
size = int(args[4]) if len(args) > 4 else 2048

bpy.ops.wm.read_factory_settings(use_empty=True)
objects = []
for path in (high_path, low_path):
    bpy.ops.wm.obj_import(filepath=path)
    o = bpy.context.selected_objects[0]
    bpy.ops.object.shade_smooth()
    objects.append(o)
high, low = objects

material = bpy.data.materials.new("Bake")
node = material.node_tree.nodes.new("ShaderNodeTexImage")
material.node_tree.nodes.active = node
low.data.materials.append(material)

scene = bpy.context.scene
scene.render.engine = "CYCLES"
bake = scene.render.bake
bake.use_selected_to_active = True
bake.cage_extrusion = 0.004
bake.max_ray_distance = 0.008
bake.margin = 8
bake.normal_space = "TANGENT"
bpy.ops.object.select_all(action="DESELECT")
high.select_set(True)
low.select_set(True)
bpy.context.view_layer.objects.active = low

# Occlusion is the low mesh's own: the high one, lying right on it, would shadow everything.
for kind, out, samples in (("NORMAL", normal_out, 1), ("AO", ao_out, 64)):
    image = bpy.data.images.new(kind, size, size)
    image.colorspace_settings.name = "Non-Color"
    node.image = image
    scene.cycles.samples = samples
    bake.use_selected_to_active = kind == "NORMAL"
    high.hide_render = kind == "AO"
    high.select_set(kind == "NORMAL")
    bpy.ops.object.bake(type=kind)
    image.filepath_raw = out
    image.file_format = "PNG"
    image.save()
