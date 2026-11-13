#!/usr/bin/env python3
"""Writes a coat's colours for the app: Nooki/Resources/Coats/<pose>-<coat>.fdh, f_dc_0..2 of every splat as half floats.

billet-gpu's coat PLYs differ from the original only in f_dc_0..2, so the app ships just those, rounded to half floats
(within 0.002, under a fifth of an 8-bit colour level), and lays them over the original PLY when it loads (CatCoat.dress).
This checks that claim and prints the sha256 of the PLY the app rebuilds, for CatCoatTests.

    python3 scripts/coats/coat-colours.py Nooki/Resources/Mochi.ply ~/billet-gpu/out/coats/Mochi-ginger.ply \
        Nooki/Resources/Coats/Mochi-ginger.fdh
"""
import hashlib
import sys

import numpy as np

FLOATS = 14  # x y z scale_0..2 rot_0..3 opacity f_dc_0..2


def split(path):
    data = open(path, "rb").read()
    end = data.index(b"end_header\n") + len(b"end_header\n")
    return data[:end], data[end:]


original, coat, out = sys.argv[1:4]
header, body = split(original)
coat_header, coat_body = split(coat)
assert header == coat_header and len(body) == len(coat_body), "the coat is not a recolour of this PLY"
a = np.frombuffer(body, "<f4").reshape(-1, FLOATS)
b = np.frombuffer(coat_body, "<f4").reshape(-1, FLOATS)
assert (a[:, :11].view("<u4") == b[:, :11].view("<u4")).all(), "more than f_dc differs"
colours = np.ascontiguousarray(b[:, 11:].astype("<f2"))
assert np.isfinite(colours).all() and np.abs(colours.astype("<f4") - b[:, 11:]).max() < 0.002, "a colour does not fit a half float"
rebuilt = a.copy()
rebuilt[:, 11:] = colours.astype("<f4")
open(out, "wb").write(colours.tobytes())
print(f"{out}: {len(colours)} splats, sha256 of the rebuilt PLY {hashlib.sha256(header + rebuilt.tobytes()).hexdigest()}")
