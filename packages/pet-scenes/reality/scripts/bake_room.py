#!/usr/bin/env python3
"""Bakes assets-source/Item_*.usdz into one Room.usdz for the app.

Each piece becomes a single mesh under its own name, with dense meshes decimated, low-poly ones left
as authored, and authored normals carried across. Colours move into a small palette texture shared
by two plain materials. Glossy and glowing surfaces keep materials of their own.

The room's simple shapes are baked here too, so nothing is generated on the phone while the room
loads. Their sizes must match the list in NookiDiorama, which a test checks. They carry a stand-in
material: the app gives them their own.

    pip install usd-core pyfqmr numpy scipy pillow
    bake_room.py
"""

import tempfile
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pyfqmr
from PIL import Image
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdUtils, Vt
from scipy.spatial import cKDTree

PACKAGE = Path(__file__).resolve().parent.parent
SOURCES = PACKAGE / "assets-source"
OUTPUT = PACKAGE / "Sources/PetSceneReality/Resources/Room.usdz"

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
KEEP_WHOLE = {"Item_monstera": {"Torus", "Cone", "Cylinder"}}
# The soil shares its height with the inside of the pot and flickers against it, so it sits higher.
LIFTS = {"Item_monstera": {"Cylinder": 0.006}}
NEIGHBOURS = 12
SAME_PLACE = 1e-4
PLAIN_ROUGHNESS = (0.8, 1.0)
EDGE_RADIUS = 0.004
BOXES = {
    "shell_floor": (1.3, 0.08, 1.3),
    "shell_wall_left": (0.06, 0.86, 1.3),
    "shell_wall_back": (1.36, 0.86, 0.06),
    "shell_skirting_left": (0.012, 0.09, 1.2),
    "shell_skirting_back": (1.2, 0.09, 0.012),
    "shell_wire": (0.76, 0.006, 0.006),
}
BOWL_DISH = ("shape_dish", 0.075, 0.04)
SPHERES = {"shape_treats": 0.066, "shape_note_mark": 0.022}
PALETTE_BLOCK = 8
PALETTE_COLUMNS = 8


@dataclass(frozen=True)
class Surface:
    diffuse: tuple
    roughness: float
    metallic: float
    emissive: tuple

    @property
    def is_plain(self):
        return not any(self.emissive) and self.roughness in PLAIN_ROUGHNESS and not self.metallic

    @property
    def material_name(self):
        if self.is_plain:
            return f"plain_{int(self.roughness * 100)}"
        return "special_" + "".join(f"{round(value * 255):02x}" for value in self.diffuse)


