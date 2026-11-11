"""One USDZ + one catalog JSON per prop, at room scale.

Usage: python -I pack_items.py <remeshed dir> <specs.json> <out dir> <scale> <id>=<name> ...
Mesh: metres * scale, y-up, origin at the base centre, front +Z, one 512 px JPEG texture (q88),
one material. Writes <out>/Item_<id>.usdz and <out>/Item_<id>.json.
"""
import json, math, sys
from pathlib import Path
from PIL import Image
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdUtils, Vt
sys.path.insert(0, str(Path(__file__).parent))
from pack_props import read_obj

CELL = 0.05
src, specs_p, out, scale = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), float(sys.argv[4])
specs = json.loads(specs_p.read_text()); out.mkdir(parents=True, exist_ok=True)
FLAT = {"rug", "throwblanket", "floorcushion-terracotta", "floorcushion-sage"}
SURFACE = {"desk", "wallshelf", "fishtank"}

def kind(name, mount):
    if mount == "wall" or name in FLAT: return "FLAT"
    return "SURFACE" if name in SURFACE else "SOLID"

for pair in sys.argv[5:]:
    iid, name = pair.split("=")
    verts, uvs, normals, faces = read_obj(src / f"{iid}.obj")
    stats = json.loads((src / f"{iid}.json").read_text())
    work = out / f"_{iid}"; work.mkdir(exist_ok=True)
    Image.open(src / f"{iid}.png").convert("RGB").save(work / "tex.jpg", quality=88)
    stage = Usd.Stage.CreateNew(str(work / f"Item_{iid}.usdc"))
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y); UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    root = UsdGeom.Xform.Define(stage, "/Item_" + iid.replace("-", "_")); stage.SetDefaultPrim(root.GetPrim())
    geom = UsdGeom.Mesh.Define(stage, f"{root.GetPath()}/mesh")
    pts, sts, nrm, idx = [], [], [], []
    for f in faces:
        for v, t, n in f:
            idx.append(len(pts)); pts.append(Gf.Vec3f(*[c * scale for c in verts[v]]))
            sts.append(Gf.Vec2f(*uvs[t])); nrm.append(Gf.Vec3f(*normals[n]))
    geom.CreatePointsAttr(Vt.Vec3fArray(pts)); geom.CreateFaceVertexCountsAttr(Vt.IntArray([3] * len(faces)))
    geom.CreateFaceVertexIndicesAttr(Vt.IntArray(idx)); geom.CreateNormalsAttr(Vt.Vec3fArray(nrm))
    geom.SetNormalsInterpolation(UsdGeom.Tokens.vertex); geom.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
    UsdGeom.PrimvarsAPI(geom).CreatePrimvar("st", Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.vertex).Set(Vt.Vec2fArray(sts))
    base = f"{root.GetPath()}/Mat"
    mat = UsdShade.Material.Define(stage, base)
    sh = UsdShade.Shader.Define(stage, base + "/s"); sh.CreateIdAttr("UsdPreviewSurface")
    sh.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(0.9); sh.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0.0)
    rd = UsdShade.Shader.Define(stage, base + "/st"); rd.CreateIdAttr("UsdPrimvarReader_float2")
    rd.CreateInput("varname", Sdf.ValueTypeNames.String).Set("st")
    tx = UsdShade.Shader.Define(stage, base + "/t"); tx.CreateIdAttr("UsdUVTexture")
    tx.CreateInput("file", Sdf.ValueTypeNames.Asset).Set("tex.jpg")
    tx.CreateInput("sourceColorSpace", Sdf.ValueTypeNames.Token).Set("sRGB")
    tx.CreateInput("st", Sdf.ValueTypeNames.Float2).ConnectToSource(rd.ConnectableAPI(), "result")
    tx.CreateOutput("rgb", Sdf.ValueTypeNames.Float3)
    sh.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).ConnectToSource(tx.ConnectableAPI(), "rgb")
    mat.CreateSurfaceOutput().ConnectToSource(sh.ConnectableAPI(), "surface")
    UsdShade.MaterialBindingAPI.Apply(geom.GetPrim()).Bind(mat)
    stage.GetRootLayer().Save()
    usdz = out / f"Item_{iid}.usdz"
    UsdUtils.CreateNewARKitUsdzPackage(Sdf.AssetPath(str(work / f"Item_{iid}.usdc")), str(usdz))
    for p in work.iterdir(): p.unlink()
    work.rmdir()
    m = stats["metres"]; w, d, h = (m["width"] * scale, m["depth"] * scale, m["height"] * scale)
    sp = specs[name]; fit = sp["fit"]; size = (max(w, d) if fit == "width" else h)
    cat = {"id": iid, "name": sp["title"], "kind": kind(name, sp["mount"]), "width_m": round(w, 3), "depth_m": round(d, 3),
           "height_m": round(h, 3), "footprint_cells": [math.ceil(w / CELL - 1e-6), math.ceil(d / CELL - 1e-6)],
           "mount": sp["mount"], "fit": fit, "size_m": round(size, 3), "anchors": [], "tris": len(faces),
           "affordance": sp.get("affordance"), "usdz_kb": usdz.stat().st_size // 1024}
    (out / f"Item_{iid}.json").write_text(json.dumps(cat, indent=1))
    print("PACKED", iid, cat["kind"], cat["footprint_cells"], round(h, 2), len(faces), cat["usdz_kb"], "KB", flush=True)
