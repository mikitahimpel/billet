# Notices

The MIT licence in [LICENSE](LICENSE) covers billet's own code. The assets below are not covered by
it.

## Cats

The cats in `packages/pet-scenes/reality/Sources/PetSceneReality/Resources/Cats` (tabby, plush,
detailed, detailedKitten, detailedFluffy, hero, chibi, kitten, tuxedo) are new models made for
billet in Blender. The detailed cats' and the hero's fur, stripes, fur cards and normal maps are
made in Blender from billet's own model; no outside model or texture is used.

## Idol cats

The Idol cats (`Cat_idol*`) and splat cats (`Splat_*.bsplat`) in the same folder were generated on
a Mac with [Idol](https://huggingface.co/speridlabs/idol) (Speridlabs, Apache License 2.0), run
through its MLX port in [mlx-vlm](https://github.com/Blaizzy/mlx-vlm) (MIT). Idol's only input was
a Blender render of billet's own detailed cat. Its image encoders were DINOv3
(`facebook/dinov3-vith16plus-pretrain-lvd1689m` weights, as repackaged in
`ddalcu/Idol-MLX-Serve-8bit`; Meta's DINOv3 License) and the FLUX.2 VAE from
`black-forest-labs/FLUX.2-klein-4B` (Apache License 2.0). None of these models ships in the app;
only the generated splats and the meshes made from them do. The pipeline follows
nexishq/idol-scenes. See [docs/idol-splats.md](docs/idol-splats.md).

`Cat_idolIlya`: Cat by Ilya (nexishq), used with permission. Made by the same pipeline from his
illustration in nexishq/idol-scenes.

The cats in the room's style (`Cat_gingerChonk` and the others made with it) were generated on a
PC: each starts from a picture made by FLUX.2-klein-4B (Black Forest Labs, Apache License 2.0)
from a text prompt, with renders of billet's own room and detailed cat as style references. Idol
then ran through [idol-sdk](https://github.com/speridlabs/idol-sdk) (Speridlabs, Apache License
2.0) on PyTorch (BSD-3-Clause), with the same DINOv3 (Meta's DINOv3 License) and FLUX.2 VAE
encoders, and BiRefNet (MIT) to cut the cat from its background. As above, no model ships in the
app, only the meshes made from its output. Marmalade (`Cat_marmalade`) was made the same way from a
standing view FLUX.2-klein-4B drew of billet's own ginger cat concept, with the picture's lighting
taken out of its baked colour.

## Idol props

`packages/pet-scenes/reality/Sources/PetSceneReality/Resources/IdolProps.reality` (the Labs
"Idol props" pilot) holds room props generated for billet. Each began as a picture made with
[FLUX.2-klein-4B](https://huggingface.co/black-forest-labs/FLUX.2-klein-4B) (Black Forest Labs,
Apache License 2.0), prompted in words and, for some, with a render of billet's own Window Seat
room as a style reference. [Idol](https://huggingface.co/speridlabs/idol) (Speridlabs, Apache
License 2.0) turned each picture into a splat, run on a CUDA GPU through Speridlabs' own
[idol-sdk](https://github.com/speridlabs/idol-sdk) (Apache License 2.0), with the DINOv3 image
encoder (`facebook/dinov3-vith16plus-pretrain-lvd1689m`, Meta's DINOv3 License) and the FLUX.2
VAE from FLUX.2-klein-4B. The splats were remeshed, decimated and their colour baked in Blender.
None of these models ships in the app; only the meshes and their one baked texture do.

## First-launch heart

`packages/pet-scenes/reality/Sources/PetSceneReality/Resources/Heart.reality` is a new model made
for billet in Blender from code alone (`packages/pet-scenes/reality/scripts/make_heart.py`); no
outside model or texture is used. The windowsill, candles and fairy lights around it are built in
Swift at run time.

## Night street in 3D

`packages/pet-scenes/reality/Sources/PetSceneReality/Resources/StreetView` (the street outside
Window Seat's window behind Labs' "3D view") is made for billet from code alone: modelled and
light-baked in Blender by `packages/pet-scenes/reality/scripts/make_street_view.py`, its far
roofline card painted by `paint_street_cards.py`. The far skyline
(`packages/pet-scenes/reality/assets-source/street/skyline.png`, keyed and tiled into
`street-cards.png`) was generated for billet from a text prompt with
[FLUX.2-klein-4B](https://huggingface.co/black-forest-labs/FLUX.2-klein-4B) (Black Forest Labs,
Apache License 2.0) on the owner's PC. The model does not ship in the app; only the image made with
it does. No outside model or texture is used.

## Project assets

- `packages/pet-scenes/reality/Sources/PetSceneReality/Resources/*.usdz` come from the Nooki project.
- The Nooki cabin (`packages/pet-scenes/reality/Sources/PetSceneReality/NookiCabin.swift` and
  `NookiCabinPieces.swift`) comes from the Nooki project: its room, furniture, colours, lights and
  backdrop are ported from `Nooki/Scene/DioramaScene.swift` and `HomeView.swift` in
  [nexishq/nooki-ios](https://github.com/nexishq/nooki-ios) at 6b968d4, with its author's permission.
  It ships no files from that project; every shape is built in code.
