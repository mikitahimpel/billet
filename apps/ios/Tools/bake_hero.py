"""Renders the hero Mochi (the splash and the welcome) from the seated splat, coat by coat, with numpy.

Run (scripts/hero/bake-hero.sh does this for every coat):
  python3 Tools/bake_hero.py <out dir> --coat grey|ginger|... [--width 1080]

Writes `Hero-<coat>.webp`, the whole cat at rest, and patches the app lays over it: `HeroBlink<n>-<coat>.webp` (both
lids at 0.5 and shut) and `HeroEar<n>-<coat>.webp` (an ear flicked out half and fully), each cut to the rectangle
outside which nothing differs from rest, so a patch replaces its rectangle of the rest image without a seam. The
rectangles, as fractions of the image, are printed for `HeroArt.swift`.

The splat is drawn as the app's GaussianSplatResource draws it: sigmoid opacity, colour 0.5 + SH_C0 * f_dc, Gaussians
sorted back to front; bones move it as `CatRig.update` does (lids swing 0.7 and 0.42 rad about the upper lid's head, an
ear flicks about z, 0.45 rad at the top of a twitch), blended linearly by the `.skin` weights.
"""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "Nooki/Resources"
SH_C0 = 0.28209479
LID_SWING = (0.7, 0.42)
EAR_FLICK = 0.45
# Framing: the camera sits in front of her (her face looks toward -Z), a little above her eyes, and looks down at
# her middle; she fills `FILL` of the image's height.
EYE = np.array([0.0, 0.2, -1.1])
TARGET = np.array([0.0, 0.135, 0.0])
FILL = 0.9


def read_ply(path):
    data = path.read_bytes()
    end = data.index(b"end_header\n") + len(b"end_header\n")
    count = int(next(line for line in data[:end].decode().splitlines() if line.startswith("element vertex")).split()[2])
    return np.frombuffer(data[end:], "<f4").reshape(count, 14).astype(np.float64)


def quat_matrix(q):
    w, x, y, z = (q / np.linalg.norm(q, axis=1, keepdims=True)).T
    return np.stack([
        np.stack([1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)], -1),
        np.stack([2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)], -1),
        np.stack([2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)], -1),
    ], 1)


def axis_rotation(axis, angle):
    c, s = np.cos(angle), np.sin(angle)
    return {
        "x": np.array([[1, 0, 0], [0, c, -s], [0, s, c]]),
        "y": np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]]),
        "z": np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]]),
    }[axis]


def bone_poses(rig, lids=0.0, ear=0.0):
    """Each bone's rotation and translation in model space; only the lids and the left ear leave rest."""
    names = [b["name"] for b in rig["bones"]]
    heads = {b["name"]: np.array(b["head"]) for b in rig["bones"]}
    poses = [(np.eye(3), np.zeros(3)) for _ in names]

    def about(name, pivot, rotation):
        poses[names.index(name)] = (rotation, pivot - rotation @ pivot)

    for side in ("Left", "Right"):
        hinge = heads[f"lid{side}"]
        about(f"lid{side}", hinge, axis_rotation("x", -LID_SWING[0] * lids))
        about(f"lid{side}Low", hinge, axis_rotation("x", LID_SWING[1] * lids))
    about("earLeft", heads["earLeft"], axis_rotation("z", -ear))
    return poses


def posed(splats, skin, poses):
    rotations = np.stack([p[0] for p in poses])
    translations = np.stack([p[1] for p in poses])
    index = skin[:, :4].astype(int)
    weight = skin[:, 4:].astype(np.float64) / 255
    blend = np.einsum("nk,nkij->nij", weight, rotations[index])
    shift = np.einsum("nk,nki->ni", weight, translations[index])
    position = np.einsum("nij,nj->ni", blend, splats[:, :3]) + shift
    return position, blend


def camera(width, height):
    forward = TARGET - EYE
    forward /= np.linalg.norm(forward)
    right = np.cross(forward, np.array([0.0, 1.0, 0.0]))
    right /= np.linalg.norm(right)
    # Image rows grow downward.
    down = np.cross(forward, right)
    view = np.stack([right, down, forward])
    depth = np.linalg.norm(TARGET - EYE)
    focal = FILL * height / (0.3 / depth)
    return view, focal


