# scene-bake

Content baked on the pc (`ssh pc`, Blender 4.5 with Cycles on the RTX 3070, GPU jobs under `~/billet-gpu/.klein.lock`) so the
phone draws images and baked light instead of live 3D. Nothing here runs on the Mac but `cwebp` and Python.

## City street diorama (the window)

`./bake.sh [--samples 128] [--width 1280]` renders `city_diorama.py` for day, dusk and night, converts to WebP and writes
`apps/ios/Nooki/Resources/CityDiorama/` (about 350 KB). The city is a grid of straight clay buildings in the Room's palette, one
cross street with a crossing, trees and lamp posts; the layout is identical in the three times, only light, sky and lit
windows change. Layers are transparent 1280x704 (1.82:1, the window is 0.8 x 0.44 in `CityRoomScene.opening`) with a margin of 5.56% on
every side for parallax: `diorama.json`'s `visible` is the part the window shows.

| File | What |
| --- | --- |
| `sky_{day,dusk,night}.webp` | opaque gradient, no parallax |
| `far_*.webp` | hazed skyline, parallax follow 0.2 (`ViewPlane.far`) |
| `mid_*.webp` | the two rows of buildings, the cross street, follow 0.42 (`.middle`) |
| `street_*.webp` | road, sidewalks, trees, lamp posts, crossing, benches, follow 0.62 (`.street`) |
| `cars_*.webp` | 6 clay cars in one row (1280x213, six cells, all facing right); mirror them for the other direction |
| `diorama.json` | sizes, visible rectangle, follow per layer, lanes and crossing |

Cross-fade between times by the hour (dusk and night have lit windows and lamp pools baked in). Cars: `lanes[].y` is the
car's base as a fraction of the layer height, `scale` multiplies a cell's size, `direction` -1 is leftwards (`far` lane) and 1
rightwards (`near`). `crossing.left/right` are the crossing's edges as fractions of the width: a car waits before the edge it
reaches first. Cars are drawn above `street_*` and below nothing, so a lamp post never hides one.

`preview.py <dir> <time> <out.png>` stacks the layers into one picture for a look.

## Baked contact shadows and occlusion for the rooms

`contact_shadow.py` renders a room's models seen from above, lit evenly by the sky, with a shadow catcher on the floor: one
transparent image (black, shadow in alpha) with the soft contact shadow under every piece and the occlusion at the wall
feet. Lay it on a quad at `floor_y`, unlit and alpha-blended, over the boards; no light or shadow is needed for it.

```sh
blender -b -P contact_shadow.py -- room_contact.png 0.017 Room_furniture.usdz,Room_shell.usdz --size 1024
```

Shipped in `apps/ios/Nooki/Resources/RoomBake/`: `room_contact.webp` (+ `.json`: the rectangle it covers in room space, the top of
the image at `z0`, the back wall) and `city_contact.webp`. The quad is `floor_y` = 0.017, 3 mm above the boards, which the
decal has to clear.

`bake_model.py` bakes light and occlusion into one atlas for a whole USDZ and writes it unlit, like `scripts/bake-room`
does for the shells. It works on any USDZ with flat colours, but `Room_furniture.usdz` (144k faces, many tiny parts) unwraps
into a 4.4 MB atlas and a 14.8 MB model, so use it on a batch of a few simple props (a bookshelf, the bed), not on all of it.
Lights come from `lights/room.json` (a copy of the RealityKit lights, as in `scripts/bake-room/bake_shell.py`).

## Style references

`docs/city-room-style.md`.
