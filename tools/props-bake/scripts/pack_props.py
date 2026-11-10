"""Packs the remeshed props into what the app loads: one shared colour atlas and one USDZ.

Each prop's 512 px bake goes into its own cell of a 4 x 4 atlas page (2048 px, 16 cells), its UVs
moved into that cell; props past 16 start another page. Every prop is a prim
`/IdolProps/Idol_<name>` holding one mesh, bound to its page's one material, so props on a page
share it. Metres, y-up, pivot at the base centre.

Usage: python -I pack_props.py <remeshed dir> <out dir> <name> [<name> ...]
Writes <out>/IdolProps.usdz, <out>/atlas<page>.png and <out>/props.json (per prop: tris, metres).
"""

import json
import sys
from pathlib import Path

from PIL import Image
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdUtils, Vt

CELL, GRID = 512, 4


def read_obj(path):
    verts, uvs, normals, faces = [], [], [], []
    for line in path.read_text().splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "v":
            verts.append(tuple(map(float, parts[1:4])))
        elif parts[0] == "vt":
            uvs.append(tuple(map(float, parts[1:3])))
        elif parts[0] == "vn":
            normals.append(tuple(map(float, parts[1:4])))
        elif parts[0] == "f":
            corners = [tuple(int(i) - 1 for i in c.split("/")) for c in parts[1:]]
            for k in range(1, len(corners) - 1):
                faces.append((corners[0], corners[k], corners[k + 1]))
    return verts, uvs, normals, faces


def page_material(stage, page):
    """The one material for every prop on atlas page `page`: its baked colour, matte."""
    base = f"/IdolProps/Atlas{page}"
    mat = UsdShade.Material.Define(stage, base)
    shader = UsdShade.Shader.Define(stage, f"{base}/surface")
    shader.CreateIdAttr("UsdPreviewSurface")
    shader.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(0.9)
    shader.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0.0)
    reader = UsdShade.Shader.Define(stage, f"{base}/st")
    reader.CreateIdAttr("UsdPrimvarReader_float2")
    reader.CreateInput("varname", Sdf.ValueTypeNames.String).Set("st")
    tex = UsdShade.Shader.Define(stage, f"{base}/texture")
    tex.CreateIdAttr("UsdUVTexture")
    tex.CreateInput("file", Sdf.ValueTypeNames.Asset).Set(f"atlas{page}.png")
    tex.CreateInput("sourceColorSpace", Sdf.ValueTypeNames.Token).Set("sRGB")
    tex.CreateInput("st", Sdf.ValueTypeNames.Float2).ConnectToSource(reader.ConnectableAPI(), "result")
    tex.CreateOutput("rgb", Sdf.ValueTypeNames.Float3)
    shader.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).ConnectToSource(tex.ConnectableAPI(), "rgb")
    mat.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(), "surface")
    return mat


def main():
    src, out, names = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3:]
    out.mkdir(parents=True, exist_ok=True)
    stage_path = out / "IdolProps.usdc"
    stage = Usd.Stage.CreateNew(str(stage_path))
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    root = UsdGeom.Xform.Define(stage, "/IdolProps")
    stage.SetDefaultPrim(root.GetPrim())

    report = {}
    atlases, materials = [], []
    for index, name in enumerate(names):
        page, cell = divmod(index, GRID * GRID)
        col, row = cell % GRID, cell // GRID
        if page == len(atlases):
            atlases.append(Image.new("RGB", (CELL * GRID, CELL * GRID), (200, 170, 130)))
            materials.append(page_material(stage, page))
        atlas, mat = atlases[page], materials[page]
        atlas.paste(Image.open(src / f"{name}.png").convert("RGB").resize((CELL, CELL)), (col * CELL, row * CELL))
        verts, uvs, normals, faces = read_obj(src / f"{name}.obj")
        # One vertex per face corner: OBJ indexes position, uv and normal separately.
        points, sts, norms, indices = [], [], [], []
        for face in faces:
            for v, t, n in face:
                u, w = uvs[t]
                indices.append(len(points))
                points.append(Gf.Vec3f(*verts[v]))
                # USD's v runs up from the bottom; the atlas row 0 is the top.
                sts.append(Gf.Vec2f((col + u) / GRID, (GRID - 1 - row + w) / GRID))
                norms.append(Gf.Vec3f(*normals[n]))
        prim = UsdGeom.Xform.Define(stage, f"/IdolProps/Idol_{name}")
        geom = UsdGeom.Mesh.Define(stage, f"/IdolProps/Idol_{name}/mesh")
        geom.CreatePointsAttr(Vt.Vec3fArray(points))
        geom.CreateFaceVertexCountsAttr(Vt.IntArray([3] * len(faces)))
        geom.CreateFaceVertexIndicesAttr(Vt.IntArray(indices))
        geom.CreateNormalsAttr(Vt.Vec3fArray(norms))
        geom.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
        geom.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
        st = UsdGeom.PrimvarsAPI(geom).CreatePrimvar("st", Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.vertex)
        st.Set(Vt.Vec2fArray(sts))
        UsdShade.MaterialBindingAPI.Apply(geom.GetPrim()).Bind(mat)
        stats = json.loads((src / f"{name}.json").read_text())
        report[name] = {"tris": len(faces), "metres": stats["metres"], "page": page, "cell": [col, row],
                        "manifold": stats["manifold"]}
        print("PACKED", name, len(faces), "tris", stats["metres"], flush=True)

    for page, atlas in enumerate(atlases):
        atlas.save(out / f"atlas{page}.png", optimize=True)
    stage.GetRootLayer().Save()
    UsdUtils.CreateNewARKitUsdzPackage(Sdf.AssetPath(str(stage_path)), str(out / "IdolProps.usdz"))
    stage_path.unlink()
    (out / "props.json").write_text(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
