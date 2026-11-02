#!/usr/bin/env python3
"""Makes the two cats the app ships from assets-source/Cat.usdz, which is kept whole.

Cat.reality is the one the app shows. Cat.usdz is a small stand-in, for a system that cannot open
the compiled file, so it can give up detail. Needs usd-core, and macOS for sips and realitytool.
"""

import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

from pxr import Sdf, UsdUtils

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets-source" / "Cat.usdz"
RESOURCES = ROOT / "Sources" / "PetSceneReality" / "Resources"

SHOWN = {"mochi_color.png": 768, "mochi_normal.png": 512}
STAND_IN = {"mochi_color.png": 256, "mochi_normal.png": 256}


def package(sizes: dict[str, int], work: Path, output: Path) -> None:
    """Writes the cat to `output` with its textures at `sizes`."""
    folder = work / output.stem
    with zipfile.ZipFile(SOURCE) as source:
        source.extractall(folder)
    for name, size in sizes.items():
        texture = str(folder / "textures" / name)
        subprocess.run(["sips", "-Z", str(size), texture], check=True, capture_output=True)
    made = UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(folder / "Cat.usdc")), str(output))
    if not made:
        raise SystemExit(f"could not package {output}")


def main() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary).resolve()
        assets = work / "Cat.rkassets"
        assets.mkdir()
        package(SHOWN, work, assets / "Cat.usdz")
        subprocess.run(
            [
                "xcrun", "realitytool", "compile", "--platform", "iphoneos",
                "--deployment-target", "18.0",
                "--output-reality", str(RESOURCES / "Cat.reality"), str(assets),
            ],
            check=True,
            capture_output=True,
        )
        package(STAND_IN, work, work / "stand-in.usdz")
        shutil.copy(work / "stand-in.usdz", RESOURCES / "Cat.usdz")


if __name__ == "__main__":
    main()
