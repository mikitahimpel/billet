"""Mochi in other coats: per coat, a new color for every splat, written as <name>.coats beside the app's splat.

Only colors change, so the skin and rig stay valid. Fur is every near-grey splat (the collar, nose, inner ears and
eyes are colored and stay); a coat maps the fur's lightness (stripes, base, white chest, baked shading) through a
ramp, so both poses wear the same coat.

The file is one ASCII line `coats <splats> <name,name,...>` and then, coat after coat, three sRGB bytes per splat in
the splat file's order.

    python coats.py apps/ios/Nooki/Resources/Mochi.ply rigs/cat-sit.json
    python coats.py apps/ios/Nooki/Resources/MochiStanding.ply rigs/cat-standing.json --preview out/coats
"""
import argparse
import json
from pathlib import Path

import numpy as np

from make_splat import SH_C0, load_array, write_ply

COATS = ['ginger', 'cream', 'black', 'tuxedo', 'white']


def smooth(x, a, b):
    x = np.clip((x - a) / (b - a), 0, 1)
    return x * x * (3 - 2 * x)


def ramp(*stops):
    """Lightness 0..1 to rgb through linear stops (L, (r, g, b))."""
    ls = np.array([s[0] for s in stops])
    cs = np.array([s[1] for s in stops], float)
    return lambda L: np.stack([np.interp(L, ls, cs[:, k]) for k in range(3)], -1)


# Mochi's fur lightness runs from her stripes (about 0.22) through her base (0.6) to her white chest (0.9).
GINGER = ramp((0.15, (0.42, 0.17, 0.05)), (0.35, (0.70, 0.36, 0.13)), (0.6, (0.88, 0.55, 0.25)),
              (0.8, (0.95, 0.75, 0.50)), (0.92, (0.98, 0.94, 0.86)))
CREAM = ramp((0.15, (0.66, 0.52, 0.38)), (0.45, (0.85, 0.72, 0.55)), (0.7, (0.94, 0.85, 0.70)),
             (0.92, (0.99, 0.96, 0.91)))
BLACK = ramp((0.15, (0.025, 0.025, 0.03)), (0.6, (0.075, 0.07, 0.075)), (0.92, (0.17, 0.16, 0.16)))
TUXEDO = ramp((0.15, (0.025, 0.025, 0.03)), (0.6, (0.075, 0.07, 0.075)), (0.78, (0.12, 0.115, 0.115)),
              (0.86, (0.85, 0.84, 0.82)), (0.95, (0.98, 0.98, 0.97)))
WHITE = ramp((0.15, (0.84, 0.83, 0.81)), (0.6, (0.92, 0.91, 0.89)), (0.92, (0.99, 0.99, 0.98)))
# Her dark brown eyes vanish in a dark coat: a black cat's are amber, pupil and highlight kept.
AMBER = ramp((0.06, (0.04, 0.03, 0.02)), (0.16, (0.50, 0.33, 0.04)), (0.35, (0.88, 0.66, 0.16)),
             (0.75, (0.96, 0.90, 0.70)), (1, (1, 1, 1)))


def coats(data, rig):
    p = data[:, :3].astype(float)
    rgb = np.clip(0.5 + SH_C0 * data[:, 11:14], 0, 1)
    L = rgb.mean(1)
    chroma = rgb.max(1) - rgb.min(1)
    eyes = np.array(rig['eyes'])
    eye = np.zeros(len(p))
    for dx in (-0.025, 0.025):
        eye = np.maximum(eye, 1 - smooth(np.linalg.norm(p - eyes - [dx, 0, 0], axis=1), 0.008, 0.013))
    fur = (1 - smooth(chroma, 0.09, 0.17)) * (1 - eye)
    # Solid pale coats have no tabby stripes: hers are pulled most of the way to her base lightness.
    flat = 0.6 + (L - 0.6) * 0.35

    ramps = {'ginger': GINGER, 'cream': CREAM, 'black': BLACK, 'tuxedo': TUXEDO, 'white': WHITE}
    out = {}
    for name in COATS:
        new = ramps[name](flat if name == 'white' else L)
        color = rgb * (1 - fur[:, None]) + new * fur[:, None]
        if name in ('black', 'tuxedo'):
            color = color * (1 - eye[:, None]) + AMBER(L) * eye[:, None]
        out[name] = np.clip(color, 0, 1)
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('ply', type=Path)
    parser.add_argument('rig', type=Path, help='the rig spec the splat was bound with (rigs/*.json)')
    parser.add_argument('--preview', type=Path, help='also write <dir>/<coat>-<ply name>.ply to look at')
    args = parser.parse_args()

    data = load_array(args.ply)
    colors = coats(data, json.loads(args.rig.read_text()))
    target = args.ply.with_suffix('.coats')
    with open(target, 'wb') as f:
        f.write(f'coats {len(data)} {",".join(colors)}\n'.encode('ascii'))
        for color in colors.values():
            f.write(np.round(color * 255).astype(np.uint8).tobytes())
    print(f'wrote {target}: {len(colors)} coats of {len(data)} splats')
    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)
        for name, color in colors.items():
            recolored = data.copy()
            recolored[:, 11:14] = ((np.round(color * 255) / 255 - 0.5) / SH_C0).astype('<f4')
            write_ply(args.preview / f'{name}-{args.ply.stem}.ply', recolored)


if __name__ == '__main__':
    main()
