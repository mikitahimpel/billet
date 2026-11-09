# Sand3D programs

Shop furniture written as short Python programs over [Sand3D](https://github.com/Sandflow-ai/sand3d)
(Apache-2.0), which builds them with Blender's `bpy`. Why and how it compares with `make_items.py` and Idol:
[docs/sand3d-spike.md](../../docs/sand3d-spike.md).

| File | What |
| --- | --- |
| `billet_style.py` | The room's look: Ourio palette, `clay` / `cloth` / `wood` materials, bevel radii, tessellation |
| `armchair.py` | `armchair(fabric, cushion, legs)` |
| `drawers.py` | `chest_of_drawers(..., open=)`; the bottom drawer slides on a joint |
| `plant.py` | `potted_plant(kind, pot, ...)`: monstera, snake plant, bush |
| `armchair-colourways.json` | The armchair colourways the app bundles, with a suggested name and blurb each; no prices |
| `build.py` | Program → GLB → USDZ, plus the 1024 px shop thumbnail |
| `sweep.py` | Many armchair variants at once, to choose colourways from |
| `measure.py` | Triangles, size, meshes, materials and textures of any USDZ, without Blender |

## Pipeline

1. Once: `uv venv -p 3.13 && uv pip install sand3d==1.6.3` (pulls bpy 5.2.3, about 750 MB). Python 3.12
   has no bpy wheel. Keep the pin: `billet_style.tessellate()` sets a private module value.
2. On the shared Mac, Blender runs only under the build lock (`~/.billet-manager/build.lock`), one run at a
   time, with a time cap. Eight items with thumbnails take about 4 to 6 minutes under load, so build them in
   two runs.
3. Build into the app's bundle:

   ```sh
   PYTHONPATH=tools/sand3d .venv/bin/python tools/sand3d/build.py apps/ios/Nooki/Resources/Shop --thumbs
   ```

   With no ids it builds what the app ships: every colourway in `armchair-colourways.json`, `chest` and
   `monstera-potted`. Each becomes `Item_<id>.usdz` and `Item_<id>.png`, the names `Thumbnails` and
   `ItemSheet` load.
4. Check the numbers: `python3 tools/sand3d/measure.py apps/ios/Nooki/Resources/Shop/Item_<id>.usdz`.
5. The catalog row is the owner's, made in the admin: [docs/admin.md](../../docs/admin.md#sand3d-items).

What `build.py` does to every export:

- Sand3D models in millimetres under a 0.001 root scale. `build.py` bakes that scale into the meshes and offsets,
  so every node is in metres and the root's scale is 1.
- USD export with `make_items.py`'s settings: Y up, 1 m per unit, preview surfaces, no textures.
- A joint's moving node gets the joint's name. The chest's drawer slides by moving the node `bottom_drawer`,
  0 to 0.3 m towards the chest's front. RealityKit gets no joint, only the node.
- The thumbnail uses `make_items.py`'s camera, lights and shadow catcher, rendered in Cycles on the CPU
  (24 samples, denoised), so the shop card and `ItemSheet`'s live model line up.

Rules for a new program:

- Real size in millimetres, Z up, front towards -Y.
- Centred in X and Y with the base on z = 0, so the pivot is on the floor.
- Only `billet_style` colours and materials: matte, non-metallic, no textures.
- Every edge softened.
- Keep it under today's item of the same kind in triangles; `measure.py` tells.

## Licence rule

- Only our own programs go in here, written from Sand3D's API docs and our style.
- Never use objects, meshes, programs or renders from Sand3D's datasets (Objaverse, NVIDIA SimReady or any
  other), or from any other dataset. Their licences are per object, many are non-commercial, and none of them
  were made for us.
- Sand3D itself is Apache-2.0 and bpy is GPL. Both are tooling only. Nothing from either ships in the app; the
  USDZ files and thumbnails we build are ours.
