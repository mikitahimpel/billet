"""Measures USDZ models without Blender: file size, triangles, meshes, materials and textures.

Run:
  python3 tools/sand3d/measure.py <file.usdz> ...

Needs `usdcat` (macOS ships it in /usr/bin) and `sips` for texture sizes. Prints a Markdown table.
"""

import os
import re
import subprocess
import sys
import tempfile
import zipfile


def usda_of(usdz):
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "flat.usda")
        subprocess.run(["usdcat", "--flatten", usdz, "-o", out], check=True, capture_output=True)
        with open(out) as f:
            return f.read()


def textures(usdz):
    found = []
    with zipfile.ZipFile(usdz) as z, tempfile.TemporaryDirectory() as tmp:
        for info in z.infolist():
            if not info.filename.lower().endswith((".png", ".jpg", ".jpeg", ".exr")):
                continue
            path = z.extract(info, tmp)
            dims = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path],
                                  capture_output=True, text=True).stdout
            w, h = (re.search(rf"{k}: (\d+)", dims).group(1) for k in ("pixelWidth", "pixelHeight"))
            found.append(f"{w}×{h}")
    return found


def measure(usdz):
    text = usda_of(usdz)
    tris = 0
    for block in re.findall(r"int\[\] faceVertexCounts = \[([^\]]*)\]", text):
        tris += sum(int(n) - 2 for n in block.split(","))
    meshes = len(re.findall(r"\bdef Mesh\b", text))
    materials = len(re.findall(r"\bdef Material\b", text))
    up = re.search(r'upAxis = "(\w)"', text)
    mpu = re.search(r"metersPerUnit = ([\d.]+)", text)
    return dict(name=os.path.basename(usdz), kb=os.path.getsize(usdz) / 1024, tris=tris, meshes=meshes,
                materials=materials, textures=textures(usdz), up=up.group(1) if up else "?",
                mpu=mpu.group(1) if mpu else "?")


def main(paths):
    print("| Model | KB | Triangles | Meshes | Materials | Textures | Up, m/unit |")
    print("| --- | ---: | ---: | ---: | ---: | --- | --- |")
    for p in paths:
        m = measure(p)
        print(f"| {m['name']} | {m['kb']:.0f} | {m['tris']:,} | {m['meshes']} | {m['materials']} | "
              f"{', '.join(m['textures']) or 'none'} | {m['up']}, {m['mpu']} |")


if __name__ == "__main__":
    main(sys.argv[1:])