class Palette:
    """A grid of flat colours. Each block is wide enough that filtering never reaches a neighbour."""

    def __init__(self):
        self.colours = []

    def uv(self, diffuse):
        if diffuse not in self.colours:
            self.colours.append(diffuse)
        index = self.colours.index(diffuse)
        return (
            (index % PALETTE_COLUMNS + 0.5) / PALETTE_COLUMNS,
            1 - (index // PALETTE_COLUMNS + 0.5) / PALETTE_COLUMNS,
        )

    def save(self, path):
        side = PALETTE_BLOCK * PALETTE_COLUMNS
        pixels = np.zeros((side, side, 3), dtype=np.uint8)
        for index, colour in enumerate(self.colours):
            row, column = index // PALETTE_COLUMNS, index % PALETTE_COLUMNS
            pixels[
                row * PALETTE_BLOCK : (row + 1) * PALETTE_BLOCK,
                column * PALETTE_BLOCK : (column + 1) * PALETTE_BLOCK,
            ] = np.round(np.array([to_srgb(value) for value in colour]) * 255)
        Image.fromarray(pixels).save(path)


def to_srgb(value):
    return 12.92 * value if value <= 0.0031308 else 1.055 * value ** (1 / 2.4) - 0.055


def surface_of(material):
    shader = next(p for p in Usd.PrimRange(material.GetPrim()) if p.GetTypeName() == "Shader")
    inputs = {i.GetBaseName(): i.Get() for i in UsdShade.Shader(shader).GetInputs()}
    rounded = lambda colour: tuple(round(float(value), 5) for value in colour)
    return Surface(
        diffuse=rounded(inputs["diffuseColor"]),
        roughness=round(float(inputs.get("roughness", 0.5)), 3),
        metallic=float(inputs.get("metallic", 0)),
        emissive=rounded(inputs.get("emissiveColor", (0, 0, 0))),
    )


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


def source_corners(mesh, world, faces, corners):
    """World position and normal of every face corner of `mesh`."""
    points = np.array(mesh.GetPointsAttr().Get(), dtype=np.float64)
    normals = np.array(mesh.GetNormalsAttr().Get(), dtype=np.float64)
    places = (world @ np.c_[points, np.ones(len(points))].T).T[:, :3]
    turned = (np.linalg.inv(world[:3, :3]).T @ normals.T).T
    turned /= np.maximum(np.linalg.norm(turned, axis=1, keepdims=True), 1e-20)
    if mesh.GetNormalsInterpolation() == UsdGeom.Tokens.faceVarying:
        return places[faces].reshape(-1, 3), turned[corners].reshape(-1, 3)
    return places[faces].reshape(-1, 3), turned[faces].reshape(-1, 3)


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


def shared_vertices(points, normals, uvs):
    """One vertex per distinct position, normal and colour, with each corner's index into them."""
    keys = np.c_[np.round(points * 1e5), np.round(normals * 1e2), np.round(uvs * 1e3)]
    _, first, inverse = np.unique(
        keys.astype(np.int64), axis=0, return_index=True, return_inverse=True)
    return points[first], normals[first], uvs[first], inverse.reshape(-1)


def read_meshes(stage, name):
    """Each mesh of a piece in world space, with what is needed to decimate and shade it."""
    cache = UsdGeom.XformCache()
    meshes = []
    for prim in stage.Traverse():
        if not prim.IsA(UsdGeom.Mesh):
            continue
        mesh = UsdGeom.Mesh(prim)
        world = np.array(cache.GetLocalToWorldTransform(prim)).T
        world[1, 3] += LIFTS.get(name, {}).get(prim.GetName(), 0)
        local = np.array(mesh.GetPointsAttr().Get(), dtype=np.float64)
        points = (world @ np.c_[local, np.ones(len(local))].T).T[:, :3]
        material = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0]
        faces, corners = triangles(mesh)
        welded_points, welded_faces = weld(points, faces)
        meshes.append({
            "points": welded_points,
            "faces": welded_faces,
            "source": source_corners(mesh, world, faces, corners),
            "surface": surface_of(material),
            "whole": prim.GetName() in KEEP_WHOLE.get(name, ()),
        })
    return meshes


def bake_piece(meshes, budget, palette):
    sizes = [len(mesh["faces"]) for mesh in meshes]
    kept = sum(
        len(mesh["faces"]) for mesh in meshes if len(mesh["faces"]) < KEEP_BELOW or mesh["whole"])
    ratio = min(1, max(budget - kept, 0) / max(sum(sizes) - kept, 1))

    points, normals, uvs, subsets, surfaces, offset = [], [], [], defaultdict(list), {}, 0
    for mesh in sorted(meshes, key=lambda each: each["surface"].material_name):
        surface = mesh["surface"]
        reduced_points, reduced_faces = decimate(
            mesh["points"], mesh["faces"], 1 if mesh["whole"] else ratio)
        corners = reduced_points[reduced_faces].reshape(-1, 3)
        points.append(corners)
        normals.append(
            carried_normals(reduced_points, reduced_faces, *mesh["source"]).reshape(-1, 3))
        uv = palette.uv(surface.diffuse) if surface.is_plain else (0, 0)
        uvs.append(np.full((len(corners), 2), uv))
        subsets[surface.material_name].extend(range(offset, offset + len(reduced_faces)))
        surfaces[surface.material_name] = surface
        offset += len(reduced_faces)
    return (
        *shared_vertices(np.concatenate(points), np.concatenate(normals), np.concatenate(uvs)),
        subsets,
        surfaces,
        sum(sizes),
        offset,
    )


