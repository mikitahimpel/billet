"""How high each clip of a cat holds its lowest point, for standing the cat on what it is on.

The room stands a cat's model with the lowest point of its rest pose (tail and all) on the
surface under it. In a clip the lowest paw or the belly is usually higher than that, so the cat
floats, or lower, so it sinks in. For every clip in clips.json, every second frame (15 a second),
this measures the lowest point of the body, without the tail (which curls over what it touches),
above the rest pose's lowest point, in shares of the length the app scales the cat by.

Run inside Blender, once per cat:
  Blender -b -P measure_cat_ground.py -- <Cat.usdz> <clips.json> <length> <out.json>
or for every cat at once with scripts/bake_cat_ground.sh.
"""

import json
import sys
from pathlib import Path

import bpy
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1 :]
USDZ, CLIPS, LENGTH, OUT = Path(argv[0]), Path(argv[1]), float(argv[2]), Path(argv[3])
STEP = 2

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=str(USDZ))
scene = bpy.context.scene
table = json.loads(CLIPS.read_text())
table = table.get("clips", table)
# Blender reads the timeline at its own rate; the rate that fits its frames to the table's last
# second is the file's.
fps = round((scene.frame_end - scene.frame_start) / max(c["trimEnd"] for c in table.values()))
meshes = [o for o in scene.objects if o.type == "MESH"]


def body_mask(o):
    names = {g.index: g.name for g in o.vertex_groups}
    keep = []
    for v in o.data.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        keep.append(not (best and names.get(best.group, "").lower().startswith("tail")))
    return np.array(keep, dtype=bool)


body = {o.name: body_mask(o) for o in meshes}


def heights(masks):
    deps = bpy.context.evaluated_depsgraph_get()
    out = []
    for o in meshes:
        ev = o.evaluated_get(deps)
        m = ev.to_mesh()
        mw = np.array(ev.matrix_world)
        co = np.array([v.co for v in m.vertices])
        z = co @ mw[2, :3] + mw[2, 3]
        mask = masks.get(o.name) if masks else None
        out.append(z[mask] if mask is not None and len(mask) == len(z) else z)
        ev.to_mesh_clear()
    return np.concatenate(out)


arm = next(o for o in scene.objects if o.type == "ARMATURE")
arm.data.pose_position = "REST"
bpy.context.view_layer.update()
rest = heights(None)
floor = float(rest.min())
# The rest pose's height, in shares of the length, for checking the app loads the same pose.
tall = round((float(rest.max()) - floor) / LENGTH, 4)
arm.data.pose_position = "POSE"
bpy.context.view_layer.update()

clips = {}
for name, clip in sorted(table.items()):
    first = round(clip["trimStart"] * fps) + 1
    last = round(clip["trimEnd"] * fps) + 1
    lows = []
    for f in range(first, last + 1, STEP):
        scene.frame_set(f)
        lows.append(round((float(heights(body).min()) - floor) / LENGTH, 4))
    clips[name] = lows
OUT.write_text(json.dumps({"rate": fps / STEP, "rest": tall, "clips": clips}, separators=(",", ":"), sort_keys=True) + "\n")
print("GROUND", OUT)
