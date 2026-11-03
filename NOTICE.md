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

## First-launch heart

`packages/pet-scenes/reality/Sources/PetSceneReality/Resources/Heart.reality` is a new model made
for billet in Blender from code alone (`packages/pet-scenes/reality/scripts/make_heart.py`); no
outside model or texture is used. The windowsill, candles and fairy lights around it are built in
Swift at run time.

## Night street in 3D

`packages/pet-scenes/reality/Sources/PetSceneReality/Resources/StreetView` (the street outside
Window Seat's window behind Labs' "3D view") is made for billet from code alone: modelled and
light-baked in Blender by `packages/pet-scenes/reality/scripts/make_street_view.py`, its far
cards painted by `paint_street_cards.py`. No outside model, texture or generated image is used.

## Project assets

- `packages/pet-scenes/reality/Sources/PetSceneReality/Resources/*.usdz` come from the Nooki project.
