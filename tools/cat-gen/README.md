# cat-gen

A cat splat pipeline, used with its author's permission. It
turns one picture of a cat into a Gaussian splat, binds it to a skeleton, and gives the app
(`apps/ios`) the files it renders: `<name>.ply`, `<name>.rig.json` and `<name>.skin`.

`idol-sdk/` is Speridlabs' [Idol](https://huggingface.co/speridlabs/idol) inference code, Apache
License 2.0 (`idol-sdk/LICENSE`), without its gallery images and Gradio demo.

## How Mochi was made

1. **Reference image.** `refs/cat-sitting.png` (sitting, head turned like the body) and
   `refs/cat-standing.png`: one picture per pose, the cat alone on a plain background.
2. **Idol.** One image in, 3D Gaussians out (front toward +X, up toward -Y). On Apple Silicon it runs
   on MLX through mlx-vlm, elsewhere on PyTorch through `idol-sdk`. Both of Mochi's poses were
   generated at 131,072 splats.
3. **make_splat.py.** Turns the result into RealityKit space (front toward -Z, up +Y), stands it on
   y = 0 at its height in meters (`--height 0.30`; `--yaw` if the picture faces elsewhere), drops
   nearly clear splats, and writes a PLY with 14 floats per splat in GaussianSplatResource's layout.
   With `--match_colors`, the second pose takes the first pose's colors region by region
   (`match_colors.py`), so the cat does not change shade when it stands up.
4. **skin.py.** With `--rig rigs/cat-sit.json` or `rigs/cat-standing.json`, binds every splat to up
   to four bones and writes `<name>.rig.json` (bones, the point between the eyes, the mount for a
   second pose) and `<name>.skin` (4 bone indices and 4 weights per splat, uint8, in the PLY's
   order). The app's `SkinSplats.metal` moves the splats with these weights every frame.
5. **The app.** `SplatLoader` reads the PLY as it is: its body is already GaussianSplatResource's
   layout. Mochi's files are checked byte for byte against `apps/ios/nooki-cat.sha256`.
6. **Lying down.** The loaf and the curled sleep are the seated splat posed, not splats of their own,
   so she stays the same cat: `cat-sit.json` gives her fore legs and paws to fold and keeps the
   haunch's paws on the floor. A bone added to a rig needs its joint in the mesh fallback too:
   `apps/ios/Tools/reskin_mochi_mesh.py --name Mochi` (or `MochiStanding`) after `--bind`.

## Run it

Needs Node 20.11+ and [uv](https://docs.astral.sh/uv/). Setup downloads about 5 GB of weights into
`weights/` (none gated); generated files go to `out/`, both ignored by git.

```sh
node tools/cat-gen/setup.mjs
node tools/cat-gen/splat.mjs --image tools/cat-gen/refs/cat-sitting.png --out Mochi.ply --height 0.30 \
  --rig tools/cat-gen/rigs/cat-sit.json
node tools/cat-gen/splat.mjs --image tools/cat-gen/refs/cat-standing.png --out MochiStanding.ply \
  --height 0.30 --rig tools/cat-gen/rigs/cat-standing.json --match_colors Mochi.ply
cp Mochi.ply MochiStanding.ply Mochi.rig.json Mochi.skin MochiStanding.rig.json MochiStanding.skin apps/ios/Nooki/Resources/
```

`node tools/cat-gen/splat.mjs ourio` builds every asset of `scenes/ourio.json` into `out/ourio`.
`make_splat.py --help` lists the rest (`--bind` to only re-skin, `--recolor` to only match colors,
`--seed`, `--steps`, `--num_gaussians`).

`viewer.html` shows one splat in the browser with three.js and Spark; it runs inside
idol-scenes' Vite app (`npm run dev` there), which is not part of this repository.