def render(splats, colour, skin, rig, width, height, lids=0.0, ear=0.0):
    position, blend = posed(splats, skin, bone_poses(rig, lids, ear))
    view, focal = camera(width, height)
    p = (position - EYE) @ view.T
    z = p[:, 2]
    u = focal * p[:, 0] / z + width / 2
    v = focal * p[:, 1] / z + height / 2

    scale = np.exp(splats[:, 3:6])
    rotation = blend @ quat_matrix(splats[:, 6:10])
    m = rotation * scale[:, None, :]
    world = m @ m.transpose(0, 2, 1)
    camera_cov = view @ world @ view.T
    jac = np.zeros((len(z), 2, 3))
    jac[:, 0, 0] = focal / z
    jac[:, 1, 1] = focal / z
    jac[:, 0, 2] = -focal * p[:, 0] / z**2
    jac[:, 1, 2] = -focal * p[:, 1] / z**2
    cov = jac @ camera_cov @ jac.transpose(0, 2, 1)
    cov[:, 0, 0] += 0.3
    cov[:, 1, 1] += 0.3
    a, b, c = cov[:, 0, 0], cov[:, 0, 1], cov[:, 1, 1]
    det = a * c - b * b
    inv = np.stack([c / det, -b / det, a / det], 1)
    radius = np.ceil(3 * np.sqrt(np.maximum(a, c)))
    opacity = 1 / (1 + np.exp(-splats[:, 10]))

    rgb = np.zeros((height, width, 3))
    alpha = np.zeros((height, width))
    # Back to front, each over what is behind it; premultiplied.
    for i in np.argsort(-z):
        if opacity[i] < 1 / 255 or z[i] <= 0:
            continue
        x0, x1 = int(max(u[i] - radius[i], 0)), int(min(u[i] + radius[i] + 1, width))
        y0, y1 = int(max(v[i] - radius[i], 0)), int(min(v[i] + radius[i] + 1, height))
        if x0 >= x1 or y0 >= y1:
            continue
        dx = np.arange(x0, x1) + 0.5 - u[i]
        dy = (np.arange(y0, y1) + 0.5 - v[i])[:, None]
        power = -0.5 * (inv[i, 0] * dx * dx + 2 * inv[i, 1] * dx * dy + inv[i, 2] * dy * dy)
        a_i = np.minimum(opacity[i] * np.exp(power), 0.99)
        a_i[a_i < 1 / 255] = 0
        keep = 1 - a_i
        rgb[y0:y1, x0:x1] = rgb[y0:y1, x0:x1] * keep[..., None] + a_i[..., None] * colour[i]
        alpha[y0:y1, x0:x1] = alpha[y0:y1, x0:x1] * keep + a_i
    straight = np.where(alpha[..., None] > 0, rgb / np.maximum(alpha[..., None], 1e-6), 0)
    return np.dstack([np.clip(straight, 0, 1), np.clip(alpha, 0, 1)])


COATS = ["grey", "ginger", "cream", "tuxedo", "black", "calico"]
POSES = {"Blink": [dict(lids=0.5), dict(lids=1.0)], "Ear": [dict(ear=EAR_FLICK / 2), dict(ear=EAR_FLICK)]}


def to_bytes(image):
    return (image * 255 + 0.5).astype(np.uint8)


def changed_box(pairs, pad=4):
    """The smallest rectangle, padded, outside which every frame equals its rest image, as whole pixels."""
    height, width = pairs[0][0].shape[:2]
    moved = np.zeros((height, width), bool)
    for rest, frame in pairs:
        moved |= (rest != frame).any(-1)
    rows, columns = np.nonzero(moved)
    return (max(columns.min() - pad, 0), max(rows.min() - pad, 0),
            min(columns.max() + 1 + pad, width), min(rows.max() + 1 + pad, height))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("out")
    parser.add_argument("--coats", nargs="+", default=COATS)
    parser.add_argument("--width", type=int, default=1080)
    args = parser.parse_args()
    width, height = args.width, args.width * 4 // 3
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    original = read_ply(RES / "Mochi.ply")
    skin = np.frombuffer((RES / "Mochi.skin").read_bytes(), np.uint8).reshape(-1, 8)
    rig = json.loads((RES / "Mochi.rig.json").read_text())
    rests, frames = {}, {}
    for coat in args.coats:
        splats = original.copy()
        if coat != "grey":
            splats[:, 11:14] = np.frombuffer((RES / f"Coats/Mochi-{coat}.fdc").read_bytes(), "<f4").reshape(-1, 3)
        colour = np.clip(0.5 + SH_C0 * splats[:, 11:14], 0, 1)
        rests[coat] = to_bytes(render(splats, colour, skin, rig, width, height))
        for kind, poses in POSES.items():
            frames[coat, kind] = [to_bytes(render(splats, colour, skin, rig, width, height, **pose)) for pose in poses]
        # The rest image is lossy; a patch is small, and lossless so its edge matches what it covers.
        Image.fromarray(rests[coat]).save(out / f"Hero-{coat}.webp", quality=92, alpha_quality=100, method=6)

    # One rectangle per kind for every coat, so the app needs one number for each.
    boxes = {}
    for kind in POSES:
        x0, y0, x1, y1 = changed_box([(rests[c], f) for c in args.coats for f in frames[c, kind]])
        boxes[kind] = [round(v, 5) for v in (x0 / width, y0 / height, (x1 - x0) / width, (y1 - y0) / height)]
        for coat in args.coats:
            for n, frame in enumerate(frames[coat, kind], start=1):
                Image.fromarray(frame[y0:y1, x0:x1]).save(out / f"Hero{kind}{n}-{coat}.webp", lossless=True, method=6)
    print(json.dumps(boxes))


if __name__ == "__main__":
    main()
