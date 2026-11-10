"""Writes CatStanding.usdz sitting as a still mesh, for the Blender renders of Mochi (coat cards, portraits).

Run with any Python that has pxr and numpy (Blender's does):
  python Tools/sit_mesh.py [model.usdz] <out dir>
  blender -b --python Tools/sit_mesh.py -- [model.usdz] <out dir>

Poses the mesh's joints as cat_pose.py poses the rig's bones, moves every vertex by its joint weights as RealityKit
does (linear blending), drops the skeleton, moves her so she sits about the origin, and writes <out dir>/sitting.usda
beside the model's textures.
"""

import json
import os
import sys
import zipfile
from pathlib import Path

import numpy as np
from pxr import Usd, UsdGeom, UsdSkel, Vt

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cat_pose import SEAT, act, sit_poses  # noqa: E402

RES = Path(__file__).resolve().parents[1] / "Nooki/Resources"


def sit(model, out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(model) as package:
        package.extractall(out)
    layer = next(n for n in os.listdir(out) if n.endswith(".usdc"))
    stage = Usd.Stage.Open(str(out / layer))
    rig = json.loads((RES / "MochiStanding.rig.json").read_text())
    bones = [b["name"] for b in rig["bones"]]
    poses = sit_poses(rig)

    skel = UsdSkel.Skeleton(next(p for p in stage.Traverse() if p.IsA(UsdSkel.Skeleton)))
    paths = [str(p) for p in skel.GetJointsAttr().Get()]
    names = [p.split("/")[-1] for p in paths]
    rest = [np.array(m)[3, :3] for m in skel.GetBindTransformsAttr().Get()]
    # CatMeshRig: a `<bone>Pivot` joint turns as its bone and rides on its parent joint's bone.
    joints = []
    for j, name in enumerate(names):
        pivot = name.endswith("Pivot")
        q, t = poses[bones.index(name[:-5] if pivot else name)]
        if pivot:
            parent = names[paths.index(paths[j].rsplit("/", 1)[0])]
            pq, pt = poses[bones.index(parent)]
            t = act(pq, rest[j]) + pt - act(q, rest[j])
        joints.append((q, t))

    for prim in stage.Traverse():
        binding = UsdSkel.BindingAPI(prim)
        if not prim.IsA(UsdGeom.Mesh) or not binding.GetJointIndicesPrimvar().HasValue():
            continue
        mesh = UsdGeom.Mesh(prim)
        points = np.array(mesh.GetPointsAttr().Get(), np.float64)
        index = np.array(binding.GetJointIndicesPrimvar().Get()).reshape(len(points), -1)
        weight = np.array(binding.GetJointWeightsPrimvar().Get()).reshape(len(points), -1)
        moved = np.zeros_like(points)
        for j, (q, t) in enumerate(joints):
            share = (weight * (index == j)).sum(1)
            if share.any():
                moved += share[:, None] * (act_all(q, points) + t)
        mesh.GetPointsAttr().Set(Vt.Vec3fArray.FromNumpy((moved - SEAT).astype(np.float32)))
        for name in ("primvars:skel:jointIndices", "primvars:skel:jointWeights", "primvars:skel:geomBindTransform",
                     "skel:skeleton"):
            if prim.HasProperty(name):
                prim.RemoveProperty(name)
        prim.RemoveAPI(UsdSkel.BindingAPI)
    for prim in stage.Traverse():
        if prim.HasProperty("skel:skeleton"):
            prim.RemoveProperty("skel:skeleton")
    stage.RemovePrim(skel.GetPath())
    path = out / "sitting.usda"
    stage.GetRootLayer().Export(str(path))
    return path


def act_all(q, points):
    u = q[:3]
    return points + 2 * np.cross(u, np.cross(u, points) + q[3] * points)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    model, out = (args[0], args[1]) if len(args) > 1 else (RES / "CatStanding.usdz", args[0])
    print(sit(model, out))
