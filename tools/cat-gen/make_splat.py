"""Turns reference images into Gaussian splats the app renders with GaussianSplatComponent.

Run through `npm run splat --`, which uses the Python that `npm run setup` built:
  npm run splat -- ourio                    # every asset of generate/scenes/ourio.json
  npm run splat -- ourio --only Cat         # some of them
  npm run splat -- --image photo.png --out Lamp.ply --height 0.4 [--mode real]
  npm run splat -- --ply generate/out/Cat.ply --out Cat.ply --height 0.30   # skip generation, only post-process
  npm run splat -- --ply generate/out/Cat.ply --out Cat.ply --height 0.30 --yaw -87   # and turn it to face -Z
  npm run splat -- --bind assets/cat-standing.ply --rig generate/rigs/cat-standing.json   # only re-skin
  npm run splat -- --recolor assets/cat-sit.ply --match_colors assets/cat-standing.ply   # only match colors

Pipeline:
1. Idol generates the object as 3D Gaussians: front toward +X, up toward -Y. On Apple Silicon it runs on MLX
   (mlx-vlm), elsewhere on PyTorch (the vendored idol-sdk); both write the same PLY.
2. Rotate into RealityKit space (front toward -Z, up +Y, like the Blender-made models), center the
   footprint on the origin, stand it on y = 0 and scale it to its height in meters. Idol faces the object the way
   the picture shows it; when that is not toward -Z, `yaw` turns it about +Y, in degrees.
3. Drop nearly transparent splats: they cost overdraw and count toward RealityKit's splat limit.
4. Write a binary PLY whose 14 floats per splat follow GaussianSplatResource's layout
   (position, log scale, rotation w x y z, logit opacity, SH DC), so the app copies the bytes as is.
5. With a reference (an asset's "match_colors" or --match_colors), match the colors region by region to that
   already built .ply, e.g. the same cat generated in another pose; see match_colors.py.
6. With a rig (an asset's "rig" or --rig), bind the splats to its skeleton; see skin.py.
The raw Idol output, the image it saw and a four-view preview stay in generate/out/<name>*.
"""

import argparse
import json
import platform
import sys
from pathlib import Path

import numpy as np
from plyfile import PlyData

import skin
from match_colors import match_colors

HERE = Path(__file__).resolve().parent
RAW = HERE / 'out'
DEFAULTS = {'mode': 'synthetic', 'seed': 42, 'steps': 50, 'num_gaussians': 131_072, 'min_opacity': 0.02, 'yaw': 0}
FIELDS = ['x', 'y', 'z', 'scale_0', 'scale_1', 'scale_2', 'rot_0', 'rot_1', 'rot_2', 'rot_3',
          'opacity', 'f_dc_0', 'f_dc_1', 'f_dc_2']
# 180 degrees about (1, 0, -1): +X -> -Z, -Y -> +Y.
TO_REALITYKIT = np.array([[0, 0, -1], [0, -1, 0], [-1, 0, 0]], dtype=np.float64)
TO_REALITYKIT_Q = np.array([0, 1, 0, -1]) / np.sqrt(2)
SH_C0 = 0.28209479


def load_pipeline(backend, weights, fast=False):
    if backend == 'auto':
        backend = 'mlx' if sys.platform == 'darwin' and platform.machine() == 'arm64' else 'torch'
    print(f'loading Idol ({backend}) from {weights}')
    if backend == 'mlx':
        from mlx_vlm.generate.three_d import load_3d_model

        return load_3d_model(str(weights), local_files_only=True)
    from idol import IdolPipeline

    # optimize=True would also torch.compile the denoiser, which needs Triton and only pays off after the first image.
    pipeline = IdolPipeline.from_pretrained(str(weights), optimize=False)
    if pipeline.device.type == 'cuda':
        pipeline.optimize = fast
        park_idle_models(pipeline)
    return pipeline


def park_idle_models(pipeline):
    """Keep only the denoiser in VRAM: background removal, the encoders and the decoders each run once per image,
    so they wait in RAM. Same output, about 1 GB less VRAM while sampling."""
    import torch

    def on_gpu(run, models):
        def staged(*args, **kwargs):
            for model in models:
                model.to(pipeline.device)
            try:
                return run(*args, **kwargs)
            finally:
                for model in models:
                    model.to('cpu')
                torch.cuda.empty_cache()
        return staged

    encoder = pipeline.image_encoder
    stages = {'preprocess': [pipeline.background_remover], 'image_encoder': [encoder.dinov3, encoder.flux2_vae],
              'decode': [pipeline.decoder, pipeline.decoder_gs]}
    for name, models in stages.items():
        setattr(pipeline, name, on_gpu(getattr(pipeline, name), models))
        for model in models:
            model.to('cpu')
    torch.cuda.empty_cache()


