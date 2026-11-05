# Home variants

Settings → Labs → Home picks how the first screen meets the room. The choice is kept in the App
Group as `home-variant.json` (`WidgetFeaturesModel.homeVariant`), so it survives relaunches.
Classic is the default. Every variant shows the one room, Window Seat.

| Variant      | What it does                                                                                                                                                                                        |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Classic      | Home as it was: the header chips, the room card and the cards below it.                                                                                                                             |
| Immersive    | The room fills the screen, under the status bar and behind the tab bar. A handle at the foot pulls up a panel with the streak, the closet and every card. Notes are drawn in the Notes tab. |
| Cinematic    | As Immersive. Every Home now glides into the room on a cold launch (see [onboarding](onboarding.md)); it is kept so a stored or remote choice of it still reads. |
| Living window| Immersive, plus a room that answers touch: a finger on the room is watched by the cat, holding it gives a treat, and the camera leans with the phone. Controls fade in after 3 s untouched.   |
| Night and day| Immersive, lit by the local hour (morning, day, golden hour, night with the lamp on). When the partner shares a time zone, the sky behind the room shows their hour. |

Home falls back to Classic at accessibility type sizes.

## Pieces

- `Pet/HomeVariant.swift`: the variants and their titles.
- `Pet/DayLight.swift`: the light of an hour, from the clock only (no location).
- `PetScene/PetSceneDirection.swift`: `FlyInTimeline`, the opening's timings shared by host and
  scene, and the environment values a host sets on a scene (`petSceneFlyIn`, `petSceneGaze`,
  `petSceneOrbits`, `petSceneFollowsTilt`, `petSceneShowsControls`, `petSceneFillsView`,
  `petSceneDayLight`, `petSceneOpeningEnded`, `petSceneCatCue`).
- `PetSceneReality/SceneDirection.swift`: the flight state and the room lighting per hour, used by
  `GenzRoom`.
- `FeatureHome/FullBleedHome.swift`: the full-bleed layout, gestures, opening and panel.

## Fake partner