def bevelled_box(size, radius):
    """A box with softened edges in 44 triangles: flat faces keep their normals, and the strips
    between them blend across, which reads as a rounded edge at this size."""
    half = np.array(size) / 2
    inner = np.maximum(half - radius, 0)
    points, normals, numbers, faces = [], [], {}, []

    def vertex(axis, signs):
        key = (axis, *signs)
        if key not in numbers:
            position = np.array(signs) * inner
            position[axis] = signs[axis] * half[axis]
            normal = np.zeros(3)
            normal[axis] = signs[axis]
            numbers[key] = len(points)
            points.append(position)
            normals.append(normal)
        return numbers[key]

    def triangle(a, b, c):
        pa, pb, pc = points[a], points[b], points[c]
        outward = np.dot(np.cross(pb - pa, pc - pa), pa + pb + pc) > 0
        faces.append((a, b, c) if outward else (a, c, b))

    for axis in range(3):
        following, last = (axis + 1) % 3, (axis + 2) % 3
        for side in (-1, 1):
            def at(first, second, face):
                signs = [0, 0, 0]
                signs[axis], signs[following], signs[last] = side, first, second
                return vertex(face, tuple(signs))

            triangle(at(-1, -1, axis), at(1, -1, axis), at(1, 1, axis))
            triangle(at(-1, -1, axis), at(1, 1, axis), at(-1, 1, axis))
            for along in (-1, 1):
                a, b = at(along, -1, axis), at(along, 1, axis)
                c, d = at(along, -1, following), at(along, 1, following)
                triangle(a, b, d)
                triangle(a, d, c)
                if axis == 0:
                    for end in (-1, 1):
                        triangle(at(along, end, axis), at(along, end, following), at(along, end, last))
    return np.array(points), np.array(normals), np.array(faces)


def sphere(radius, around=16, down=10):
    points, faces = [], []
    for row in range(down + 1):
        polar = np.pi * row / down
        for column in range(around):
            turn = 2 * np.pi * column / around
            points.append((np.sin(polar) * np.cos(turn), np.cos(polar), np.sin(polar) * np.sin(turn)))
    for row in range(down):
        for column in range(around):
            a = row * around + column
            b = row * around + (column + 1) % around
            c, d = a + around, b + around
            faces += [(a, b, d), (a, d, c)]
    normals = np.array(points)
    return normals * radius, normals, np.array(faces)


def cylinder(radius, height, around=32):
    ring = [(np.cos(2 * np.pi * i / around), np.sin(2 * np.pi * i / around)) for i in range(around)]
    points, normals, faces = [], [], []
    for x, z in ring:
        for y in (-height / 2, height / 2):
            points.append((x * radius, y, z * radius))
            normals.append((x, 0, z))
    for i in range(around):
        a, b = 2 * i, 2 * ((i + 1) % around)
        faces += [(a, a + 1, b + 1), (a, b + 1, b)]
    for y, up in ((-height / 2, -1), (height / 2, 1)):
        centre = len(points)
        points.append((0, y, 0))
        normals.append((0, up, 0))
        for x, z in ring:
            points.append((x * radius, y, z * radius))
            normals.append((0, up, 0))
        for i in range(around):
            a, b = centre + 1 + i, centre + 1 + (i + 1) % around
            faces.append((centre, a, b) if up < 0 else (centre, b, a))
    return np.array(points), np.array(normals), np.array(faces)


def write_shape(stage, name, shape, materials):
    points, normals, faces = shape
    material = "plain_80"
    surface = Surface((0.5, 0.5, 0.5), 0.8, 0.0, (0, 0, 0))
    uvs = np.full((len(points), 2), 0.5)
    subsets = {material: list(range(len(faces)))}
    write_piece(stage, name, (points, normals, uvs, faces.reshape(-1), subsets, {material: surface}),
                materials)


def define_material(stage, name, surface):
    path = f"/Room/_materials/{name}"
    material = UsdShade.Material.Define(stage, path)
    shader = UsdShade.Shader.Define(stage, f"{path}/surface")
    shader.CreateIdAttr("UsdPreviewSurface")
    shader.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(surface.roughness)
    shader.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(surface.metallic)
    output = shader.CreateOutput("surface", Sdf.ValueTypeNames.Token)
    material.CreateSurfaceOutput().ConnectToSource(output)
    colour = shader.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f)
    if surface.is_plain:
        reader = UsdShade.Shader.Define(stage, f"{path}/uv")
        reader.CreateIdAttr("UsdPrimvarReader_float2")
        reader.CreateInput("varname", Sdf.ValueTypeNames.String).Set("st")
        texture = UsdShade.Shader.Define(stage, f"{path}/palette")
        texture.CreateIdAttr("UsdUVTexture")
        texture.CreateInput("file", Sdf.ValueTypeNames.Asset).Set(Sdf.AssetPath("palette.png"))
        texture.CreateInput("sourceColorSpace", Sdf.ValueTypeNames.Token).Set("sRGB")
        texture.CreateInput("wrapS", Sdf.ValueTypeNames.Token).Set("clamp")
        texture.CreateInput("wrapT", Sdf.ValueTypeNames.Token).Set("clamp")
        texture.CreateInput("st", Sdf.ValueTypeNames.Float2).ConnectToSource(
            reader.CreateOutput("result", Sdf.ValueTypeNames.Float2))
        colour.ConnectToSource(texture.CreateOutput("rgb", Sdf.ValueTypeNames.Float3))
    else:
        colour.Set(Gf.Vec3f(*surface.diffuse))
        if any(surface.emissive):
            shader.CreateInput("emissiveColor", Sdf.ValueTypeNames.Color3f).Set(
                Gf.Vec3f(*surface.emissive))
    return material


