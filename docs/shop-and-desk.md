# Shop tab and Notes desk

Two 3D scenes in the same low-poly, warm-glow style as Window Seat, each filling a tab. Both are
Labs switches, so they can be A/B tested against the screens they replace, and both start on.

| Switch (Labs)          | On                                                                      | Off                                  |
| ---------------------- | ----------------------------------------------------------------------- | ------------------------------------ |
| The house → Shop tab   | A Shop tab between Home and Notes: a little shop at night, the keeper behind the counter. | No Shop tab; the shop stays a sheet on Home. |
| Notes → Notes desk     | Notes is a desk under a cork board.                                      | Notes is the list.                   |

Labs → Shopkeeper (shown while the Shop tab is on) picks the keeper: **Old tabby** (default: a
ginger cat in a cardigan and round glasses, which reads as a shopkeeper at a glance and keeps its
face at the size it is seen), Raccoon, or Fox. Stored as `shopkeeper.json` beside the flags.

## The shop

- Furniture stands on two bays of shelves on the back wall, two to a shelf (three once the
  catalog outgrows that). Each piece is the same model the room and the shop preview use,
  true to life where it fits, never smaller than half a unit, a rug stood up to face you.
- Treats sit on saucers on the counter; paints (a tin per wall colour) and floor samples (a stack
  of boards per floor) are on a low table by the window.
- Tapping anything for sale makes it hop, the keeper glances at it, and the existing shop sheet
  opens on that item (`ShopView(item:)`): price in stamps, Buy, the closet. The sheet stops at
  half height, so the keeper can be seen cheering when something is bought. Bought things go to
  the closet as before; placing one from the closet takes you to Home to put it in the room.
- The keeper breathes, blinks, sways its tail, follows you with its head, waves when the tab
  opens or when tapped, and cheers (arms up, two hops, happy eyes) after a purchase. Reduce Motion
  keeps the head following and drops the bouncing.
- The window shows a street at blue hour, drawn at runtime.

## The desk

- Blank paper lies on the desk under an arm lamp; a pencilled heart asks for a drawing. Tapping it
  opens the existing canvas; sending works as from Home.
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
