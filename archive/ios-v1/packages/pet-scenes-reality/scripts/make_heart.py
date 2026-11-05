"""Makes the soft heart of the first-launch scene, from code alone, as two halves.

Run: Blender -b --python make_heart.py -- [--render <folder>]
Writes assets-source/heart/Heart.usdz. bake_heart.sh compiles it.

  heart        the whole heart, its middle at the origin
    heart_L    the left half, from the viewer's side
    heart_R    the right half

The heart is one classic puffy heart, two round lobes over a single point, cut straight down its
middle. So each half has one lobe, a flat inner face and half of the point, and the two together
are exactly the whole heart. The halves share the heart's origin, so moving a half apart is a
plain offset. Materials are set in the app; the file carries only shape and normals: smooth on
the outside, flat on the cut.
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

# Rings and segments of the sphere the heart is shaped from.
RINGS = 48
SEGMENTS = 64
# The heart's height in metres once made, tip to the top of the lobes.
HEIGHT = 0.2
# How deep it is: larger is thinner front to back.
THINNESS = 2.0
# How deep the dip between the lobes is: larger makes rounder, more separate lobes.
CLEFT = 3.2


def inside(x: float, y: float, z: float) -> float:
    """Below zero inside the heart: Taubin's heart surface, x across, y deep, z up, with the cube
    root taken so its gradient does not vanish on the surface."""
    lobes = CLEFT * x * x + 0.1 * y * y
    return x * x + THINNESS * y * y + z * z - 1 - z * lobes ** (1 / 3)


def reach(direction: Vector) -> float:
    """How far the surface is from the middle along `direction`: the first way out."""
    step = 0.01
    r = 0.0
    while inside(*(direction * (r + step))) < 0 and r < 3:
        r += step
    low, high = r, r + step
    for _ in range(30):
        middle = (low + high) / 2
        if inside(*(direction * middle)) < 0:
            low = middle
        else:
            high = middle
    return (low + high) / 2


def surface_normal(point: Vector) -> Vector:
    """The way out of the heart at `point`, from the surface's gradient, so the two halves'
    shading runs on across the cut without a line."""
    h = 1e-4
    gradient = Vector(
        [
            inside(*(point + Vector(axis) * h)) - inside(*(point - Vector(axis) * h))
            for axis in ((1, 0, 0), (0, 1, 0), (0, 0, 1))
        ])
    return gradient.normalized() if gradient.length > 0 else point.normalized()


def heart_mesh() -> bmesh.types.BMesh:
    mesh = bmesh.new()
    bmesh.ops.create_uvsphere(mesh, u_segments=SEGMENTS, v_segments=RINGS, radius=1)
    for vertex in mesh.verts:
        direction = vertex.co.normalized()
        vertex.co = direction * reach(direction)
    return mesh


def half_mesh(left: bool) -> bmesh.types.BMesh:
    """One half of the heart, cut at x = 0 and closed with a flat face."""
    mesh = heart_mesh()
    geometry = mesh.verts[:] + mesh.edges[:] + mesh.faces[:]
    cut = bmesh.ops.bisect_plane(
        mesh, geom=geometry, dist=1e-6, plane_co=(0, 0, 0), plane_no=(1, 0, 0),
        clear_outer=left, clear_inner=not left)
    for face in mesh.faces:
        face.smooth = True
    rim = [e for e in cut["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    # The cut face gets its own vertices, so its flat normal does not bend the outside's.
    bmesh.ops.split_edges(mesh, edges=rim)
    loose = [e for e in mesh.edges if e.is_boundary]
    filled = bmesh.ops.triangle_fill(mesh, use_beauty=True, use_dissolve=False, edges=loose)
    for face in filled["geom"]:
        if isinstance(face, bmesh.types.BMFace):
            face.smooth = False
    bmesh.ops.recalc_face_normals(mesh, faces=mesh.faces)
    return mesh


def half(left: bool, name: str) -> bpy.types.Object:
    mesh = half_mesh(left)
    data = bpy.data.meshes.new(name)
    mesh.to_mesh(data)
    mesh.free()
    # Smooth on the outside by the surface itself, flat on the cut, facing the other half.
    cut = Vector((1, 0, 0)) if left else Vector((-1, 0, 0))
    normals = []
    for polygon in data.polygons:
        for index in polygon.loop_indices:
            point = data.vertices[data.loops[index].vertex_index].co
            normals.append(surface_normal(point) if polygon.use_smooth else cut)
    data.normals_split_custom_set(normals)
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