def write_piece(stage, name, baked, materials):
    points, normals, uvs, corners, subsets, surfaces, *_ = baked
    UsdGeom.Xform.Define(stage, f"/Room/{name}")
    mesh = UsdGeom.Mesh.Define(stage, f"/Room/{name}/piece")
    mesh.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(points.astype(np.float32)))
    mesh.CreateFaceVertexCountsAttr(Vt.IntArray([3] * (len(corners) // 3)))
    mesh.CreateFaceVertexIndicesAttr(Vt.IntArray(corners.tolist()))
    mesh.CreateNormalsAttr(Vt.Vec3fArray.FromNumpy(normals.astype(np.float32)))
    mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
    mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
    mesh.CreateDoubleSidedAttr(True)
    mesh.CreateExtentAttr(
        [Gf.Vec3f(*map(float, points.min(axis=0))), Gf.Vec3f(*map(float, points.max(axis=0)))])
    UsdGeom.PrimvarsAPI(mesh).CreatePrimvar(
        "st", Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.vertex
    ).Set(Vt.Vec2fArray.FromNumpy(uvs.astype(np.float32)))
    UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim())
    for material_name, faces in subsets.items():
        if material_name not in materials:
            materials[material_name] = define_material(stage, material_name, surfaces[material_name])
        subset = UsdShade.MaterialBindingAPI(mesh).CreateMaterialBindSubset(
            material_name, Vt.IntArray(faces), UsdGeom.Tokens.face)
        UsdShade.MaterialBindingAPI.Apply(subset.GetPrim()).Bind(materials[material_name])
    UsdGeom.Subset.SetFamilyType(
        UsdGeom.Imageable(mesh), UsdShade.Tokens.materialBind, UsdGeom.Tokens.partition)


def main():
    with tempfile.TemporaryDirectory() as folder:
        layer_path = Path(folder) / "Room.usdc"
        stage = Usd.Stage.CreateNew(str(layer_path))
        UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
        UsdGeom.SetStageMetersPerUnit(stage, 1)
        stage.SetDefaultPrim(UsdGeom.Xform.Define(stage, "/Room").GetPrim())
        UsdGeom.Scope.Define(stage, "/Room/_materials")
        palette, materials = Palette(), {}
        for name, budget in BUDGETS.items():
            source = Usd.Stage.Open(str(SOURCES / f"{name}.usdz"))
            if UsdGeom.GetStageUpAxis(source) != "Y" or UsdGeom.GetStageMetersPerUnit(source) != 1:
                raise ValueError(f"{name} is not Y-up in metres")
            baked = bake_piece(read_meshes(source, name), budget, palette)
            write_piece(stage, name, baked, materials)
            print(f"{name:16} {baked[-2]:7} -> {baked[-1]:6} tris, {len(baked[4])} parts")
        for name, size in BOXES.items():
            write_shape(stage, name, bevelled_box(size, EDGE_RADIUS), materials)
        dish, dish_radius, dish_height = BOWL_DISH
        write_shape(stage, dish, cylinder(dish_radius, dish_height), materials)
        for name, radius in SPHERES.items():
            write_shape(stage, name, sphere(radius), materials)
        palette.save(Path(folder) / "palette.png")
        stage.GetRootLayer().Save()
        UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(layer_path)), str(OUTPUT))
    print(f"{len(materials)} materials, {len(palette.colours)} colours, "
          f"{OUTPUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
