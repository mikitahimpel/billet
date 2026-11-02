# Styled rooms: Sunset Lamp and Window Seat

The Nooki scene can dress its room three ways. The owner picks one in **Settings → Labs → Room
style** or from the brush button on Home while a styled room is showing. The choice is stored next
to the Labs flags (`room-style.json` in the App Group, through `WidgetFeaturesStore`); nothing
stored means the Nooki diorama, as before.

| Style         | What it is                                                                      |
| ------------- | ------------------------------------------------------------------------------- |
| `nooki`       | The cosy diorama, unchanged.                                                    |
| `sunsetLamp`  | A bedroom at 11 pm. A sunset lamp throws an orange disc on the wall, the latest received note taped in its middle. |
| `windowSeat`  | A daybed under a big window on a suburb at night. The latest note is taped to the glass and lit from behind. |

The designs are the "genz" directions 1 and 3 (`~/.billet-manager/design/genz/`). The room
numbers in `GenzLayout.swift` are the mockups' room units, so the two can be read side by side.

## Where the code is

- `packages/ios/Sources/Pet/RoomStyle.swift`: the styles and their words.
- `packages/ios/Sources/PetScene/PetSceneRooms.swift`: the contract. `RoomLayerSlot` names every flat
  layer, `RoomLayerArt` is the protocol a Rive file plugs in through, `PetSceneCatAnchorKey` tells
  the host where the cat is, and environment values carry the style, replacement art and a replay
  of the opening.
- `packages/pet-scenes/reality/Sources/PetSceneReality/Genz*.swift`: the rooms. `GenzKit` makes
  flat-shaded meshes and shared materials, `GenzPieces` the furniture, `GenzLayout` where things
  stand, `GenzRoom` the room and its opening, `GenzArt` the native flat layers, `GenzRoomView` the
  stack of layers. `NookiPetScene` picks Nooki or a styled room from the environment.
- `packages/ios/Sources/FeatureHome/StyledHome.swift`: the floating controls (streak, treat chip
  anchored to the cat, caption, Draw) over a styled room.

## How the layers stack

From back to front, as in the mockups:

1. **Behind** (`sunsetCity`, `windowNight`): a SwiftUI layer under the RealityView, seen through
   the window opening. It slides with the camera at 0.3 (Sunset) or 0.25 (Window Seat) of its turn.
2. **RealityKit**: the room, furniture, cat, note paper, LED strip as an emissive mesh, lights.
   Sunset Lamp's disc and poster are textures on wall decals (`sunsetDisc`, `sunsetPoster`).
   Window Seat's headlight sweep is a real animated spot light.
3. **Over** (`sunsetBloom`, `sunsetDim`, `windowBloom`, `windowBacklight`, `windowDim`): glow in
   screen blend and the dark the room opens in.
4. **SwiftUI** chrome from FeatureHome.

## Rive files to make

Each file replaces one native layer one for one. Give it the slot's name; the room passes
`RoomLayerState` (seconds since the opening started, camera parallax in points, the outline it
follows in view points, warmth after a note lands from 0 to 1, whether the lamp is on). A Rive
implementation of `RoomLayerArt` returns a view for a layer slot or an image for a texture slot,
and returns `nil` for the slots it does not cover. Rive stays in the app target and FeatureHome:
never in the widget, Surfaces or the notification extension.

| File                     | Slot              | Kind            | Size / artboard        | Inputs to expose                       | Motion |
| ------------------------ | ----------------- | --------------- | ---------------------- | -------------------------------------- | ------ |
| `sunset-city.riv`        | `sunsetCity`      | view, behind    | 140 × 240, plum-ink ground around it | `parallaxX`, `parallaxY`        | Lit windows flicking off and on over 9 s, slow stars. |
| `sunset-disc.riv`        | `sunsetDisc`      | wall texture    | 800 × 540 (8 × 5.4 units), transparent | `time`, `warmth`, `lampOn`  | Bloom from 35% to full over 1.2 s from 0.45 s, then breathe 100–86% on a 7 s swing; brighter centre when `warmth` > 0. |
| `sunset-poster.riv`      | `sunsetPoster`    | texture         | 100 × 190              | `time`                                 | The sun with its bar turns once every 24 s. |
| `sunset-bloom.riv`       | `sunsetBloom`     | view, over      | full screen, follows the LED outline | `outline` (3 points), `time`, `lampOn` | Steps on in three over 0.5 s from 0.1 s, then shimmers 100–70% over 5 s. Screen blend. |
| `sunset-dim.riv`         | `sunsetDim`       | view, over      | full screen            | `time`, `lampOn`                       | 82% dark until the click at 0.35 s, gone by 1.45 s. Optional: a lamp-click flash. |
| `window-night.riv`       | `windowNight`     | view, behind    | 393 × 852, fitted to width | `time`, `parallaxX`, `parallaxY`   | Street lamp stutters on (0.3–1.4 s), neighbour's window goes dark for 8 s in every 20, slow cloud drift, stars. Sky, water tower, power lines, roofs, trees. |
| `window-bloom.riv`       | `windowBloom`     | view, over      | full screen, follows the window-frame LED outline (4 points) | `outline`, `time`, `lampOn` | Warms up from 1.6 s over 1.2 s. Screen blend. |
| `window-backlight.riv`   | `windowBacklight` | view, over      | full screen, follows the note's four corners | `outline`, `time`        | Street light through the paper from 1.2 s, following the street lamp's flicker. Screen blend. |
| `window-dim.riv`         | `windowDim`       | view, over      | full screen            | `time`                                 | 75% dark to clear over 1.6 s from 0.2 s. |

