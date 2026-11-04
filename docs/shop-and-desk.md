# Shop tab and Notes desk

The Shop tab is a flat grid in the sheets' warm glass, for every scene that has a shop (between Home
and Notes). The Notes desk is a 3D scene in the same low-poly, warm-glow style as Window Seat,
filling its tab. The desk is a Labs switch, so it can be A/B tested against the list, and starts on.

| Switch (Labs)          | On                                                                      | Off                                  |
| ---------------------- | ----------------------------------------------------------------------- | ------------------------------------ |
| Notes → Notes desk     | Notes is a desk under a cork board.                                      | Notes is the list.                   |

## The shop

- Four shelves of cards, two to a row (one at accessibility text sizes): **Furniture** (big pieces
  for the floor), **Decor** (things for a shelf, the seat or the wall), **Window views** (the paid
  views of the Style tab) and **Cat items** (treats, toys, beds, climbing things). Wall and floor
  paints, curtains and fairy lights stay in the Style tab. With Labs → Idol props on, the
  generated props join Furniture, Decor and Cat items by where they may stand
  (`IdolProp.surfaces`).
- Each card has a still picture of the item, its name and its price. The still is drawn once by
  the scene, off screen, in the room's matte look (`NookiShopThumbnails`), and kept on disk for
  the build; the flat glyph shows until it is ready.
- **One tap buys.** Tapping the price pays with stamps at once, with a success haptic, the card's
  picture pops, the stamps count down, and a strip at the foot says where it went:
  - a piece of furniture or decor is stood in the room at the first open spot
    (`RoomRenovator.renovate(.place:)`); with no open spot it waits in the closet, and the card and
    the strip offer **Place**, which opens Home's decorating with it;
  - a window view is unlocked and shown in the window;
  - a treat goes to the closet.
- **Undo** sits in the strip for 5 seconds instead of a confirmation: it gives the stamps back
  (a `refund` entry in the ledger) and takes the item out of the room, the closet or the window.
- Short of stamps, the price reads **N more**; tapping it says how many more and how stamps come
  (each pair starts with a gift of them; getting more comes later). Nothing is spent.
- A long press looks closer: a large picture with what the item is, **Buy**, and for a window
  view **Try it on in your room**, which opens Home's Style tab with the view tried on, as a tap on
  its swatch there does.
- The closet button (top right) opens the closet, with a count of what waits in it.

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

- `Pet`: `ShopCheckout` (one-tap buy, undo, the shortfall),
  `ShopItem.Shelf`, `ShopState.undoBuy`.
- `PetScene`: `shopThumbnail(_:side:scale:)` for the stills, `makeDeskScene(state:onEvent:)` with
  `DeskSceneState` and its events in `PetScene/PetSceneTabs.swift`. A scene without them returns
  `nil`: the shop shows glyphs and the host keeps the notes list.
- `PetSceneReality`: `NookiShopThumbnails`, `TabStage.swift` (the shared camera, mount rule, glow
  overlay and the `TabStages` cache), `DeskStage`, `DeskLayout` (with `CatVisit`),
  `TabScenes.swift` (the SwiftUI views).
- `FeatureHome`: `ShopView` (the grid, kept out of `Pet` so the widget does not link it), `ShopTab`,
  `DeskTab`, wired in `AppShellView`.

## Rendering

The desk renders as the rooms do (see `docs/home-variants.md`, Switching rooms): one RealityView,
mounted only once its tab is on screen (one mounted out of sight never draws), then kept. It steps
from a display-link `FrameClock` that pauses off screen. It is built in code from the styled rooms'
`GenzKit`, so meshes and materials are shared with them. The glow is a SwiftUI layer in screen
blend over the scene, at the lamps projected from the camera.

The shop keeps no renderer: its stills are drawn one at a time by one off-screen
`RealityRenderer`, which goes, with the models it loaded, a few seconds after the last one.
