"""One Idol prop mesh made game-ready in Blender: watertight, flat-bottomed, light, baked.

  dense textured .glb (splat2mesh, real-world metres, y-up, base centred)
  -> voxel remesh (closed, even triangles) -> flatten everything within `flat` of the floor onto
  y = 0, so it stands on a flat base -> decimate to the triangle budget -> smart UV unwrap with
  wide margins -> bake the colour from the dense mesh (selected to active, Cycles CPU, 4 threads)
  onto `px` square -> .obj (y-up, metres, pivot at the base centre) + .png + .json stats.

The prop is scaled so its `fit` measure (width: the larger of width and depth; or height) is
`size` metres: its real size.

Run: Blender -b --factory-startup -t 4 -P remesh_prop.py -- <in.glb> <out dir> <name>
     <tris> <width|height> <size m> [yaw degrees] [px] [voxel m]
"""

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix

argv = sys.argv[sys.argv.index("--") + 1 :]
SRC, OUT, NAME, TRIS = Path(argv[0]), Path(argv[1]), argv[2], int(argv[3])
FIT, SIZE = argv[4], float(argv[5])
YAW = math.radians(float(argv[6])) if len(argv) > 6 else 0.0
PX = int(argv[7]) if len(argv) > 7 else 512
VOXEL = float(argv[8]) if len(argv) > 8 else 0.0
OUT.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.threads_mode = "FIXED"
bpy.context.scene.render.threads = 4
bpy.ops.import_scene.gltf(filepath=str(SRC))
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
src = meshes[0]
src.name = "source"
bpy.context.view_layer.objects.active = src
src.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# Blender is z-up: the glTF importer turned the y-up file so that up is +z here. Idol's splats
# come out with up along -y, which splat2mesh keeps, so the prop is turned the right way up.
src.data.transform(Matrix.Rotation(math.pi, 4, "X"))
if YAW:
    src.data.transform(Matrix.Rotation(YAW, 4, "Z"))
dims = src.dimensions
measure = dims.z if FIT == "height" else max(dims.x, dims.y)
src.data.transform(Matrix.Scale(SIZE / measure, 4))
src.data.update()
bpy.context.view_layer.update()

dims = src.dimensions
size = max(dims)
voxel = VOXEL or size / 160

bpy.ops.object.select_all(action="DESELECT")
src.select_set(True)
bpy.ops.object.duplicate()
clean = bpy.context.selected_objects[0]
clean.name = NAME
clean.data.materials.clear()
bpy.context.view_layer.objects.active = clean

remesh = clean.modifiers.new("remesh", "REMESH")
remesh.mode = "VOXEL"
remesh.voxel_size = voxel
bpy.ops.object.modifier_apply(modifier=remesh.name)

# A flat base: everything within a few voxels of the floor goes onto it.
bm = bmesh.new()
bm.from_mesh(clean.data)
floor = min(v.co.z for v in bm.verts)
flat = max(voxel * 2, dims.z * 0.02)
for v in bm.verts:
    v.co.z = 0.0 if v.co.z - floor < flat else v.co.z - floor
bm.to_mesh(clean.data)
bm.free()
src.location.z -= floor

faces = sum(len(p.vertices) - 2 for p in clean.data.polygons)
dec = clean.modifiers.new("decimate", "DECIMATE")
dec.ratio = min(1.0, TRIS / max(faces, 1))
bpy.ops.object.modifier_apply(modifier=dec.name)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.quads_convert_to_tris()
bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.03)
bpy.ops.object.mode_set(mode="OBJECT")
for poly in clean.data.polygons:
    poly.use_smooth = True

image = bpy.data.images.new("albedo", PX, PX)
mat = bpy.data.materials.new("baked")
mat.use_nodes = True
tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
tex.image = image
mat.node_tree.links.new(tex.outputs["Color"], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
mat.node_tree.nodes.active = tex
clean.data.materials.append(mat)

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 4
bake = scene.render.bake
bake.use_selected_to_active = True
bake.cage_extrusion = voxel * 2
bake.max_ray_distance = voxel * 6
bake.margin = 16
bpy.ops.object.select_all(action="DESELECT")
src.select_set(True)
clean.select_set(True)
bpy.context.view_layer.objects.active = clean
bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
png = OUT / f"{NAME}.png"
image.filepath_raw = str(png)
image.file_format = "PNG"
image.save()

# The base's centre on the origin.
lo = [min(v.co[i] for v in clean.data.vertices) for i in range(3)]
hi = [max(v.co[i] for v in clean.data.vertices) for i in range(3)]
shift = [-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]]
clean.data.transform(Matrix.Translation(shift))

bpy.ops.object.select_all(action="DESELECT")
clean.select_set(True)
obj = OUT / f"{NAME}.obj"
bpy.ops.wm.obj_export(filepath=str(obj), export_selected_objects=True, forward_axis="NEGATIVE_Z",
                      up_axis="Y", export_materials=False, export_normals=True, export_uv=True)

bm = bmesh.new()
bm.from_mesh(clean.data)
edges_ok = all(e.is_manifold for e in bm.edges)
bm.free()
tris = sum(len(p.vertices) - 2 for p in clean.data.polygons)
# Blender x, y, z = the app's width (x), depth (-z) and height (y).
stats = {"name": NAME, "tris": tris, "verts": len(clean.data.vertices), "manifold": edges_ok,
         "metres": {"width": hi[0] - lo[0], "depth": hi[1] - lo[1], "height": hi[2] - lo[2]},
         "voxel": voxel, "px": PX}
(OUT / f"{NAME}.json").write_text(json.dumps(stats, indent=1))
print("REMESHED", json.dumps(stats))