def generate(pipeline, name, asset):
    output = pipeline(str(asset['image']), mode=asset['mode'], seed=asset['seed'], steps=asset['steps'],
                      num_gaussians=asset['num_gaussians'], verbose=True)
    RAW.mkdir(exist_ok=True)
    path = RAW / f'{name}.ply'
    output.gaussian.save_ply(str(path))
    output.preprocessed_image.save(RAW / f'{name}_input.png')
    return path


def quat_mul(a, b):
    aw, ax, ay, az = a
    bw, bx, by, bz = b.T
    return np.stack([aw * bw - ax * bx - ay * by - az * bz,
                     aw * bx + ax * bw + ay * bz - az * by,
                     aw * by - ax * bz + ay * bw + az * bx,
                     aw * bz + ax * by - ay * bx + az * bw], 1)


def load(path):
    v = PlyData.read(path)['vertex']
    return {f: np.asarray(v[f], dtype=np.float64) for f in FIELDS}


def load_array(path):
    """A post-processed .ply as rows of the 14 floats."""
    v = load(path)
    return np.stack([v[f] for f in FIELDS], 1).astype('<f4')


def align(s, height, min_opacity, yaw=0):
    keep = 1 / (1 + np.exp(-s['opacity'])) >= min_opacity
    half = np.radians(yaw) / 2
    turn = np.array([np.cos(half), 0, np.sin(half), 0])
    c, si = np.cos(2 * half), np.sin(2 * half)
    to_app = np.array([[c, 0, si], [0, 1, 0], [-si, 0, c]]) @ TO_REALITYKIT
    xyz = np.stack([s['x'], s['y'], s['z']], 1)[keep] @ to_app.T
    rot = np.stack([s[f'rot_{i}'] for i in range(4)], 1)[keep]
    rot = quat_mul(quat_mul(turn, TO_REALITYKIT_Q[None])[0], rot / np.linalg.norm(rot, axis=1, keepdims=True))

    lo, hi = xyz.min(0), xyz.max(0)
    factor = height / (hi[1] - lo[1])
    xyz = (xyz - [(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2]) * factor
    log_scale = np.stack([s[f'scale_{i}'] for i in range(3)], 1)[keep] + np.log(factor)
    color = np.stack([s[f'f_dc_{i}'] for i in range(3)], 1)[keep]
    out = np.concatenate([xyz, log_scale, rot, s['opacity'][keep, None], color], 1).astype('<f4')
    print(f'kept {len(out)} of {len(keep)} splats, size {np.round(xyz.max(0) - xyz.min(0), 3)} m')
    return out


def write_ply(path, data):
    header = ['ply', 'format binary_little_endian 1.0', f'element vertex {len(data)}']
    header += [f'property float {f}' for f in FIELDS] + ['end_header', '']
    with open(path, 'wb') as f:
        f.write('\n'.join(header).encode('ascii'))
        f.write(data.tobytes())


def preview(path, data, size=512):
    """Front, left, back and right views: opaque centers in painter's order, enough to check pose and color."""
    from PIL import Image

    solid = 1 / (1 + np.exp(-data[:, 10])) > 0.2
    xyz = data[solid, :3]
    rgb = np.clip(0.5 + SH_C0 * data[solid, 11:14], 0, 1)
    center = (xyz.min(0) + xyz.max(0)) / 2
    p = xyz - center
    scale = 0.84 * size / 2 / np.abs(p).max()
    tiles = []
    for angle in np.radians([0, 90, 180, 270]):
        # Turn the model, then look at it from -Z: screen right is -X there.
        x = p[:, 0] * np.cos(angle) + p[:, 2] * np.sin(angle)
        z = -p[:, 0] * np.sin(angle) + p[:, 2] * np.cos(angle)
        sx, order = -x, np.argsort(-z)
        ix = (size / 2 + sx[order] * scale).astype(int)
        iy = (size / 2 - p[order, 1] * scale).astype(int)
        img = np.ones((size, size, 3))
        for dx in (0, 1):
            for dy in (0, 1):
                img[np.clip(iy + dy, 0, size - 1), np.clip(ix + dx, 0, size - 1)] = rgb[order]
        tiles.append(img)
    Image.fromarray((np.concatenate(tiles, 1) * 255).astype(np.uint8)).save(path)


def scene_jobs(args):
    """(name, asset, output path) for each asset of a scene file; its paths are relative to the file."""
    path = Path(args.scene)
    if not path.suffix:
        path = HERE / 'scenes' / f'{args.scene}.json'
    scene = json.loads(path.read_text())
    out_dir = Path(args.out) if args.out else path.parent / scene['out']
    names = args.only.split(',') if args.only else list(scene['assets'])
    unknown = set(names) - set(scene['assets'])
    if unknown:
        raise SystemExit(f'not in {path.name}: {", ".join(sorted(unknown))}')
    out_dir.mkdir(parents=True, exist_ok=True)
    for name in names:
        asset = {**DEFAULTS, **scene['assets'][name]}
        asset['image'] = path.parent / asset['image']
        for key in ('rig', 'match_colors'):
            if key in asset:
                asset[key] = path.parent / asset[key]
        yield name, asset, out_dir / f'{name}.ply'


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('scene', nargs='?', help='scene name in generate/scenes, or a path to a scene .json')
    parser.add_argument('--only', help='comma-separated asset names of the scene')
    parser.add_argument('--image', help='one image instead of a scene')
    parser.add_argument('--ply', help='raw Idol output to post-process instead of generating')
    parser.add_argument('--out', help='output .ply; with a scene, the output folder instead of its own')
    parser.add_argument('--height', type=float, help='meters, floor to top')
    parser.add_argument('--mode', choices=['synthetic', 'real'], help="'real' for photos")
    parser.add_argument('--seed', type=int)
    parser.add_argument('--steps', type=int, help='sampling steps, 50 by default; 20 to 30 for quick drafts')
    parser.add_argument('--fast', action='store_true',
                        help='CUDA: batched guidance, cuDNN attention, TF32; ~12%% faster, output differs slightly')
    parser.add_argument('--num_gaussians', type=int, help='32,768 to 1,048,576, a multiple of 32')
    parser.add_argument('--min_opacity', type=float)
    parser.add_argument('--yaw', type=float, help='degrees to turn the result about +Y so it faces -Z')
    parser.add_argument('--backend', choices=['auto', 'torch', 'mlx'], default='auto')
    parser.add_argument('--weights', default=HERE / 'weights' / 'idol')
    parser.add_argument('--rig', help='rig spec in generate/rigs to bind the output to')
    parser.add_argument('--bind', help='an already post-processed .ply to only bind to --rig')
    parser.add_argument('--match_colors', help='a built .ply whose colors to match, region by region')
    parser.add_argument('--recolor', help='an already post-processed .ply to only match to --match_colors, in place')
    args = parser.parse_args()

    if args.recolor:
        if not args.match_colors:
            parser.error('--recolor needs --match_colors')
        write_ply(args.recolor, match_colors(load_array(args.recolor), load_array(args.match_colors)))
        print(f'{args.recolor}: colors matched to {args.match_colors}')
        return

    if args.bind:
        if not args.rig:
            parser.error('--bind needs --rig')
        data = load_array(args.bind)
        skin.bind(args.bind, data, args.rig)
        return

    overrides = {k: getattr(args, k) for k in ('mode', 'seed', 'steps', 'num_gaussians', 'min_opacity', 'height',
                                               'rig', 'yaw', 'match_colors')
                 if getattr(args, k) is not None}
    if args.scene:
        jobs = [(name, {**asset, **overrides}, out) for name, asset, out in scene_jobs(args)]
    elif (args.image or args.ply) and args.out and args.height:
        source = {'image': args.image} if args.image else {'ply': args.ply}
        jobs = [(Path(args.out).stem, {**DEFAULTS, **overrides, **source}, Path(args.out))]
    else:
        parser.error('give a scene, or --image/--ply with --out and --height')

    pipeline = None
    for name, asset, out in jobs:
        raw = asset.get('ply')
        if not raw:
            pipeline = pipeline or load_pipeline(args.backend, args.weights, args.fast)
            raw = generate(pipeline, name, asset)
        data = align(load(raw), asset['height'], asset['min_opacity'], asset['yaw'])
        if asset.get('match_colors'):
            data = match_colors(data, load_array(asset['match_colors']))
        write_ply(out, data)
        if asset.get('rig'):
            skin.bind(out, data, asset['rig'])
        RAW.mkdir(exist_ok=True)
        preview(RAW / f'{name}_preview.png', data)
        print(f'{name}: {out}')


if __name__ == '__main__':
    main()
