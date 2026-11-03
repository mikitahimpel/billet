# Shop tab and Notes desk

Two 3D scenes in the same low-poly, warm-glow style as Window Seat, each filling a tab. The Shop tab
is always there (between Home and Notes: a little shop at night, the keeper behind the counter), for
every scene that has a shop. The desk is a Labs switch, so it can be A/B tested against the list, and
starts on.

| Switch (Labs)          | On                                                                      | Off                                  |
| ---------------------- | ----------------------------------------------------------------------- | ------------------------------------ |
| Notes → Notes desk     | Notes is a desk under a cork board.                                      | Notes is the list.                   |

Labs → Shopkeeper picks the keeper: **Teddy bear** (default: a
well-loved plush bear in fuzzy fabric, with button eyes, stitched seams, nose and mouth, a red bow
tie and a patched belly) or **Shopkeeper** (a round, friendly person in a green apron). Stored
as `shopkeeper.json` beside the flags; a keeper saved before the old tabby, raccoon and fox were
retired comes back as the teddy.

## The shop

- Furniture stands on two bays of shelves on the back wall, two to a shelf (three once the
  catalog outgrows that). Each piece is the same model the room and the shop preview use,
  true to life where it fits, never smaller than half a unit, a rug stood up to face you.
- Treats sit on saucers on the counter; paints (a tin per wall colour) and floor samples (a stack
  of boards per floor) are on a low table by the window.
- Buying is meant to be found in two seconds:
  - Everything for sale carries a paper price tag with the stamp seal and its price (a tick once
    a paint or floor is owned). Tapping a tag is the same as tapping its item.
  - Items bob gently where they stand, out of step, and a glint passes over one now and then.
  - When the tab opens, the keeper bows hello, then sweeps an arm to the shelves on each side
    while a glint runs over every item it shows, then over the counter and the table.
  - The first visit shows one short hint, "Tap anything with a price tag to buy it", until the
    first tap or a few seconds pass.
- Tapping an item makes it hop, and it floats forward in front of the counter, grown and slowly
  turning, in a pool of light. A card shows its name, what it is for, and **Get for N stamps**
  (or how many stamps are missing, or Owned). Details opens the old shop sheet on it.
- Getting it: the keeper reaches over the counter with a parcel in craft paper and a red ribbon,
  hands it over (the parcel flies to you and fades), then cheers. A note says it is in your
  closet, with the way there; placing it from the closet goes to Home as before.
- The keeper's clips are the same for every keeper: idle (breathe, blink, sway, tail, follow you
  with its head), greet (a bow), present (arms to the shelves), wave (when tapped), hand over and
  cheer. Reduce Motion keeps the head following and drops the bobbing, turning and hops.
- The shop window looks out on the same view as the room's window: Labs → View, its weather and
  hour, drawn by the same view art (`NativeWindowView`, or a `WindowViewArt` replacement),
  following the time of day when Home does.

## The desk

- Blank paper lies on the desk under an arm lamp, a pencil across it that fidgets now and then as
  if asking to be picked up, in a soft breathing glow. A pencilled "draw here" (or "draw your
  first note" on an empty board) writes itself out once with an arrow to the page. A tap anywhere
  on the desk top opens the existing canvas straight away; sending works as from Home.
- With no notes yet, a dashed card is pinned where the first one will go; tapping it draws too.
- The board pins the latest note large and up to eight more small, each with a lean and a pin
  colour taken from its id, so nothing moves around as notes arrive. Tapping one lifts it and
  opens the existing note viewer (replay, reactions, frames, wallpaper as their Labs switches say).
- The list button (top right) opens the list as before, with the shelf board and every note; at
  accessibility text sizes Notes is the list.
- The cat chosen in Labs → Cat visits: it is there when the desk opens, sits by the paper and
  fidgets (looks round, grooms, slow blinks), sometimes naps, sometimes wanders off for a while.
  Tapping it gets a happy wriggle.

## Code

- `PetScene`: `makeShopScene(state:onEvent:)` and `makeDeskScene(state:onEvent:)`, with
  `ShopSceneState`, `DeskSceneState` and their events in `PetScene/PetSceneTabs.swift`. A scene
  without them returns `nil` and the host keeps the old screens.
- `PetSceneReality`: `TabStage.swift` (the shared camera, mount rule, glow overlay and the
  `TabStages` cache), `ShopStage`, `ShopLayout`, `KeeperMotion`, `KeeperRig`, `DeskStage`,
  `DeskLayout` (with `CatVisit`), `TabScenes.swift` (the SwiftUI views).
- `FeatureHome`: `ShopTab`, `DeskTab`, wired in `AppShellView`.

## Rendering

As the rooms do (see `docs/home-variants.md`, Switching rooms): one RealityView per tab, mounted
only once its tab is on screen (one mounted out of sight never draws), then kept. Each stage steps
from a display-link `FrameClock` that pauses off screen. Everything is built in code from the
styled rooms' `GenzKit`, so meshes and materials are shared with them; only the keeper (60–90 KB)
and the shelf furniture (`Room.reality`) load from files, after the room is already showing. The
glow is a SwiftUI layer in screen blend over the scene, at the lamps projected from the camera.

## Making the keepers

`packages/pet-scenes/reality/scripts/bake_shopkeepers.sh` runs Blender in background mode on
`make_shopkeepers.py` and compiles each keeper with `realitytool`. Pass names to rebuild only
some; `make_shopkeepers.py -- --render <folder>` also renders a look at each. Provenance is in the
product art log.
