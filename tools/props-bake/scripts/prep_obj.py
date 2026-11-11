"""Orient and centre remeshed props: yaw about Y, origin at the base centre (floor) or the middle (wall).
Usage: python prep_obj.py <remeshed dir> <out dir> <id>=<name>:<yaw deg>:<floor|wall> ...
Front is +Z after the yaw; a wall piece keeps its back at -z.
"""
import json, math, shutil, sys
from pathlib import Path
src, out = Path(sys.argv[1]), Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
for arg in sys.argv[3:]:
    iid, rest = arg.split("="); name, yaw, mount = rest.split(":"); a = math.radians(float(yaw)); c, s = math.cos(a), math.sin(a)
    rot = lambda x, y, z: (x * c + z * s, y, -x * s + z * c)
    lines = (src / f"{name}.obj").read_text().splitlines(); vs = []
    for l in lines:
        if l.startswith("v "): vs.append(rot(*map(float, l.split()[1:4])))
    mn = [min(v[i] for v in vs) for i in range(3)]; mx = [max(v[i] for v in vs) for i in range(3)]
    cx, cz = (mn[0] + mx[0]) / 2, (mn[2] + mx[2]) / 2
    off = (cx, (mn[1] + mx[1]) / 2 if mount == "wall" else mn[1], cz)
    res = []
    for l in lines:
        p = l.split()
        if l.startswith("v "):
            x, y, z = rot(*map(float, p[1:4])); res.append("v %.6f %.6f %.6f" % (x - off[0], y - off[1], z - off[2]))
        elif l.startswith("vn "): res.append("vn %.6f %.6f %.6f" % rot(*map(float, p[1:4])))
        else: res.append(l)
    (out / f"{iid}.obj").write_text("\n".join(res) + "\n"); shutil.copy(src / f"{name}.png", out / f"{iid}.png")
    j = json.loads((src / f"{name}.json").read_text()); j["metres"] = {"width": mx[0] - mn[0], "depth": mx[2] - mn[2], "height": mx[1] - mn[1]}
    (out / f"{iid}.json").write_text(json.dumps(j))
