# Home variants

Settings → Labs → Home picks how the first screen meets the room. The choice is kept in the App
Group as `home-variant.json` (`WidgetFeaturesModel.homeVariant`), so it survives relaunches.
Classic is the default. Every variant works with Nooki, Sunset Lamp and Window Seat.

| Variant      | What it does                                                                                                                                                                                        |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Classic      | Home as it was: the header chips, the room card and the cards below it.                                                                                                                             |
| Immersive    | The room fills the screen, under the status bar and behind the tab bar. One gold pen draws; a handle at the foot pulls up a panel with the streak, renovate, closet, shop and every card. |
| Cinematic    | Immersive, plus an opening once per launch: the camera flies in, the lights come up, the cat wakes and looks at the camera, then the note grows in. A tap skips it; Reduce Motion shows its end. |
| Living window| Immersive, plus a room that answers touch: a finger on the room is watched by the cat, holding it gives a treat, and the camera leans with the phone. Controls fade in after 3 s untouched.   |
| Night and day| Immersive, lit by the local hour (morning, day, golden hour, night with the lamp on). When the partner shares a time zone, the window (Nooki) or the sky behind the room shows their hour. |

Home falls back to Classic at accessibility type sizes and while the room is being renovated.

## Pieces

- `Pet/HomeVariant.swift`: the variants and their titles.
- `Pet/DayLight.swift`: the light of an hour, from the clock only (no location).
- `PetScene/PetSceneDirection.swift`: `FlyInTimeline`, the opening's timings shared by host and
  scene, and the environment values a host sets on a scene (`petSceneFlyIn`, `petSceneGaze`,
  `petSceneOrbits`, `petSceneFollowsTilt`, `petSceneShowsControls`, `petSceneFillsView`,
  `petSceneDayLight`, `petSceneOpeningEnded`, `petSceneCatCue`).
- `PetSceneReality/SceneDirection.swift`: the flight state and the room lighting per hour, used by
  both `NookiDiorama` and `GenzRoom`.
- `FeatureHome/FullBleedHome.swift`: the full-bleed layout, gestures, opening and panel.

## Fake partner

