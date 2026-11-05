# The room: Window Seat

Home shows one room, Window Seat: a daybed under a big window on a suburb at night. The latest
received note is taped to the glass and lit from behind. The design is the "genz" direction 3
(`~/.billet-manager/design/genz/`). The room numbers in `GenzLayout.swift` are the mockup's room
units, so the two can be read side by side.

Earlier builds also had the Nooki diorama and a second styled room, Sunset Lamp, chosen in Labs
or from a brush button on Home. Both went in build 20. `RemovedScenesMigration` deletes that old
choice (`room-style.json`) and moves anyone on a removed scene to the room.

## The Nooki cabin (Labs → Room)

Build 21 brings the Nooki project's latest room back as a second choice in **Settings → Labs →
Room**; Window Seat stays the default. The choice is `HomeRoom`, kept in `home-room.json`, which
the migration never touches. The cabin is Ilya's `DioramaScene` (nexishq/nooki-ios 6b968d4) ported
into a second `GenzLayout` (`NookiCabin.swift`, `NookiCabinPieces.swift`) at 6 room units to his
metre, so it runs on the same `GenzRoom` as Window Seat: the cat, its brain and trips, the needs
(bowl, yarn), petting and toys, decorating, the lamp and the light switch all work there.

What differs, through `GenzLayout.hasOutside`: the cabin has no street, view or weather outside, no
pair style on its walls (the decorate Style tab is hidden), and none of Window Seat's flat layers.
Behind it is Ilya's amber vignette with drifting bokeh (`NookiCabinBackdrop`, at 6 fps). The note
hangs as a big polaroid in the middle of the twine garland on the back wall. The cat lives on the
floor (`catTop` is the whole floor); its home is the plush bed, which it walks into rather than
round (`catObstacles` skips a bed on the cat's floor). The cabin lights itself: a shadowed sun, the
round window's spill and a flickering candle (`GenzOwnLight`), with the lamp on the stool as the
room's lamp. Lighting presets still add their glow, haze and grade.

Not ported: Mochi, Ilya's Gaussian-splat cat (seated only, with no walk or sleep clips, and needing
iOS 27's splat API), so the cabin shows the cat chosen in Labs; his dust motes (a particle emitter);
the Moments photos on the garland (billet has no Moments), so its other four polaroids are plain
prints; and his Shop items, which were never placed in his room.

## Where the code is

- `packages/ios/pet/Sources/PetScene/PetSceneRooms.swift`: the contract. `RoomLayerSlot` names every
  flat layer, `RoomLayerArt` is the protocol a Rive file plugs in through, and
  `PetSceneCatAnchorKey` tells the host where the cat is.
- `packages/pet-scenes/reality/Sources/PetSceneReality/Genz*.swift`: the room. `GenzKit` makes
  flat-shaded meshes and shared materials, `GenzPieces` the furniture, `GenzLayout` where things
  stand, `GenzRoom` the room and its opening, `GenzArt` the native flat layers, `GenzRoomView` the
  stack of layers. `NookiPetScene` shows it through `NookiRoom`.
- `packages/ios/features/Sources/FeatureHome/StyledHome.swift`: the controls over the room: the streak, the
  decorate button and the caption ("A note from your partner · 5 min ago", or "No notes yet").
  Notes are drawn in the Notes tab; treats are given in the room, from the bowl.

## How the layers stack

From back to front, as in the mockup:

1. **Behind** (`windowNight`): a SwiftUI layer under the RealityView, seen through the window
   opening. It slides with the camera at 0.25 of its turn.
2. **RealityKit**: the room, furniture, cat, note paper, LED strip as an emissive mesh, lights.
   The headlight sweep is a real animated spot light.
3. **Over** (`windowBloom`, `windowBacklight`, `windowDim`): glow in screen blend and the dark the
   room opens in.
4. **SwiftUI** chrome from FeatureHome.

## Rive files to make

Each file replaces one native layer one for one. Give it the slot's name; the room passes
`RoomLayerState` (seconds since the opening started, camera parallax in points, the outline it
follows in view points, warmth after a note lands from 0 to 1, whether the lamp is on). A Rive
implementation of `RoomLayerArt` returns a view for a slot, and `nil` for the slots it does not
cover. Rive stays in the app target and FeatureHome: never in the widget, Surfaces or the
notification extension.

| File                     | Slot              | Kind            | Size / artboard        | Inputs to expose                       | Motion |
| ------------------------ | ----------------- | --------------- | ---------------------- | -------------------------------------- | ------ |
| `window-night.riv`       | `windowNight`     | view, behind    | 393 × 852, fitted to width | `time`, `parallaxX`, `parallaxY`   | Replaces every window view at once. To replace one view, see "Window views" below. |
| `window-bloom.riv`       | `windowBloom`     | view, over      | full screen, follows the window-frame LED outline (4 points) | `outline`, `time`, `lampOn` | Warms up from 1.6 s over 1.2 s. Screen blend. |
| `window-backlight.riv`   | `windowBacklight` | view, over      | full screen, follows the note's four corners | `outline`, `time`        | Street light through the paper from 1.2 s, following the street lamp's flicker. Screen blend. |
| `window-dim.riv`         | `windowDim`       | view, over      | full screen            | `time`                                 | 75% dark to clear over 1.6 s from 0.2 s. |

The same timings are the functions in `GenzOpening.swift`; a Rive file that keeps them stays in
step with the 3D lights.

## Window views

What Window Seat's glass looks out on is a view, chosen in **Settings → Labs → View** with its
weather (clear, rain, snow, fog) and hour (morning, day, dusk, night). "As made" leaves the weather
to the view and the hour to the room: night, or the hour of the day when Home follows it. The
choice is `window-view.json` next to the Labs flags. Art rules are in the style bible
(`~/.billet-manager/product/art/style-bible.md`), and every view's provenance is logged in
`~/.billet-manager/product/art/provenance.md`.

| View          | What it is |
| ------------- | ---------- |
| `suburbNight` | US suburb at night: water tower, power lines, roofs, the houses across the street, the street lamp. |

How a view is made (`packages/pet-scenes/reality/Sources/PetSceneReality/Views/`):

- **Stage.** Art is laid out in stage units against the window: the opening is 100 wide and 58
  tall, its top left corner at the origin. The sill hides the glass below about 52, so a street
  stays above that line. The note is taped over the middle, so hero shapes stand to its sides.
- **Planes.** A `ViewRecipe` paints four planes: far, middle, street, near. Each still plane is
  painted once per look (view, hour, weather) into a bitmap. When the camera turns, each plane
  follows a share of the window's movement on screen (0.2 far up to 0.85 near): that is the
  parallax. The shared sky (gradient, stars, the moon in its phase, clouds, a plane's lights) sits
  behind, and the air (rain, snow) and the glass (sheen, the lamp's reflection, drops, frost) in
  front.
- **Life.** Moving things are drawn every frame from the wall clock. `ViewRhythm` places at most
  one pass of an event in each slot at a hashed time, so gaps, directions and colours never loop.
- **The cat.** A recipe names what moves (`interest`): the cat turns its head to it, and paws at a
  drop running down the glass beside it when it is up. The room's 3D headlight sweep follows the
  view's cars (`headlight`).
- **Rive.** `WindowViewArt` (in `PetScene`, environment `petSceneViewArt`) returns a view for a
  `WindowView` and a `WindowViewState` (view, weather, hour, opening time, wall clock, the window
  outline now and at the camera's home, lamp on), or `nil` to keep the native one. A Rive file for
  one view plugs in there; a `RoomLayerArt` for `windowNight` still replaces all of them.

## New 3D pieces

All made in code from boxes, faceted prisms and extruded outlines (no downloaded models), one
material per part. Meshes and materials are cached in one `GenzKit` per scene, so every furniture
set and recolour shares them. Each piece has two or three colour slots; a shop variant is the same
piece with other slot colours (`GenzPiece(kind, slots:)`).

| Piece                | Slots                       |
| -------------------- | --------------------------- |
| Phone on charger     | case, screen, cable         |
| Daybed               | frame, linen, throw         |
| Milk crate           | crate, inside               |
| Book stack           | lower, upper                |
| Pleated thrift lamp  | brass, shade                |
| Round rug            | edge, middle                |
| Snake plant          | pot, leaf, stripe           |

The window with its deep sill, the LED strip and the note paper belong to the room's shell.

### Not yet in the shop

The pieces are not registered as shop items yet. Shop furniture is the baked `Item_*` models in
`Room.reality`, and the room does not draw `play.room` yet. Registering code-made pieces needs a
`ShopItem.Look` for a kind and its slot colours, the room drawing bought pieces (with the sill as
a placement surface for small props), and icons and prices in `ShopItemStyle`.

## Load and cost

- No new files to load: every piece is built from a handful of shared meshes on the main actor in
  a few milliseconds, before the cat arrives.
- The cat is loaded once per scene (the chosen `Cat_<model>.reality`, else the standard Detailed
  cat) and cloned into the room, so a replaced cat model shows up here with no change.
- The note's texture is 512 wide, drawn at runtime when a note lands.

## What differs from the mockups

- Type: the app's own Schibsted Grotesk and controls, not Funnel.
- There is no Draw button on Home: notes are drawn in the Notes tab.
- The app has no partner name, so the caption says "your partner".
- Tabs are the app's own (Home, Notes, Settings).
- The cat is the existing model, curled asleep, not the mockups' sitting cat.
- Accessibility text sizes keep the classic Home layout.