The same timings are the functions in `GenzOpening.swift`; a Rive file that keeps them stays in
step with the 3D lights.

## New 3D pieces

All made in code from boxes, faceted prisms and extruded outlines (no downloaded models), one
material per part. Meshes and materials are cached in one `GenzKit` per scene, so the two rooms and
any recolour share them. Each piece has two or three colour slots; a shop variant is the same
piece with other slot colours (`GenzPiece(kind, slots:)`).

| Piece                | Room          | Slots                       |
| -------------------- | ------------- | --------------------------- |
| Low platform bed     | Sunset Lamp   | frame, linen, duvet         |
| Cube nightstand      | Sunset Lamp   | body, top                   |
| Sunset lamp          | Sunset Lamp   | body, stem, lens            |
| Checkered rug        | Sunset Lamp   | light, dark                 |
| Phone on charger     | both          | case, screen, cable         |
| Sneakers             | Sunset Lamp   | upper, sole                 |
| Hoodie pile          | Sunset Lamp   | hoodie, tee                 |
| Big monstera         | Sunset Lamp   | pot, leaf, vein             |
| Poster frame         | Sunset Lamp   | frame, print (texture slot) |
| Daybed               | Window Seat   | frame, linen, throw         |
| Milk crate           | Window Seat   | crate, inside               |
| Book stack           | Window Seat   | lower, upper                |
| Pleated thrift lamp  | Window Seat   | brass, shade                |
| Round rug            | Window Seat   | edge, middle                |
| Snake plant          | Window Seat   | pot, leaf, stripe           |

The window with its deep sill, the LED strip and the note paper belong to each room's shell.

### Not yet in the shop

The pieces are not registered as shop items yet. The shop places bought furniture through the
Nooki room's renovation (`NookiShopModels`, `NookiShopRoom`), which loads models by name from
`Room.reality`, and the styled rooms do not draw `play.room` yet. Registering them needs:

1. A `ShopItem.Look` for a code-made piece (kind and slot colours) or a `Genz_` model name that
   `NookiShopModels.furniture` builds through `GenzKit`.
2. The styled rooms drawing bought pieces, with the sill as a placement surface for small props
   (Window Seat's design asks for that).
3. Icons in `ShopItemStyle` and prices. Suggested first shelf: sunset lamp, checkered rug, milk
   crate, snake plant, pleated lamp, each in two recolours; renovate options for the LED colour and
   the wall paint; closet items from the designs (knit beanie, tiny scarf) wait for the new cat.

## Load and cost

- No new files to load: every piece is built from a handful of shared meshes on the main actor in
  a few milliseconds, before the cat arrives.
- The cat is loaded once per scene from the same files Nooki uses (`Cat.reality`, else `Cat.usdz`)
  and cloned into each styled room, so a replaced cat model shows up here with no change.
- Textures stay small: the disc is 512 × 346, the poster 128 × 243, the note 512 wide, all drawn at
  runtime. The disc is redrawn only while it blooms or warms, the poster four times a second.

## What differs from the mockups

- Type: the app's own Schibsted Grotesk and controls, not Bricolage Grotesque or Funnel; the Draw
  button keeps the shared gold primary rather than sunset orange or lamp amber.
- The app has no partner name, so captions say "Your partner".
- Tabs are the app's own (Home, Notes, Settings).
- The cat is the existing model, curled asleep, not the mockups' sitting cat.
- Accessibility text sizes and renovating keep the classic Home layout and the Nooki room.