With the fake partner, the full-bleed variants keep the room clear: a small amber dot sits beside
the handle, and the pulled-up panel says what it means ("Fake partner: scripted replies, on this
phone only"). Classic keeps its caption.

## Trying the hours

With Night and day chosen, Labs → Home shows **Pretend hour** (the clock, 07:00, 13:00, 19:00,
23:00). It moves the date by whole hours (`DayLight.pretending`), so the partner's sky moves with
it. Saved as `pretend-hour.json` beside the variant.

The diorama goes darker at night than the shared look, so its lamp and lantern light the room.
The styled rooms are made for the evening, so daylight only adds to their own light. The
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

## Switching rooms

The diorama has one RealityView and the two styled rooms share another. Each is made the first
time its room is shown and then kept, hidden while the other is on screen, so a switch back is
instant. Sunset Lamp and Window Seat take turns in the same RealityView: a RealityView made while
another one exists only draws its first frame, so a second styled room in a view of its own stayed
dark (lamp off, no note, cat asleep, camera stuck mid-flight) or empty. Rooms step from the
display (`FrameClock`) rather than from RealityKit's update events, which come from every scene
in the app and so would step a room twice a frame while both views are kept.

On the Simulator, a switch shows the room within about 0.1 s for a styled room seen for the first
time, 0.6 s for the diorama the first time, and at once after that.

## Lighting

Labs → Lighting picks one look for every room: Off, Amber lantern (the default), Fairy lights,
Golden hour, Neon night and Candle. Each is one `LightingLook` value (`PetSceneReality`) on a
shared rig, so a new look is one more value:

- key: the lamp's colour, brightness, softness and flicker;
- fill: the ambient light's colours from above and below, and how much brighter or darker it is;
- core: a soft light low over the rug, so the room glows from inside like a lantern;
- rim: a spot light behind the cat;
- fairy lights along the wall tops, with spill lights onto the walls (Window Seat only);
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

The diorama gets the grade and vignette only.

Frame times on the Simulator, Window Seat, over 5 s windows after the opening: Off holds
16.7 ms (95th 16.7 ms); Amber lantern averages 17.1–17.7 ms, with the 95th at 16.7 ms in most
windows and 27 ms in the worst.

## Furniture

Labs → Furniture picks the pieces in the styled rooms: Original (the first block pieces), Cosy
nook (the default) and Retro den. A furnished set swaps in richer low-poly pieces built in code
(`GenzRichPieces.swift`): a quilted daybed or bed under a knitted throw, a crate of books, a
pleated lamp with a lit bulb, a leafy plant, a patterned rug, a chair with clothes, mugs, and
polaroids taped to the glass. Retro den adds a record player and a speaker. Each set is the same
kinds of piece in its own colours (`GenzFurnitureSets.swift`), placed to suit each room. The cat
keeps its place in every set.

In the Window Seat, the furnished sets build a whole cosy corner (`GenzSeatPieces.swift`):

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

`GenzRenderShots` renders a styled room offscreen on the Mac from home, from each end of the orbit
and close up:

```sh
cd packages/pet-scenes/reality
GENZ_SHOTS=/path/to/folder GENZ_FURNITURE=cosyNook swift test --filter GenzRenderShots
```

It runs only when `GENZ_SHOTS` is set. `GENZ_STYLE=sunsetLamp` renders the other room. The glow
layers are drawn by SwiftUI, so they are not in these renders.

Each room and set is its own room in the cache (`GenzLayout.Key`), built the first time it is
shown. The pieces are not sold in the shop yet, because the shop sells the diorama's models.
Where each model came from is logged in `~/.billet-manager/product/art/provenance.md`.

## Decorate

Decorating happens on Home, in the room as it is shown, in every layout and room style.

**Getting in:**
- the sofa button beside the pen, or in the styled rooms' header;
- holding a piece of furniture for about half a second, which also picks it up;
- "Change the room" in the drawer;
- placing an item from the shop.

While decorating, Home's chrome and the tab bar step aside. Holding the room no longer gives a
treat.

**Moving pieces:**
- Drag a piece to move it over the floor. It snaps to a grid: 5 cm in Nooki, a quarter unit in
  the styled rooms.
- Twist with two fingers, or tap Turn, to rotate it in 15° steps. Turn tries a quarter turn, then
  the nearest turn that fits.
- A piece keeps inside the room: pushed into a wall, it slides along it.
- It never overlaps another piece or something fixed. The marker under it is cream where it fits
  and coral where it doesn't.
- Letting go somewhere that doesn't fit sends it back.
- Rugs lie under everything.

**Undo, the closet and Reset:**
- Undo steps back through moves, turns, pieces added and pieces put away.
- The tray at the foot lists furniture waiting in the closet. Tapping one stands it at the
  nearest open spot, picked up.
- Put away sends a closet piece back to the closet.
- Reset puts the room's own furniture back where it started.

**In the styled rooms:**
- Every piece standing on the floor can be moved. What stands on a piece rides with it, such as
  the record player on its crate.
- Two pieces stay put, because the cat's walks and the lamp's glow are laid out around them:
  - the piece the cat lives on (the window seat or the bed);
  - the table under the lamp.
- Places are kept per room and furniture set (`genz.spots.<style>.<furniture>` in the app's
  defaults).

**Code:**
- `DecorPlan.swift` is the placement model: grid and turn snapping, bounds, turned-rectangle
  collision, open spots and undo history. `DecorPlanTests` cover it.
- `DecorSession` moves pieces in one room.
- `DecorTouch` maps fingers and the controls onto it.
- `DecorControls` is the SwiftUI overlay.

**Sync:** shop placements are stored in the shop state, as before. The room's own furniture is
stored on the device. Neither is sent to the partner yet; there was no partner sync of the room
before this either.
