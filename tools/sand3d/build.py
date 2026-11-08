"""Builds sand3d items to GLB, converts each to USDZ the way apps/ios/Tools/make_items.py exports, and can render
the shop thumbnail.

Run (Python 3.13 with sand3d and bpy 5.2 installed, see docs/sand3d-spike.md):
  python tools/sand3d/build.py <out_dir> [--thumbs] [--samples N] [--fine] [name ...]

Writes <name>.glb, <name>.usdz and with --thumbs <name>.png into out_dir. Names are the keys of ITEMS; none
builds them all.
"""

import argparse
import math
import os
import sys

import bpy
import sand3d as s3d
from mathutils import Vector

import billet_style as st
from armchair import armchair
from drawers import chest_of_drawers
from plant import potted_plant

ITEMS = {
    "armchair": lambda: armchair(),
    "armchair_rose_tufted_tapered": lambda: armchair("rose", "tufted", "tapered"),
    "armchair_sage_flat_bun": lambda: armchair("sage", "flat", "bun"),
    "drawers": lambda: chest_of_drawers(),
    "drawers_open": lambda: chest_of_drawers(open=260),
    "plant_monstera": lambda: potted_plant("monstera"),
    "plant_snake_belly": lambda: potted_plant("snake", "belly", pot_color="#e9d2b0"),
    "plant_bush_sage": lambda: potted_plant("bush", pot_color="#8daa7e", leaf="#93a86a", leaf_dark="#6f8a4e"),
}


def build_glb(make, path):
    s3d.empty_scene()
    s3d.export(make(), path)


def glb_to_usdz(glb, usdz):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
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


def render_thumbnail(path, samples, size=512):
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


def run(items, out_dir, thumbs, samples):
    os.makedirs(out_dir, exist_ok=True)
    for name, make in items.items():
        glb, usdz = (os.path.join(out_dir, f"{name}.{ext}") for ext in ("glb", "usdz"))
        build_glb(make, glb)
        glb_to_usdz(glb, usdz)
        lo, hi = bounds()
        print("BOUNDS", name, " ".join(f"{a:.3f}..{b:.3f}" for a, b in zip(lo, hi)), flush=True)
        if thumbs:
            render_thumbnail(os.path.join(out_dir, f"{name}.png"), samples)
        print("ITEM", name, flush=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir")
    ap.add_argument("names", nargs="*")
    ap.add_argument("--thumbs", action="store_true")
    ap.add_argument("--samples", type=int, default=32)
    ap.add_argument("--fine", action="store_true", help="sand3d's own tessellation instead of the style's")
    a = ap.parse_args()
    if not a.fine:
        st.tessellate()
    unknown = set(a.names) - set(ITEMS)
    if unknown:
        sys.exit(f"unknown items: {', '.join(sorted(unknown))}")
    run({n: ITEMS[n] for n in (a.names or ITEMS)}, a.out_dir, a.thumbs, a.samples)
