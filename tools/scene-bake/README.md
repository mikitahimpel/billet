# scene-bake

Content baked on the pc (`ssh pc`, Blender 4.5 with Cycles on the RTX 3070, GPU jobs under `~/billet-gpu/.klein.lock`) so the
phone draws images and baked light instead of live 3D. Nothing here runs on the Mac but `cwebp` and Python.

## Suburb diorama (the Bedroom window)

`./bake.sh [--samples 128] [--width 1280]` renders `city_diorama.py` for day, dusk and night, converts to WebP and writes
`apps/ios/Nooki/Resources/CityDiorama/` (about 350 KB). The scene is an American suburb on a grid of lots: detached clay houses (colonial, ranch with a garage and a parked car, bungalow and
farmhouse with porches), lawns, picket fences, mailboxes, big rounded trees, lamp posts, a quiet street with a side street and a
crossing, a steeple and low hills; the layout is identical in the three times, only light, sky and lit
windows change. Layers are transparent 1280x704 (1.82:1, the window is 0.8 x 0.44 in `CityRoomScene.opening`) with a margin of 5.56% on
every side for parallax: `diorama.json`'s `visible` is the part the window shows.

| File | What |
| --- | --- |
| `sky_{day,dusk,night}.webp` | opaque gradient (moon and stars at night), no parallax |
| `far_*.webp` | hills, steeple, distant roofs and tree lines, parallax follow 0.2 (`ViewPlane.far`) |
| `mid_*.webp` | the two rows of houses with lawns and driveways, the side street, follow 0.42 (`.middle`) |
| `street_*.webp` | road, sidewalks, picket fences, mailboxes, front-yard trees, lamp posts, crossing, follow 0.62 (`.street`) |
| `near_*.webp` | a hedge with flowers along the bottom edge, follow 0.85 (`.near`) |
| `cars_*.webp` | 6 clay cars (sedan, SUV, pickup, twice) in one row (1280x213, six cells, all facing right); mirror them for the other direction |
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

## Kitchen corner (the feed, water and brush games)

`kitchen.py` models the kitchen corner procedurally (clay boxes, cylinders, balls and lofted leaf blades in the Living
room's palette: cream wall, honey cupboards, sage tiles, terracotta jars, a blush café curtain, a lit mustard pendant)
and bakes it into two opaque images drawn unlit on two quads:

```sh
flock ~/billet-gpu/.klein.lock blender -b -P kitchen.py -- out/kitchen wall  --samples 256   # kitchen_wall.png
flock ~/billet-gpu/.klein.lock blender -b -P kitchen.py -- out/kitchen floor --samples 256   # kitchen_floor.png
flock ~/billet-gpu/.klein.lock blender -b -P kitchen.py -- out/kitchen look  --samples 64    # look_game.png, look_wide.png
cwebp -q 82 -noalpha kitchen_wall.png -o kitchen_wall.webp   # and the same for the floor
```

Each run takes about 15 s on the 3070. Shipped in `apps/ios/Nooki/Resources/Kitchen/` with `kitchen.json`:

| File | What |
| --- | --- |
| `kitchen_wall.webp` | the wall straight on, orthographic, 1.0 m x 1.1 m (1024x1126): counter run (top at 0.255 m), sage backsplash, window with sill and café curtain left of centre, shelf of jars, utensil rail, pendant lamp; the lower middle 0.5 m x 0.3 m is kept clear for the cat |
| `kitchen_floor.webp` | the floor from above, 1.2 m wide x 0.9 m deep (1024x768), top of the image at the wall: neutral honey boards, a cream flat-weave rug with rounded corners (oat border, sage line, tonal end stripes, short fringe), the counter's contact shadow along the top edge and a soft vignette |
| `kitchen.json` | sizes in metres; `rug` and `clear` as fractions of the image (origin top left) |

The wall image's plane is the counter's front: stand the wall quad on the floor quad's back edge. `look` lays the two
PNGs on quads in the game's room and renders them from `TabletopRoom`'s camera with a stand-in cat (`look_game`) and with
a 40 degree lens from the same spot (`look_wide`), to judge the whole corner.

## Style references

`docs/city-room-style.md`.

## Room pieces (the Living room's own furniture)

The room's furniture a player can move is one USDZ each, `apps/ios/Nooki/Resources/Room/Base_<piece>.usdz` (windowseat,
nightstand, plant, lamp, cattree, bowls, donutbed, basket, books, rug; catalog ids `base-<piece>`). Each has its origin on the
boards (y = 0 at their top, 0.014 in the room) in the middle of the cell it stands in when the room is as it always was
(`PIECES` in `apps/ios/Tools/make_room.py`, the cells of `tools/decor-lod/catalog.py` `BASE`), so a holder at that cell
reproduces the room. `Room_furniture.usdz` keeps what never moves: the round window with `Glow_window`, the shelf, the picture
and the fairy-light wire. Together they have the same 283,820 triangles the single model had.

```sh
rsync -a apps/ios/Tools/ pc:billet-gpu/rearr/Tools/
ssh pc 'cd ~/billet-gpu/rearr && ~/billet-gpu/blender-app/blender-billet -b --python Tools/make_room.py -- new'   # about 5 s
scp 'pc:billet-gpu/rearr/new/Base_*.usdz' pc:billet-gpu/rearr/new/Room_furniture.usdz apps/ios/Nooki/Resources/Room/
# one piece only: ... make_room.py -- new Base_rug
# bounds (width, depth, top, and the bounds' middle dx, dz from the cell middle) for tools/decor-lod/catalog.py
blender -b -P tools/decor-lod/bounds.py -- apps/ios/Nooki/Resources tools/decor-lod/bounds.json
# the floor decal holds only what stays: the shell and the fixed furniture; each piece draws its own blob
scp apps/ios/Nooki/Resources/Room/Room_shell.usdz pc:billet-gpu/rearr/
ssh pc 'cd ~/billet-gpu/rearr && flock ~/billet-gpu/.klein.lock ~/billet-gpu/blender-app/blender-billet -b -P contact_shadow.py -- room_contact.png 0.017 Room_shell.usdz,new/Room_furniture.usdz --size 1024 --bounds -0.595,-0.595,0.56,0.56'
cwebp -quiet -q 82 -alpha_q 92 -m 6 room_contact.png -o apps/ios/Nooki/Resources/RoomBake/room_contact.webp
```