With the fake partner, the full-bleed variants keep the room clear: a small amber dot sits beside
the handle, and the pulled-up panel says what it means ("Fake partner: scripted replies, on this
phone only"). Classic keeps its caption.

## Trying the hours

With Night and day chosen, Labs → Home shows **Pretend hour** (the clock, 07:00, 13:00, 19:00,
23:00). It moves the date by whole hours (`DayLight.pretending`), so the partner's sky moves with
it. Saved as `pretend-hour.json` beside the variant.

The room is made for the evening, so daylight only adds to its own light. The
partner's lit sky glows down from the top of the backdrop.

## Hooks for the cat

Two moments are cues, sent by whatever schedules the cat and played with the cat's clips through
`CatBehaviour.cue(_:at:)`, so every model in Labs → Cat plays them with what it has:

- `CatCue.wakeUp`: stretches (or yawns, or perks) and stays up a while.
- `CatCue.lookAtCamera`: rests where the head may turn and holds the viewer's eye for
  `CatBehaviour.viewerLook` seconds; a cat still waking looks once it is done. Any finger the head
  was following is let go.

`HomeView` owns a `CatDirector`; anything with access to it calls `director.send(.wakeUp)`, and
the newest request reaches the scene as `petSceneCatCue`. The opening sends the same cues on its
own timeline: wake at `FlyInTimeline.wake` (0.9 s), look at `FlyInTimeline.look` (3 s), so a
three-second stretch is done before the note grows in at 3.9 s. Living window's finger turns the
head through the rig, not the body.

## Limits

- The Simulator has no motion sensor, so tilt in Living window is only seen on a device.
- The opening waits for the room to load, so on a cold start it begins about 3 s after launch.

## Mounting the room

The room has one RealityView, made the first time Home is on screen: a RealityView made off screen
never draws. The room steps from the display (`FrameClock`) rather than from RealityKit's update
events, which come from every scene in the app and would step it more than once a frame.

## Lighting

Labs → Lighting picks one look for every room: Off, Amber lantern (the default), Fairy lights,
Golden hour, Neon night and Candle. Each is one `LightingLook` value (`PetSceneReality`) on a
shared rig, so a new look is one more value:

- key: the lamp's colour, brightness, softness and flicker;
- fill: the ambient light's colours from above and below, and how much brighter or darker it is;
- core: a soft light low over the rug, so the room glows from inside like a lantern;
- rim: a spot light behind the cat;
- fairy lights along the wall tops, with spill lights onto the walls;
- sun: a low directional light through the window, with shadows;
- the LED strip's colour and the colour of the light from outside;
- contact shadows: soft dark patches under floor furniture and the cat;
- haze, halos, grade and vignette: flat SwiftUI layers over the view.

RealityKit on iOS 26 has `renderingEffects.customPostProcessing`, which could give real bloom, but
on the iOS 26.2 Simulator setting it traps inside RealityKit (`ARView.renderCallbacks.setter`), in
both the make and update closures. So bloom is drawn in the view instead: soft radial halos over
each light, screen-blended in a `Canvas`, placed from the room's lights projected to the screen.
The grade multiplies a tint over everything and screen-blends a lift under the darks, so nothing is
pure black and nothing is hard white.

Frame times on the Simulator, Window Seat, over 5 s windows after the opening: Off holds
16.7 ms (95th 16.7 ms); Amber lantern averages 17.1–17.7 ms, with the 95th at 16.7 ms in most
windows and 27 ms in the worst.

## Furniture

Labs → Furniture picks the pieces in the room: Original (the first block pieces), Cosy
nook (the default) and Retro den. A furnished set swaps in richer low-poly pieces built in code
(`GenzRichPieces.swift`): a quilted daybed under a knitted throw, a crate of books, a
pleated lamp with a lit bulb, a leafy plant, a patterned rug, mugs, and
polaroids taped to the glass. Retro den adds a record player and a speaker. Each set is the same
kinds of piece in its own colours (`GenzFurnitureSets.swift`). The cat
keeps its place in every set.

The furnished sets build a whole cosy corner (`GenzSeatPieces.swift`):

- a built-in seat under the window, with panelled doors, a piped linen cushion level with the sill
  where the cat sits, pillows leaning on the glass, a folded knitted throw over the front, a
  cardigan dropped on the seat, mugs and a phone;
- a bookshelf beside the seat full of varied books, with a vase, a sprig, a photo and a candle;
- a turned side table holding the lamp (a glazed ceramic base) and candles that flicker;
- polaroids, wall shelves (a trailing plant, dried grass, candles, a cactus) and string lights
  on the side wall;
- a knitted pouf and a cat bed on the rug, and plants on the floor.

The camera starts a little further round, so the bookshelf corner is in view.

Soft things use smooth meshes made in code (`GenzSoft.swift`):

- pillows and cushions seamed round their middle;
- turned pots, mugs and candles;
- tubes for sleeves and wires;
- rounded boxes for the wood.

Wood, knit and linen get 128-pixel textures drawn in code, with a normal map for their relief.
Ceramics are glazed. The room keeps to a budget of 120,000 triangles (a test checks it). A test
also checks that floor pieces never overlap and stay inside the room.

`GenzRenderShots` renders the room offscreen on the Mac from home, from each end of the orbit
and close up:

```sh
cd archive/ios-v1/packages/pet-scenes-reality
GENZ_SHOTS=/path/to/folder GENZ_FURNITURE=cosyNook swift test --filter GenzRenderShots
```

It runs only when `GENZ_SHOTS` is set. The glow
layers are drawn by SwiftUI, so they are not in these renders.

Each furniture set is its own room in the cache (`GenzLayout.Key`), built the first time it is
shown. The pieces are not sold in the shop yet.
Where each model came from is logged in `~/.billet-manager/product/art/provenance.md`.

## Decorate

Decorating happens on Home, in the room as it is shown, in every layout.

**Getting in:**
- the sofa button on the room;
- holding a piece of furniture for about half a second, which also picks it up.

While decorating, Home's chrome and the tab bar step aside. Holding the room no longer gives a
treat.

**Moving pieces:**
- Drag a piece to move it over the floor. It snaps to a grid of a quarter unit.
- Twist with two fingers, or tap Turn 90°, to rotate it in 15° steps. Turn 90° tries a quarter
  turn, then the nearest turn that fits.
- A piece keeps inside the room: pushed into a wall, it slides along it.
- It never overlaps another piece or something fixed. The piece picked up lifts, with a soft
  glowing ring on the floor under it that breathes slowly. The ring is gold where the piece fits
  and coral where it doesn't, and the toolbar then says "No room here".
- Letting go somewhere that doesn't fit sends it back.
- Rugs lie under everything.

**Undo:** steps back through moves and turns.

**Controls:**
- Top: undo on the left and a gold-tinted Done on the right, both 44 pt Liquid Glass.
- Bottom, while a piece is picked up: one glass toolbar with the piece's name and Turn 90°, plus
  Put away for furniture from the closet.
- Bottom, with nothing picked up: "Tap a piece to move it". A room that takes closet furniture
  shows an Add items button there instead; Window Seat draws none, so it doesn't.
- The first time a piece is picked up, "Drag to move · twist to turn" shows for four seconds
  and never again (`decorGestureHintShown` in the app's defaults).
- A soft haptic tap as a piece is picked up, and a lighter one as it is set down.

**What moves:** everything but the window and the seat the cat lives on, each piece on its own
surface:
- **Floor:** the rug, pouf, plants, bookshelf, cat bed, side table, and the crate and speaker.
- **Seat:** the four pillows, the throw, the mugs, the cardigan and the phone, along the seat's
  top. The throw and the cardigan hang over its front edge, so they only slide along it and
  don't turn (no Turn 90°). The cat lying there blocks a piece like anything else.
- **Tops:** what stands on a piece moves on that piece's top and rides with it: the lamp and
  candles on the side table, the record player on its crate. The lamp's light and its glow
  follow the bulb wherever the table goes.
- Pieces hung on the wall (shelves, polaroids, string lights) don't move yet.
- The cat's walks on the seat go round pillows, mugs and the rest where they now stand.

**Reset layout:** the ⋯ button next to undo puts every piece back where the room first had it.

**Saved:** places are kept per furniture set (`genz.spots.windowSeat.<furniture>` in the app's
defaults; the key keeps the room's name so places saved before stay). A piece on a top is kept
in its base's space, so it stays on the table wherever the table goes.

**Shared with the partner:** each move and each reset sends the room's arrangement as an
`arrange` play (`room` such as `windowSeat.cosyNook`, `spots` of moved pieces as `[x, z, yaw]`).
The pair's room keeps the last one per room and replays them on connect, so both rooms stand
their furniture the same. A partner's arrangement moves pieces straight to their places; a piece
picked up at that moment stays in hand.

**Code:**
- `DecorPlan.swift` is the placement model: grid and turn snapping, bounds, turned-rectangle
  collision, open spots and undo history. `DecorPlanTests` cover it.
- `DecorSession` moves pieces in one room, one `DecorPlan` per surface.
- `DecorTouch` maps fingers and the controls onto it.
- `DecorControls` is the SwiftUI overlay.

**Sync:** where the room's furniture stands is stored on the device and not sent to the partner.
