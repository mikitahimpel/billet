#!/usr/bin/env python3
"""Makes the cats the app ships.

Mochi comes from assets-source/Cat.usdz, which is kept whole: Cat.reality is the one the app shows,
and Cat.usdz is a small stand-in for a system that cannot open the compiled file, so it can give up
detail. Mochi needs usd-core.

Every other cat comes from assets-source/cats/<model>/, holding Cat.usdz and clips.json. Each is
compiled to Resources/Cats/Cat_<model>.reality beside its clip table. A cat painted from a palette
also ships the palette as Cat_<model>_palette.png, which the app repaints for each coat. A palette
is a grid of flat swatches, so it is never resized: a resize would blur one swatch into the next.
A cat painted with a full texture instead keeps one texture per extra coat beside its source as
Cat_<model>_<coat>.jpg, shipped as it is.

Pass model names to bake only those, or `mochi`. Needs macOS for sips and realitytool.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets-source" / "Cat.usdz"
CAT_SOURCES = ROOT / "assets-source" / "cats"
RESOURCES = ROOT / "Sources" / "PetSceneReality" / "Resources"
CATS = RESOURCES / "Cats"

SHOWN = {"mochi_color.png": 768, "mochi_normal.png": 512}
STAND_IN = {"mochi_color.png": 256, "mochi_normal.png": 256}

# A compiled cat over this many bytes is a sign something came in unreduced. The detailed cats
# carry a 1024 px albedo and a normal map, and the kitten and fluffy one fur cards too, so they
# are allowed more.
LARGEST_CAT = 2_500_000
LARGEST = {"detailed": 3_000_000, "detailedKitten": 3_400_000, "detailedFluffy": 3_600_000}


def package(sizes: dict[str, int], work: Path, output: Path) -> None:
    """Writes Mochi to `output` with its textures at `sizes`."""
    from pxr import Sdf, UsdUtils

    folder = work / output.stem
    with zipfile.ZipFile(SOURCE) as source:
        source.extractall(folder)
    for name, size in sizes.items():
        texture = str(folder / "textures" / name)
        subprocess.run(["sips", "-Z", str(size), texture], check=True, capture_output=True)
    made = UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(folder / "Cat.usdc")), str(output))
    if not made:
        raise SystemExit(f"could not package {output}")


def compile_reality(assets: Path, output: Path) -> None:
    subprocess.run(
        [
            "xcrun", "realitytool", "compile", "--platform", "iphoneos",
            "--deployment-target", "18.0",
            "--output-reality", str(output), str(assets),
        ],
        check=True,
        capture_output=True,
    )


def bake_mochi(work: Path) -> None:
    assets = work / "Cat.rkassets"
    assets.mkdir()
    package(SHOWN, work, assets / "Cat.usdz")
    compile_reality(assets, RESOURCES / "Cat.reality")
    package(STAND_IN, work, work / "stand-in.usdz")
    shutil.copy(work / "stand-in.usdz", RESOURCES / "Cat.usdz")


def palette_in(usdz: Path) -> bytes | None:
    """The palette the model is painted from, if it has one."""
    with zipfile.ZipFile(usdz) as package:
        names = [n for n in package.namelist() if n.endswith("_palette.png")]
        return package.read(names[0]) if names else None


def bake_cat(model: str, work: Path) -> None:
    source = CAT_SOURCES / model
    usdz = source / "Cat.usdz"
    table = json.loads((source / "clips.json").read_text())
    for name in ("idle", "sit", "sleep"):
        if name not in table:
            raise SystemExit(f"{model}: clips.json has no {name}")
    name = f"Cat_{model}"
    assets = work / f"{name}.rkassets"
    assets.mkdir()
    shutil.copy(usdz, assets / f"{name}.usdz")
    CATS.mkdir(exist_ok=True)
    output = CATS / f"{name}.reality"
    compile_reality(assets, output)
    clips = {
        clip: {key: value for key, value in range_.items() if key in ("trimStart", "trimEnd", "loops", "base")}
        for clip, range_ in table.items()
    }
    (CATS / f"{name}.clips.json").write_text(json.dumps(clips, indent=1, sort_keys=True) + "\n")
    palette = palette_in(usdz)
    if palette is not None:
        (CATS / f"{name}_palette.png").write_bytes(palette)
    coats = sorted(source.glob(f"{name}_*.jpg"))
    for coat in coats:
        shutil.copy(coat, CATS / coat.name)
    size = output.stat().st_size
    extras = (", palette" if palette else "") + "".join(f", {c.stem.removeprefix(name + '_')}" for c in coats)
    print(f"{model}: {size / 1e6:.2f} MB{extras}")
    largest = LARGEST.get(model, LARGEST_CAT)
    if size > largest:
        raise SystemExit(f"{model}: {size} bytes is over {largest}")


def main() -> None:
    wanted = sys.argv[1:] or ["mochi", *sorted(p.name for p in CAT_SOURCES.iterdir() if p.is_dir())]
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary).resolve()
        for model in wanted:
            if model == "mochi":
                bake_mochi(work)
            else:
                bake_cat(model, work)


if __name__ == "__main__":
    main()
