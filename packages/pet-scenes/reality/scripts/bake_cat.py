#!/usr/bin/env python3
"""Makes the cats the app ships.

Every cat comes from assets-source/cats/<model>/, holding Cat.usdz and clips.json. Each is
compiled to Resources/Cats/Cat_<model>.reality beside its clip table. A cat painted from a palette
also ships the palette as Cat_<model>_palette.png, which the app repaints for each coat. A palette
is a grid of flat swatches, so it is never resized: a resize would blur one swatch into the next.
A cat painted with a full texture instead keeps one texture per extra coat beside its source as
Cat_<model>_<coat>.jpg, shipped as it is.

Pass model names to bake only those. Needs macOS for realitytool.
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
CAT_SOURCES = ROOT / "assets-source" / "cats"
RESOURCES = ROOT / "Sources" / "PetSceneReality" / "Resources"
CATS = RESOURCES / "Cats"

# A compiled cat over this many bytes is a sign something came in unreduced. The detailed cats
# carry a 1024 px albedo and a normal map, and the kitten and fluffy one fur cards too, so they
# are allowed more; the hero ships four more clips than the others.
LARGEST_CAT = 2_500_000
LARGEST = {
    "detailed": 3_000_000,
    "detailedKitten": 3_400_000,
    "detailedFluffy": 3_600_000,
    "hero": 3_200_000,
}


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
    wanted = sys.argv[1:] or sorted(p.name for p in CAT_SOURCES.iterdir() if p.is_dir())
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary).resolve()
        for model in wanted:
            bake_cat(model, work)


if __name__ == "__main__":
    main()
