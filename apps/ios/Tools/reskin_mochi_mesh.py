"""Gives CatStanding.usdz joints for the rig's bones it lacks, and reweights the vertices those bones take.

Run with make_mochi_mesh.py's Python:
  python Tools/reskin_mochi_mesh.py [--name MochiStanding]

A bone added to the rig (tools/cat-gen/rigs, then skin.py) moves the splat at once; the mesh fallback only once it has a
joint of that name. This adds each missing bone as a joint after the existing ones, resting unrotated at its head as
make_mochi_mesh.py places joints, and gives every vertex the new bones claim a share of the weights make_mochi_mesh.py
would give it from the current skin. Everything else in the USDZ stays as it is, without a rebuild through Blender.
"""
import argparse
import json
import os
import shutil
import tempfile
import zipfile

import numpy as np
from pxr import Gf, Usd, UsdGeom, UsdSkel, UsdUtils, Vt

from make_mochi_mesh import RESOURCES, read_splat, skin_weights, top4


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--name", default="MochiStanding", help="the splat and rig the mesh was built from")
    args = parser.parse_args()
    path = os.path.join(RESOURCES, "Cat" + args.name.removeprefix("Mochi") + ".usdz")

    splat = read_splat(os.path.join(RESOURCES, f"{args.name}.ply"))
    bones = json.load(open(os.path.join(RESOURCES, f"{args.name}.rig.json")))["bones"]
    skin = np.frombuffer(open(os.path.join(RESOURCES, f"{args.name}.skin"), "rb").read(), np.uint8).reshape(-1, 2, 4)

    work = tempfile.mkdtemp(prefix="mochi_reskin_")
    with zipfile.ZipFile(path) as package:
        package.extractall(work)
    layer = next(n for n in os.listdir(work) if n.endswith(".usdc"))
    stage = Usd.Stage.Open(os.path.join(work, layer))
    skel = UsdSkel.Skeleton(next(p for p in stage.Traverse() if p.IsA(UsdSkel.Skeleton)))
    paths = list(skel.GetJointsAttr().Get())
    names = [p.split("/")[-1] for p in paths]
    added = [b for b in bones if b["name"] not in names]
    if not added:
        print(f"{path}: already has every bone")
        return

    bind = list(skel.GetBindTransformsAttr().Get())
    rest = list(skel.GetRestTransformsAttr().Get())
    for b in added:
        parent = paths[names.index(b["parent"])]
        world = Gf.Matrix4d(1)
        world.SetTranslateOnly(Gf.Vec3d(*b["head"]))
        paths.append(f"{parent}/{b['name']}")
        names.append(b["name"])
        bind.append(world)
        rest.append(world * bind[names.index(b["parent"])].GetInverse())
    skel.GetJointsAttr().Set(paths)
    skel.GetJointNamesAttr().Set(names)
    skel.GetBindTransformsAttr().Set(Vt.Matrix4dArray(bind))
    skel.GetRestTransformsAttr().Set(Vt.Matrix4dArray(rest))

    # Skin columns in the rig's order, each the joint of that bone's name.
    joint = np.array([names.index(b["name"]) for b in bones])
    new = np.array([b in added for b in bones])
    for prim in stage.Traverse():
        binding = UsdSkel.BindingAPI(prim)
        if not prim.IsA(UsdGeom.Mesh) or not binding.GetJointIndicesPrimvar().HasValue():
            continue
        points = np.array(prim.GetAttribute("points").Get(), np.float64)
        index = np.array(binding.GetJointIndicesPrimvar().Get(), np.int32).reshape(-1, 4)
        weight = np.array(binding.GetJointWeightsPrimvar().Get(), np.float32).reshape(-1, 4)
        weights = skin_weights(splat, skin, points, bones)
        # Only the skinned surface; the rigid parts (eyes, lids, collar, bell) keep their one joint.
        faces = np.array(UsdGeom.Mesh(prim).GetFaceVertexIndicesAttr().Get(), np.int64).reshape(-1, 3)
        skinned = np.zeros(len(points), bool)
        for subset in UsdGeom.Subset.GetAllGeomSubsets(UsdGeom.Mesh(prim)):
            if subset.GetPrim().GetName().rstrip("0123456789") in ("Body", "Fur", "Fins"):
                skinned[faces[np.array(subset.GetIndicesAttr().Get())].ravel()] = True
        taken = (weights[:, new].sum(1) > 0.01) & skinned
        top, amount = top4(weights[taken])
        index[taken] = joint[top]
        weight[taken] = amount
        binding.GetJointIndicesPrimvar().Set(Vt.IntArray.FromNumpy(index.ravel()))
        binding.GetJointWeightsPrimvar().Set(Vt.FloatArray.FromNumpy(weight.ravel()))
        print(f"{prim.GetPath()}: {taken.sum()} of {len(points)} vertices reweighted")
    # Exported rather than saved: a saved crate file keeps the replaced arrays as dead space.
    fresh = os.path.join(work, "fresh")
    os.makedirs(fresh)
    stage.GetRootLayer().Export(os.path.join(fresh, layer))
    for name in os.listdir(work):
        if name != layer and os.path.isfile(os.path.join(work, name)):
            shutil.copy(os.path.join(work, name), fresh)

    out = os.path.join(work, "out.usdz")
    cwd = os.getcwd()
    os.chdir(fresh)
    try:
        if not UsdUtils.CreateNewARKitUsdzPackage(layer, out):
            raise SystemExit("USDZ packaging failed")
    finally:
        os.chdir(cwd)
    shutil.copyfile(out, path)
    print(f"{path}: joints {', '.join(b['name'] for b in added)} added")


if __name__ == "__main__":
    main()
