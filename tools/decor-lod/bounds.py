"""Measures the models the room draws: width (x), depth (z) and height (y) in the model's own units, written to
tools/decor-lod/bounds.json for catalog.py. Run after a model is added or changed.

blender -b -P tools/decor-lod/bounds.py -- apps/ios/Nooki/Resources tools/decor-lod/bounds.json
"""

import glob
import json
import os
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1 :]
resources, out = argv
files = sorted(glob.glob(os.path.join(resources, "Decor/Decor_*.usdz")) + glob.glob(os.path.join(resources, "Shop/Item_*.usdz")))
result = {}
for path in files:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.usd_import(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for o in meshes:
        for corner in o.bound_box:
            p = o.matrix_world @ __import__("mathutils").Vector(corner)
            for i in range(3):
                lo[i] = min(lo[i], p[i])
                hi[i] = max(hi[i], p[i])
    # Blender is Z up and USD's front is -Y: width is x, depth y, height z.
    name = os.path.basename(path)[: -len(".usdz")]
    result[name] = {"width": round(hi[0] - lo[0], 4), "depth": round(hi[1] - lo[1], 4), "height": round(hi[2] - lo[2], 4)}
json.dump(result, open(out, "w"), indent=1, sort_keys=True)
print("BOUNDS", len(result))
