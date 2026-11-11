"""Makes the room's light copy of a shop model: one mesh, at most `--tris` triangles, the same materials.

blender -b -P decimate.py -- Item_armchair.usdz Decor_armchair.usdz --tris 6000
"""

import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1 :]
source, target = argv[0], argv[1]
budget = int(argv[argv.index("--tris") + 1]) if "--tris" in argv else 6000

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=source)

meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
body = bpy.context.view_layer.objects.active

# Bake the transforms of the parents the import kept.
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def colour(material):
    if material and material.node_tree:
        for node in material.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                return tuple(node.inputs["Base Color"].default_value[:3])
    return (0.5, 0.5, 0.5)


# Few materials, few draw calls: merge the two closest colours until `--parts` are left.
parts = int(argv[argv.index("--parts") + 1]) if "--parts" in argv else 3
slots = [colour(m) for m in body.data.materials]
groups = {i: i for i in range(len(slots))}
live = set(range(len(slots)))
while len(live) > parts:
    a, b = min(
        ((a, b) for a in live for b in live if a < b),
        key=lambda ab: sum((x - y) ** 2 for x, y in zip(slots[ab[0]], slots[ab[1]])),
    )
    for k, v in groups.items():
        if v == b:
            groups[k] = a
    live.discard(b)
for polygon in body.data.polygons:
    polygon.material_index = groups[polygon.material_index]
keep = sorted(live)
for index in reversed(range(len(slots))):
    if index not in keep:
        body.data.materials.pop(index=index)

tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
if tris > budget:
    mod = body.modifiers.new("lod", "DECIMATE")
    mod.ratio = budget / tris
    bpy.ops.object.modifier_apply(modifier=mod.name)
print("DECOR", source, tris, "->", sum(len(p.vertices) - 2 for p in body.data.polygons), len(body.data.materials))

bpy.ops.wm.usd_export(filepath=target, export_materials=True, export_animation=False)
