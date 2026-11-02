"""Makes the soft heart of the first-launch scene, from code alone, as two halves.

Run: Blender -b --python make_heart.py -- [--render <folder>]
Writes assets-source/heart/Heart.usdz. bake_heart.sh compiles it.

  heart        the whole heart, its middle at the origin
    heart_L    the left half, from the viewer's side
    heart_R    the right half

Each half is a sphere shaped into a soft teardrop, round at its crown and tapering to a rounded
tip, leant out from upright about the tip. The two tips meet at the bottom and the crowns overlap
a little in the middle, so together they read as one puffy heart, and apart each is a whole soft
piece with no cut face. The halves share the heart's origin, so moving a half apart is a plain
offset. Materials are set in the app; the file carries only shape and smooth normals.
"""

from __future__ import annotations

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets-source", "heart")

# Rings and segments of the sphere each half is shaped from.
RINGS = 40
SEGMENTS = 56
# The heart's height in metres once made, tip to the top of the lobes.
HEIGHT = 0.2
# How far each half leans out from upright, and how deep it is against its width.
LEAN = math.radians(27)
DEPTH = 0.95


def lobe_width(z: float) -> float:
    """The half's width at height `z` from -1 (its tip) to 1 (its crown): round at the crown,
    tapering softly to a rounded tip."""
    ring = math.sqrt(max(0.0, 1 - z * z))
    swell = 0.14 + 0.86 * ((z + 1) / 2) ** 0.8
    return ring * swell


def half_mesh(left: bool) -> bmesh.types.BMesh:
    mesh = bmesh.new()
    bmesh.ops.create_uvsphere(mesh, u_segments=SEGMENTS, v_segments=RINGS, radius=1)
    lean = LEAN if left else -LEAN
    for vertex in mesh.verts:
        x, y, z = vertex.co
        width = lobe_width(z)
        ring = math.sqrt(max(1e-9, 1 - z * z))
        x, y = x / ring * width * 0.8, y / ring * width * 0.8 * DEPTH
        # Stand it on its tip at the origin, then lean it out about the tip.
        z = z + 1
        x, z = x * math.cos(lean) - z * math.sin(lean), x * math.sin(lean) + z * math.cos(lean)
        # A little into the middle above the tip, so the lobes overlap there and read as one
        # heart while together; the tips stay where they meet.
        x += (0.1 if left else -0.1) * min(z, 0.6) / 0.6
        vertex.co = Vector((x, y, z))
    bmesh.ops.smooth_vert(
        mesh, verts=mesh.verts, factor=0.3, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    return mesh


def half(left: bool, name: str) -> bpy.types.Object:
    mesh = half_mesh(left)
    data = bpy.data.meshes.new(name)
    mesh.to_mesh(data)
    mesh.free()
    for polygon in data.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new(name, data)
    material = bpy.data.materials.new(f"{name}_mat")
    material.use_nodes = True
    shader = material.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = (0.9, 0.18, 0.22, 1)
    shader.inputs["Roughness"].default_value = 0.35
    data.materials.append(material)
    return obj


def build() -> bpy.types.Object:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    root = bpy.data.objects.new("heart", None)
    bpy.context.scene.collection.objects.link(root)
    for side, left in (("heart_L", True), ("heart_R", False)):
        obj = half(left, side)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent = root
    centre_on_box(root)
    return root


def centre_on_box(root: bpy.types.Object) -> None:
    low = Vector((math.inf,) * 3)
    high = Vector((-math.inf,) * 3)
    for child in root.children:
        for vertex in child.data.vertices:
            for axis in range(3):
                low[axis] = min(low[axis], vertex.co[axis])
                high[axis] = max(high[axis], vertex.co[axis])
    middle = (low + high) / 2
    scale = HEIGHT / (high.z - low.z)
    for child in root.children:
        for vertex in child.data.vertices:
            vertex.co = (vertex.co - middle) * scale
    low, high = (low - middle) * scale, (high - middle) * scale
    print(f"heart size {tuple(round(v, 4) for v in (high - low))}")


def export(root: bpy.types.Object) -> str:
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "Heart.usdz")
    bpy.ops.wm.usd_export(
        filepath=path, selected_objects_only=False, export_animation=False, export_materials=True,
        export_normals=True, export_uvmaps=False, generate_preview_surface=True,
        convert_orientation=True, export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y", root_prim_path="", merge_parent_xform=False,
        triangulate_meshes=True, export_lights=False, export_cameras=False)
    print(f"exported {path}")
    return path


def render(folder: str) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    camera_data = bpy.data.cameras.new("camera")
    camera = bpy.data.objects.new("camera", camera_data)
    camera.location = (0.08, -0.55, 0.06)
    camera.rotation_euler = (math.radians(84), 0, math.radians(8))
    scene.collection.objects.link(camera)
    scene.camera = camera
    light_data = bpy.data.lights.new("key", "AREA")
    light_data.energy = 6
    light = bpy.data.objects.new("key", light_data)
    light.location = (0.3, -0.4, 0.4)
    light.rotation_euler = (math.radians(50), 0, math.radians(30))
    scene.collection.objects.link(light)
    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.08, 0.04, 0.03, 1)
    scene.world = world
    for name, offset in (("together", 0.0), ("apart", 0.04)):
        bpy.data.objects["heart_L"].location.x = -offset
        bpy.data.objects["heart_R"].location.x = offset
        scene.render.filepath = os.path.join(folder, f"heart-{name}.png")
        bpy.ops.render.render(write_still=True)
    bpy.data.objects["heart_L"].location.x = 0
    bpy.data.objects["heart_R"].location.x = 0


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    root = build()
    if "--render" in args:
        render(args[args.index("--render") + 1])
    export(root)


main()
