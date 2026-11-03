# Idol cats and splat cats

Labs → Cat has cats that [Idol](https://huggingface.co/speridlabs/idol) made from a single picture.
Each comes in two forms:

- **Idol <coat>** (`CatModel.idolGinger`, …): a textured mesh of at most 10k triangles and a
  1024 px texture, skinned to the shared cat skeleton, with every clip. It works on every device.
- **Splat <coat>** (`CatModel.splatGinger`, …): the Gaussian splat Idol made, moved by the same
  skeleton. It needs RealityKit's `GaussianSplatComponent`: the iOS 27 SDK (Xcode 27) to build,
  iOS 27 to run, and an Apple7 GPU (A14 or later). Anywhere else it is the Idol mesh, and Labs
  leaves it out of the list so it doesn't repeat that mesh.

## How a cat is made

The scripts live outside the repo, in `~/.billet-manager/pet-concept/splat/scripts/`.

1. `render_refs.py` (Blender): one of billet's cats in its bind pose, three-quarter front view,
   soft light, transparent backdrop. The bind pose matters: the splat is later given the
   skeleton's weights by nearest surface. A calico coat is painted procedurally.
2. `gen_staged.py`: Idol on MLX in three one-process passes: encode (DINOv3 + FLUX.2 VAE), denoise
   (8-bit denoiser), decode. Only one part of the model is in memory at a time. Each pass waits
   while swap is high or a real `xcodebuild` runs, and a watchdog stops it if swap passes 15 GB.
   On the M1 a 131,072-Gaussian cat takes about 25 s to encode (7.3 GB peak), 33 min to denoise
   50 steps (1.9 GB peak) and 12 s to decode.
3. `align_skin.py`: into the mesh's own space, a yaw search and a scaled ICP onto the bind-pose
   mesh, then each splat takes the blended weights of its four nearest vertices (top four joints).
   It renders the splat posed by real clips from the USD to check the weights.
4. `cat_mesh.py`: the splat to a mesh (billet-scenes' `splat2mesh.py`: density volume, marching
   cubes, quadric decimation, xatlas, baked colour), keeping the coordinates.
5. `idol_cat_blend.py` (Blender): the mesh replaces `Tabby` in a copy of the cat's `.blend`.
   Weights move across by nearest surface, and the eye bones' share goes to the head, since Idol
   paints the eyes on. Then cathd's `clips.py export`, `fix_usd.py`, `compact_usd.py`, `usdzip`
   and `bake_cat.py` run as for every cat.
6. `pack_splat.py`: the skinned splat as `Splat_<coat>.bsplat`. The format is quantised and
   DEFLATE-compressed, about 2.2 MB for 131k splats against 7.3 MB as raw floats; see
   `SplatCloud`.

## How a splat cat runs

`NookiAssets.compiledCat` loads the Idol mesh as for any cat, and `SplatCat.dress` adds the splat
body beside its skinned mesh, which turns invisible but keeps animating. Every frame
`SplatCatSystem` reads the mesh's joint poses and a Metal kernel (`SplatSkinning`) writes the posed
splats into the `LowLevelBuffer` behind the `GaussianSplatResource`. That is linear blend skinning
for centres and blended joint rotations for orientations. So the rig, clips, look-at, needs and
behaviour all drive the splat with no change.

The decoder, the skinning maths and the kernel build on today's SDK and are tested on the Mac
(`SplatCloudTests`). Only `SplatCatBody` and `SplatCatSystem` sit behind `#if compiler(>=6.4)` and
`@available(iOS 27, *)`. They follow nexishq/nooki-ios's `SplatLoader` and have not been compiled
yet: that waits for Xcode 27.

## Licences

- Idol weights and SDK: Apache-2.0 (Speridlabs). The MLX port: MIT (mlx-vlm).
- DINOv3: Meta's DINOv3 License. It allows commercial use. We run it only on the Mac and ship no
  DINOv3 weights, so its "Built with DINOv3" display term for redistribution does not apply to the
  app. Generated outputs are not addressed by the licence; we read them as outputs, not
  derivatives (not legal advice).
- FLUX.2 VAE: from FLUX.2-klein-4B, Apache-2.0. It is the same tensors as FLUX.2-dev's VAE cast to
  bf16 (checked by billet-scenes), so nothing non-commercial is used.
