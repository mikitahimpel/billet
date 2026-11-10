# props-bake

Turns Idol (image to 3D Gaussian splat) props into shop and room assets. Runs on the pc (`ssh pc`, Ubuntu WSL, RTX 3070,
Blender 4.5); every GPU or heavy CPU step takes `~/billet-gpu/.klein.lock`, so one job runs at a time. Nothing here runs on the Mac.

## Pipeline

1. Reference image: FLUX.2-klein edit of `inputs/props/style-ref.png` (`gen_batch.py`, prompt = object + the shared style tail,
   see `inputs/props*/` refs json). Two seeds per object.
2. Splat: Idol, 50 steps, 262144 Gaussians, one job file per object in `inputs/<group>/jobs/` (`idol_watch.sh <group>`).
3. Mesh: `build_pc.sh <name>...` = `dense_mesh.py` (splat to dense coloured mesh) then `remesh_prop.py` (voxel remesh, flat base,
   decimate to the triangle budget in `specs.json`, smart UV, 512 px colour bake). Output `props-build/remeshed/<name>.{obj,png,json}`.
4. Orient: `prep_obj.py remeshed final <id>=<name>:<yaw>:<floor|wall>`: yaw about Y so the front is +Z, origin at the base
   centre (floor) or the middle with the back at -z (wall).
5. Look: `render_props.py sheet ...` (3 views on neutral grey, for curation) and `render_props.py tile ...` (512 px transparent,
   one 3/4 camera direction, one light rig, soft contact shadow, framed per object with a 12% margin). Convert the tile to WebP
   (`quality=88`).
6. Pack: `pack_items.py final specs.json out 0.5 <id>=<name>...` writes `Item_<id>.usdz` (one mesh, one material, one 512 px JPEG)
   and `Item_<id>.json`.

## Scale

Idol sizes in `specs.json` are real-world metres. The room is about 1 m wide, so models ship at 0.5 of that (the scale the
Shop catalog already used for the Idol pieces); `width_m`, `depth_m`, `height_m` in the JSON are in room metres.

## Catalog JSON

`id`, `name`, `kind` (`SOLID` stands and blocks, `FLAT` rugs, cushions and wall pieces, `SURFACE` carries other pieces),
`width_m`, `depth_m`, `height_m`, `footprint_cells` (5 cm cells, rounded up, `[x, z]`), `mount` (`floor` or `wall`),
`fit` and `size_m` (what `ShopItem.Look.furniture` takes), `anchors` (empty for now), `tris`, `affordance`, `usdz_kb`.

## Where the files go

`apps/ios/Nooki/Resources/Shop/Item_<id>.{usdz,webp,json}`. `Thumbnails` loads `Item_<id>.webp` and falls back to `.png`.
The room draws a lighter copy made by the room's own LOD step; these models are already 800 to 3000 triangles.

## Curation

Each object is judged on a contact sheet (front, 3/4, back). Rejected on the first pass: broken or floating geometry (wall shelf, guitar,
mirror, tilted plant poster, neon heart), a figurine instead of a frame (cat frame), black cracks (lava lamp), a stool-like cushion
(sage floor cushion). Rejected objects are re-rolled from the second reference with another seed (`props3`, name suffix `-b`).
