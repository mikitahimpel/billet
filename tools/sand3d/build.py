"""Builds sand3d items to GLB, converts each to USDZ the way apps/ios/Tools/make_items.py exports, and can render
the shop thumbnail.

Run (Python 3.13 with sand3d and bpy 5.2 installed, see README.md):
  python tools/sand3d/build.py <out_dir> [--thumbs] [--samples N] [--size PX] [--fine] [--glb] [id ...]

Writes Item_<id>.usdz and with --thumbs Item_<id>.png into out_dir, the names the app's bundle uses
(apps/ios/Nooki/Resources/Shop), and with --glb the GLB beside them. Ids are the keys of ITEMS: the shipped ones,
the armchair colourways of armchair-colourways.json, and a few spike pieces; none builds the shipped ones.
"""

import argparse
import json
import math
import os
import re
import sys
import tempfile

import bpy
import sand3d as s3d
from mathutils import Matrix, Vector

import billet_style as st
from armchair import armchair
from drawers import chest_of_drawers
from plant import potted_plant

HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(HERE, "armchair-colourways.json")) as f:
    COLOURWAYS = json.load(f)["variants"]

# Shipped in the app's bundle; build.py with no ids builds these.
SHIPPED = {
    **{v["id"]: (lambda v=v: armchair(v["fabric"], v["cushion"], v["legs"])) for v in COLOURWAYS},
    "chest": lambda: chest_of_drawers(),
    "monstera-potted": lambda: potted_plant("monstera", seed=3),
}
ITEMS = {
    **SHIPPED,
    "chest-open": lambda: chest_of_drawers(open=260),
    "snakeplant": lambda: potted_plant("snake", "belly", pot_color="#e9d2b0"),
    "bush": lambda: potted_plant("bush", pot_color="#8daa7e", leaf="#93a86a", leaf_dark="#6f8a4e"),
}


def build_glb(make, path):
    s3d.empty_scene()
    s3d.export(make(), path)


def bake_scale():
    """Sand3D's GLB keeps millimetres under a 0.001 scale on its root; pushes that scale into every local offset and
    every mesh, so each node's transform is in metres and the root's scale is 1.

    Uniform scale commutes with rotation, so S·T(t)·R = T(s·t)·R·S down the chain.
    """
    done = set()
    for root in [ob for ob in bpy.context.scene.objects if ob.parent is None]:
        s = root.scale.x
        if abs(s - 1) < 1e-9 or not (abs(root.scale.y - s) < 1e-9 and abs(root.scale.z - s) < 1e-9):
            continue
        root.scale = (1, 1, 1)
        if root.type == "MESH" and root.data.name not in done:
            root.data.transform(Matrix.Scale(s, 4))
            done.add(root.data.name)
        for ob in root.children_recursive:
            ob.location = ob.location * s
            if ob.type == "MESH" and ob.data.name not in done:
                ob.data.transform(Matrix.Scale(s, 4))
                done.add(ob.data.name)
    bpy.context.view_layer.update()


def name_joints():
    """Gives each joint's moving node its joint's name. Sand3D names the joint node after its part, Blender renames
    the clash to `<name>.001`, and USD would export that as `<name>_001`; the part itself becomes `<name>_part`.
    """
    for ob in list(bpy.context.scene.objects):
        m = re.fullmatch(r"(.+)\.001", ob.name)
        if not m or "s3d_joint" not in ob:
            continue
        clash = bpy.context.scene.objects.get(m.group(1))
        if clash is not None:
            clash.name = f"{m.group(1)}_part"
        ob.name = m.group(1)


def glb_to_usdz(glb, usdz):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    bake_scale()
    name_joints()
    # Same settings as make_items.export_usdz: Blender's Z up becomes USD's Y up, metres, preview surfaces.
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.wm.usd_export(
        filepath=usdz,
        selected_objects_only=True,
        export_materials=True,
        generate_preview_surface=True,
        export_animation=False,
        convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y",
        evaluation_mode="RENDER",
    )


def bounds():
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH":
            continue
        for v in ob.data.vertices:
            p = ob.matrix_world @ v.co
            lo, hi = Vector(map(min, lo, p)), Vector(map(max, hi, p))
    return lo, hi


def render_thumbnail(path, samples, size):
    """make_items.render_thumbnail's camera, lights and shadow catcher, at a lower cost for a busy machine."""
    scene = bpy.context.scene
    lo, hi = bounds()
    center, radius = (lo + hi) / 2, (hi - lo).length / 2
    bpy.ops.mesh.primitive_plane_add(size=radius * 40, location=(center.x, center.y, lo.z))
    bpy.context.object.is_shadow_catcher = True
    world = bpy.data.worlds.new("World")
    world.color = (0.95, 0.82, 0.7)
    scene.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy, sun.data.angle, sun.data.color = 2.6, math.radians(35), (1.0, 0.93, 0.84)
    sun.rotation_euler = (math.radians(22), 0, math.radians(-35))
    scene.collection.objects.link(sun)
    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "SUN"))
    fill.data.energy, fill.data.angle, fill.data.use_shadow = 1.0, math.radians(90), False
    fill.rotation_euler = (math.radians(60), 0, math.radians(30))
    scene.collection.objects.link(fill)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 70
    scene.collection.objects.link(cam)
    fov = 2 * math.atan(18 / cam.data.lens)
    direction = Vector((0.55, -1.0, 0.62)).normalized()
    cam.location = center + direction * (radius / math.sin(fov / 2)) * 1.2
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (center - cam.location).to_track_quat("-Z", "Y")
    scene.camera = cam
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.view_settings.view_transform = "Standard"
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def run(items, out_dir, thumbs, samples, size=1024, keep_glb=False):
    os.makedirs(out_dir, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for name, make in items.items():
            glb = os.path.join(out_dir if keep_glb else tmp, f"Item_{name}.glb")
            usdz = os.path.join(out_dir, f"Item_{name}.usdz")
            build_glb(make, glb)
            glb_to_usdz(glb, usdz)
            lo, hi = bounds()
            print("BOUNDS", name, " ".join(f"{a:.3f}..{b:.3f}" for a, b in zip(lo, hi)), flush=True)
            if thumbs:
                render_thumbnail(os.path.join(out_dir, f"Item_{name}.png"), samples, size)
            print("ITEM", name, flush=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir")
    ap.add_argument("names", nargs="*")
    ap.add_argument("--thumbs", action="store_true")
    ap.add_argument("--samples", type=int, default=24)
    ap.add_argument("--size", type=int, default=1024, help="thumbnail pixels a side; the bundle's are 1024")
    ap.add_argument("--fine", action="store_true", help="sand3d's own tessellation instead of the style's")
    ap.add_argument("--glb", action="store_true", help="keep each GLB beside its USDZ")
    a = ap.parse_args()
    if not a.fine:
        st.tessellate()
    unknown = set(a.names) - set(ITEMS)
    if unknown:
        sys.exit(f"unknown items: {', '.join(sorted(unknown))}")
    run({n: ITEMS[n] for n in (a.names or SHIPPED)}, a.out_dir, a.thumbs, a.samples, a.size, a.glb)
