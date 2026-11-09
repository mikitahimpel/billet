"""Writes K variants of one program to look through: the armchair's colourways × cushions × legs, each a USDZ and a
thumbnail, plus a fragment listing them. The variants the app ships are chosen by hand in armchair-colourways.json.

Run (same interpreter as build.py):
  python tools/sand3d/sweep.py <out_dir> [--k K] [--samples N] [--no-thumbs]

Variants are taken in a fixed order that changes the colour first, so the first K are the most distinct.
"""

import argparse
import itertools
import json
import os

import billet_style as st
from armchair import LEG_HEIGHT, armchair
from build import run

CUSHIONS = ("plump", "tufted", "flat")


def variants():
    for legs, cushion, fabric in itertools.product(LEG_HEIGHT, CUSHIONS, st.FABRICS):
        yield f"armchair_{fabric}_{cushion}_{legs}", (fabric, cushion, legs)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir")
    ap.add_argument("--k", type=int, default=6)
    ap.add_argument("--samples", type=int, default=16)
    ap.add_argument("--no-thumbs", action="store_true")
    a = ap.parse_args()
    st.tessellate()
    chosen = list(itertools.islice(variants(), a.k))
    items = {name: (lambda args=args: armchair(*args)) for name, args in chosen}
    run(items, a.out_dir, not a.no_thumbs, a.samples)
    catalog = [{"id": name.replace("_", "-"), "model": f"Item_{name}", "fabric": f, "cushion": c, "legs": l,
                "fit": "width", "size": 0.4} for name, (f, c, l) in chosen]
    with open(os.path.join(a.out_dir, "variants.json"), "w") as f:
        json.dump(catalog, f, indent=2)
    print(f"{len(chosen)} of {len(list(variants()))} possible variants written")


if __name__ == "__main__":
    main()
