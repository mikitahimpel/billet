"""Binds a splat to a skeleton: per-splat bone weights from a rig spec in generate/rigs.

Each part (a leg, the head, the tail) claims the splats inside its half-spaces and ellipsoids, softly at their edges,
in the order the spec lists them; the bones without a part share what is left. Within a part or the remainder, a splat
leans toward the bones it lies closest to, so joints bend smoothly where two bones meet.

Writes two files beside the .ply that the web and the app both read:
  <name>.rig.json  the bones: name, parent, head (pivot) and tail, in skin order; the point between the eyes, and
                   where a second pose of the same cat is mounted on the first
  <name>.skin      4 bone indices then 4 weights per splat, uint8, in the .ply's splat order; weights sum to 255
"""

import json
from pathlib import Path

import numpy as np

# Below this, a bone is too close to call; keeps splats on a bone from dividing by zero.
CORE = 0.006


def segment_distance(p, a, b):
    ab = b - a
    t = np.clip((p - a) @ ab / max(ab @ ab, 1e-12), 0, 1)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)


def smoothstep(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def inside(p, shapes):
    """1 well inside every shape, 0 outside. A half-space keeps the side its normal points to, smooth across `soft`
    meters; an ellipsoid (`center`, `radii`) keeps its inside, smooth across `soft` times its radii."""
    m = np.ones(len(p))
    for shape in shapes:
        if 'center' in shape:
            d = np.linalg.norm((p - shape['center']) / shape['radii'], axis=1)
            m *= smoothstep(0.5 + (1 - d) / shape['soft'])
            continue
        n = np.asarray(shape['normal'], float)
        n /= np.linalg.norm(n)
        m *= smoothstep(0.5 + (p - shape['point']) @ n / shape['soft'])
    return m


def by_distance(p, bones):
    """Columns of weights over `bones` summing to 1, falling off with the fourth power of distance."""
    d = np.stack([segment_distance(p, np.asarray(b['head']), np.asarray(b['tail'])) for b in bones], 1)
    w = 1 / (d * d + CORE * CORE) ** 2
    return w / w.sum(1, keepdims=True)


def weights(p, rig):
    bones = rig['bones']
    w = np.zeros((len(p), len(bones)))
    left = np.ones(len(p))
    for part, planes in rig['parts'].items():
        idx = [i for i, b in enumerate(bones) if b.get('part') == part]
        share = inside(p, planes) * left
        w[:, idx] = share[:, None] * by_distance(p, [bones[i] for i in idx])
        left -= share
    rest = [i for i, b in enumerate(bones) if 'part' not in b]
    w[:, rest] = left[:, None] * by_distance(p, [bones[i] for i in rest])
    return w


def quantize(w):
    """Top four bones per splat as uint8 indices and weights summing to 255."""
    top = np.argsort(-w, 1)[:, :4]
    amount = np.take_along_axis(w, top, 1)
    amount /= amount.sum(1, keepdims=True)
    q = np.floor(amount * 255).astype(int)
    q[:, 0] += 255 - q.sum(1)
    return np.concatenate([top, q], 1).astype(np.uint8)


def bind(ply, data, spec):
    """Writes the sidecars of `ply`, whose splats are `data` (N x 14, positions first)."""
    rig = json.loads(Path(spec).read_text())
    skin = quantize(weights(data[:, :3].astype(np.float64), rig))
    ply = Path(ply)
    bones = [{k: b[k] for k in ('name', 'parent', 'head', 'tail') if k in b} for b in rig['bones']]
    sidecar = {'bones': bones, **{k: rig[k] for k in ('eyes', 'mount') if k in rig}}
    ply.with_suffix('.rig.json').write_text(json.dumps(sidecar, indent=1) + '\n', newline='\n')
    ply.with_suffix('.skin').write_bytes(skin.tobytes())
    used = np.bincount(skin[:, 0], minlength=len(bones))
    print(f'skinned {len(skin)} splats to {len(bones)} bones; main bone counts {dict(zip([b["name"] for b in bones], used.tolist()))}')
