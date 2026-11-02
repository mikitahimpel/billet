#!/usr/bin/env python3
"""Rebuilds the room's Item_*.usdz files as one decimated mesh per piece.

Each source mesh is decimated on its own, so small details survive, and keeps its authored normals,
which carry the soft shading. All of a piece's meshes are then baked into one mesh with a material
subset per colour. Colours are constant, so texture
coordinates and display colours are dropped. Materials are copied as they are.

    pip install usd-core pyfqmr numpy scipy
    optimize_furniture.py <folder of source usdz> <output folder>
"""

import sys
import tempfile
from collections import defaultdict
from pathlib import Path

import numpy as np
import pyfqmr
from scipy.spatial import cKDTree
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdUtils, Vt

# Triangles to keep in each piece, chosen for the size the piece has on screen.
BUDGETS = {
    "Item_armchair": 5000,
    "Item_bookcase": 8000,
    "Item_donutbed": 9000,
    "Item_lamp": 7000,
    "Item_lantern": 3500,
    "Item_monstera": 12000,
    "Item_mouse": 3000,
    "Item_print": 5240,
    "Item_rug": 12000,
    "Item_teatable": 5000,
    "Item_tower": 14000,
    "Item_yarn": 3000,
}
# A mesh this small is already what its author wanted. The triangles to lose are in the dense ones.
KEEP_BELOW = 1000
SMALLEST_RESULT = 250
# Meshes that sit too close to a neighbour to lose any shape: the rim pokes through the soil.
KEEP_WHOLE = {"Torus", "Cone", "Cylinder"}
# The soil shares its height with the inside of the pot and flickers against it, so it sits higher.
SOIL_LIFT = 0.006
NEIGHBOURS = 12
SAME_PLACE = 1e-4


def triangles(mesh):
    """Fan triangles as point indices, with the matching indices of each face corner."""
    counts = np.array(mesh.GetFaceVertexCountsAttr().Get())
    indices = np.array(mesh.GetFaceVertexIndicesAttr().Get())
    out, corners = [], []
    start = 0
    for count in counts:
        for i in range(1, count - 1):
            out.append((indices[start], indices[start + i], indices[start + i + 1]))
            corners.append((start, start + i, start + i + 1))
        start += count
    return np.array(out, dtype=np.int64), np.array(corners, dtype=np.int64)


def weld(points, faces):
    span = max(float(np.ptp(points, axis=0).max()), 1e-6)
    keys = np.round(points / (span * 1e-5)).astype(np.int64)
    _, first, inverse = np.unique(keys, axis=0, return_index=True, return_inverse=True)
    inverse = inverse.reshape(-1)
    welded = inverse[faces]
    keep = (welded[:, 0] != welded[:, 1]) & (welded[:, 1] != welded[:, 2]) & (
        welded[:, 2] != welded[:, 0])
    return points[first], welded[keep]


def decimate(points, faces, ratio):
    if ratio >= 1:
        return points, faces
    target = max(SMALLEST_RESULT, int(len(faces) * ratio))
    if len(faces) < KEEP_BELOW or target >= len(faces):
        return points, faces
    simplifier = pyfqmr.Simplify()
    simplifier.setMesh(points, faces)
    simplifier.simplify_mesh(
        target_count=target, aggressiveness=5, preserve_border=True, verbose=False)
    vertices, reduced, _ = simplifier.getMesh()
    return np.array(vertices, dtype=np.float64), np.array(reduced, dtype=np.int64)


def source_corners(mesh, world, faces_and_corners):
    """World position and normal of every corner of `mesh`, faces fan-triangulated."""
    points = np.array(mesh.GetPointsAttr().Get(), dtype=np.float64)
    normals = np.array(mesh.GetNormalsAttr().Get(), dtype=np.float64)
    places = (world @ np.c_[points, np.ones(len(points))].T).T[:, :3]
    turned = (np.linalg.inv(world[:3, :3]).T @ normals.T).T
    turned /= np.maximum(np.linalg.norm(turned, axis=1, keepdims=True), 1e-20)
    if mesh.GetNormalsInterpolation() == UsdGeom.Tokens.faceVarying:
        vertex, corner = faces_and_corners
        return places[vertex], turned[corner]
    vertex = faces_and_corners[0]
    return places[vertex], turned[vertex]


def carried_normals(points, faces, source_places, source_normals):
    """Normals per corner, blended from source corners by closeness and by facing the same way.

    A vertex that stayed where it was takes its source normal almost exactly; one the decimation
    moved takes a smooth mix, so curved surfaces do not turn into facets.
    """
    a, b, c = (points[faces[:, i]] for i in range(3))
    cross = np.cross(b - a, c - a)
    units = cross / np.maximum(np.linalg.norm(cross, axis=1, keepdims=True), 1e-20)
    tree = cKDTree(source_places)
    distances, nearest = tree.query(points, k=min(NEIGHBOURS, len(source_places)))
    distances = distances.reshape(len(points), -1)
    nearest = nearest.reshape(len(points), -1)
    span = float(np.ptp(source_places, axis=0).max())
    closeness = 1 / (distances**2 + (span * SAME_PLACE) ** 2)
    normals = np.zeros((len(faces), 3, 3))
    for corner in range(3):
        candidates = source_normals[nearest[faces[:, corner]]]
        agreement = np.einsum("ijk,ik->ij", candidates, units)
        weights = (np.clip(agreement, 0, None) ** 4 + 1e-6) * closeness[faces[:, corner]]
        total = (candidates * weights[..., None]).sum(axis=1)
        normals[:, corner] = total / np.maximum(np.linalg.norm(total, axis=1, keepdims=True), 1e-20)
    return normals


