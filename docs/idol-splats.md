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

## Cats from illustrations (Ilya's cat)

Idol's splats are much cleaner from a clean illustration than from a render of our model. Ilya's
cat comes from his own illustration, with his permission (FLUX.2-klein-4B on the Mac makes such
pictures too: `gen_refs.py`). The picture must stand square, head and body facing the same way, to
match the skeleton's standing bind pose: a sitting splat tears when it is unposed onto it. In the app
the cat still sits through the sit clip.

Marching cubes leaves slivers and seams that open into white cracks once the mesh bends, so
`remesh_bake.py` rebuilds the surface in Blender: a 2.5 mm voxel remesh (closed, even triangles),
decimated to 9k, new UVs with wide margins, the colour baked from the first mesh with a 24 px
bleed. The weights then move across from the template and are smoothed (`IDOL_SMOOTH=20`).

An Idol cat's head is much bigger than the template's, so clips that bring the head down to the
body push it inside: groomFlank and groomTail (head turned back to the flank), groom (head down to
a paw) and lieDown. Check every clip from the room camera's angle, high and in front, not only
side-on. The Idol cats' clip tables leave groomFlank, groomTail and lieDown out, so the cat plays
their stand-ins (groom, sleep). Their groom plays the lickLips frames: groom has no stand-in, and a
made cat must have it.

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

## Cats in the room's style, and the pose QA

From 2026-11-04 new cats start from a picture in the room's style (FLUX.2-klein-4B with renders of
the room and the detailed cat as style references): adult proportions, a normal-sized head,
standing square on four paws, one tail. A picture goes to Idol only after a check of tails, legs,
ears, eyes and body (`cat-style/qa`, plus a look at the sheet). Idol runs on the PC; meshing,
rigging and QA run on the Mac, one cat at a time (`splat/scripts/make_cat.sh`, checkpointed).

Every clip of every cat is checked before it ships (`qa_cat.py`, `qa_verdict.py`):

- six key frames per clip, and the cross-fade from its middle back to its base pose at 25, 50 and
  75 %, skinned as RealityKit blends joints;
- scores against the detailed cat's own score for the same clip: surface pushed inside a body part
  it doesn't border (head into chest), faces crossing faces far from them at rest, triangles
  collapsing or blowing up, edges stretching, new folds;
- one tail: the tail-weighted part of the mesh must be a single piece;
- the contact sheet from the in-app angles (home, orbit high and low, close-up), failing clips in
  red, which a person looks over. groomFlank fails by eye on every Idol cat.

A failing clip that has stand-ins is left out of that cat's clip table, so the app plays a
stand-in; one without stand-ins plays a passing clip's frames from the same base pose. A cat whose
idle, walk, sit or sleep fails, or that hasn't exactly one tail, doesn't ship. Ilya's cat fails its
sleep and is out of the picker until it is remade in the room's style.