def shared_vertices(points, normals):
    """One vertex per distinct position and normal, with each corner's index into them."""
    keys = np.c_[np.round(points * 1e5), np.round(normals * 1e2)].astype(np.int64)
    _, first, inverse = np.unique(keys, axis=0, return_index=True, return_inverse=True)
    return points[first], normals[first], inverse.reshape(-1)


def read_groups(stage):
    cache = UsdGeom.XformCache()
    groups = defaultdict(list)
    for prim in stage.Traverse():
        if not prim.IsA(UsdGeom.Mesh):
            continue
        mesh = UsdGeom.Mesh(prim)
        world = np.array(cache.GetLocalToWorldTransform(prim)).T
        is_pot = stage.GetRootLayer().identifier.endswith("Item_monstera.usdz")
        if is_pot and prim.GetName() == "Cylinder":
            world[1, 3] += SOIL_LIFT
        local = np.array(mesh.GetPointsAttr().Get(), dtype=np.float64)
        points = (world @ np.c_[local, np.ones(len(local))].T).T[:, :3]
        material = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0].GetPath()
        faces, corners = triangles(mesh)
        welded_points, welded_faces = weld(points, faces)
        groups[material].append(
            (welded_points, welded_faces, source_corners(mesh, world, (faces, corners)),
             is_pot and prim.GetName() in KEEP_WHOLE))
    return groups


def optimise(source, output, budget):
    stage = Usd.Stage.Open(str(source))
    groups = read_groups(stage)
    sizes = [len(mesh[1]) for meshes in groups.values() for mesh in meshes]
    total = sum(sizes)
    kept = sum(
        len(mesh[1]) for meshes in groups.values() for mesh in meshes
        if len(mesh[1]) < KEEP_BELOW or mesh[3])
    ratio = min(1, max(budget - kept, 0) / max(total - kept, 1))

    all_points, all_normals, subsets, offset = [], [], [], 0
    for material, meshes in groups.items():
        indices = []
        for points, faces, (source_places, source_normals), whole in meshes:
            reduced_points, reduced_faces = decimate(points, faces, 1 if whole else ratio)
            all_points.append(reduced_points[reduced_faces].reshape(-1, 3))
            all_normals.append(
                carried_normals(
                    reduced_points, reduced_faces, source_places.reshape(-1, 3),
                    source_normals.reshape(-1, 3)).reshape(-1, 3))
            indices.extend(range(offset, offset + len(reduced_faces)))
            offset += len(reduced_faces)
        subsets.append((material, indices))
    points, normals, corners = shared_vertices(
        np.concatenate(all_points), np.concatenate(all_normals))

    with tempfile.TemporaryDirectory() as folder:
        layer_path = Path(folder) / f"{source.stem}.usdc"
        built = Usd.Stage.CreateNew(str(layer_path))
        UsdGeom.SetStageUpAxis(built, UsdGeom.GetStageUpAxis(stage))
        UsdGeom.SetStageMetersPerUnit(built, UsdGeom.GetStageMetersPerUnit(stage))
        root = UsdGeom.Xform.Define(built, "/root")
        built.SetDefaultPrim(root.GetPrim())
        flat = stage.Flatten()
        UsdGeom.Scope.Define(built, "/root/_materials")
        names = {}
        for material, _ in subsets:
            name = Sdf.Path(f"/root/_materials/{material.name}")
            names[material] = name
            Sdf.CopySpec(flat, material, built.GetRootLayer(), name)

        mesh = UsdGeom.Mesh.Define(built, "/root/piece")
        mesh.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(points.astype(np.float32)))
        mesh.CreateFaceVertexCountsAttr(Vt.IntArray([3] * offset))
        mesh.CreateFaceVertexIndicesAttr(Vt.IntArray(corners.tolist()))
        mesh.CreateNormalsAttr(Vt.Vec3fArray.FromNumpy(normals.astype(np.float32)))
        mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
        mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
        mesh.CreateDoubleSidedAttr(True)
        low, high = points.min(axis=0), points.max(axis=0)
        mesh.CreateExtentAttr([Gf.Vec3f(*map(float, low)), Gf.Vec3f(*map(float, high))])
        mesh.GetPrim().ApplyAPI(UsdShade.MaterialBindingAPI)
        for index, (material, faces) in enumerate(subsets):
            subset = UsdShade.MaterialBindingAPI(mesh).CreateMaterialBindSubset(
                f"part{index}", Vt.IntArray(faces), UsdGeom.Tokens.face)
            UsdShade.MaterialBindingAPI.Apply(subset.GetPrim()).Bind(
                UsdShade.Material(built.GetPrimAtPath(names[material])))
        UsdGeom.Subset.SetFamilyType(
            UsdGeom.Imageable(mesh), UsdShade.Tokens.materialBind, UsdGeom.Tokens.partition)
        built.GetRootLayer().Save()
        UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(layer_path)), str(output))
    return total, offset, len(subsets)


def main():
    source, output = Path(sys.argv[1]), Path(sys.argv[2])
    output.mkdir(parents=True, exist_ok=True)
    for name, budget in BUDGETS.items():
        total, kept, parts = optimise(source / f"{name}.usdz", output / f"{name}.usdz", budget)
        size = (output / f"{name}.usdz").stat().st_size // 1024
        print(f"{name:16} {total:7} -> {kept:6} tris, {parts} parts, {size} KB")


if __name__ == "__main__":
    main()
