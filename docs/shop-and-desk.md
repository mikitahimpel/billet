# Shop tab and Notes desk

The Shop tab is a flat grid in the sheets' warm glass, for every scene that has a shop (between Home
and Notes). The Notes desk is a 3D scene in the same low-poly, warm-glow style as Window Seat,
filling its tab. The desk is a Labs switch, so it can be A/B tested against the list, and starts on.

| Switch (Labs)          | On                                                                      | Off                                  |
| ---------------------- | ----------------------------------------------------------------------- | ------------------------------------ |
| Notes → Notes desk     | Notes is a desk under a cork board.                                      | Notes is the list.                   |

## The shop

The shop is laid out like a good game store, for two people rather than a casino. From the top:

1. **This week**: one bundle, its pieces fanned out on a warm plate, its name and a line on what it
   makes of the room, a **−N%** value tag, the sum of its parts struck through beside its price,
   and a timer to Monday 00:00 UTC, when the next one comes.
2. **A gift for today**: free, one tap, once a day per phone. Some stamps (10, 15 or 20) or, one
   day in four, a treat for the cat. The box wobbles until it is opened and bursts into stamps when
   it is; then it counts down to the next one.
3. **Today's deals**: three items at 20, 25 or 30 % off, in a row that scrolls sideways, with the
   usual price struck through and a timer to 00:00 UTC.
4. **Bundles**: the other sets (Rainy evening, Reading nook, Green corner, Cat heaven) and, until it
   is bought once, the starter **Make it yours** at 40 % off. A bundle charges only for what is
   still to get: a view or curtains already owned are left out of its price and its struck sum.
5. **For your cat**: treats, toys and beds, each with a line on what the cat does with it. A long
   press shows the cat beside the thing, hearts rising, its reaction in a bubble.
6. **Furniture**, **Decor** and **Window views**, as before.

The week's bundle, the deals and the gift follow from the pair's room code and the UTC day or week
(`ShopOffers`, seeded with `StableRandom`), so both phones show the same without asking a server,
and each timer runs to a real change. Nothing runs out, nothing says "only N left", and a timer
never restarts on reopening.

**Giving.** A long press on a piece or a treat offers **Give to your partner**: a sheet with the
item, an optional note (80 characters) and its price, one tap. It is paid at once and can be taken
back for 5 seconds like any purchase; after that it is wrapped and sent, and lands on the partner's
doormat with the note (Labs → Wrapped delivery shows the doormat). The room passes a gift to the
partner at once, or keeps it (up to 20) until they connect (`gift` and `gift-opened` play frames in
`DemoRoom`).

**Stamps.** Tapping the balance, or **Where stamps come from** under "N more", opens a sheet that
says how stamps come: a gift to start, the gift every day, and packs later. With Labs → Stamp packs
on, a row of packs sits below it; until a `StampPackSource` sells any it is a placeholder whose
button does nothing. Real money comes through that protocol only, never through StoreKit in the
shop (billet-pay's `StampShop` conforms to it).

**Counting.** `ShopOpened`, `ShopOfferViewed` (once per offer per visit), `ShopItemBought`,
`ShopBundleBought`, `ShopGiftSent`, `ShopPurchaseUndone` and `ShopDailyGiftClaimed`, as in
`docs/analytics.md`. The admin's "most chosen" shows bundles bought, offers seen and gifts.

The shelves:

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

- `Pet`: `ShopCheckout` (one-tap buy of an item, a deal, a bundle or a gift; undo; the
  shortfall), `ShopOffers` (the rotation), `ShopBundle`, `DailyGift`, `StampPackSource`,
  `ShopItem.Shelf`, `ShopState.undoBuy`.
- `PetScene`: `shopThumbnail(_:side:scale:)` for the stills, `makeDeskScene(state:onEvent:)` with
  `DeskSceneState` and its events in `PetScene/PetSceneTabs.swift`. A scene without them returns
  `nil`: the shop shows glyphs and the host keeps the notes list.
- `PetSceneReality`: `NookiShopThumbnails`, `TabStage.swift` (the shared camera, mount rule, glow
  overlay and the `TabStages` cache), `DeskStage`, `DeskLayout` (with `CatVisit`),
  `TabScenes.swift` (the SwiftUI views).
- `FeatureHome`: `ShopView` (the store, kept out of `Pet` so the widget does not link it),
  `ShopOfferViews` (banner, deal and bundle cards, the daily gift), `ShopSheets` (stamps, giving),
  `ShopTab`,
  `DeskTab`, wired in `AppShellView`.

## Rendering

The desk renders as the rooms do (see `docs/home-variants.md`, Switching rooms): one RealityView,
mounted only once its tab is on screen (one mounted out of sight never draws), then kept. It steps
from a display-link `FrameClock` that pauses off screen. It is built in code from the styled rooms'
`GenzKit`, so meshes and materials are shared with them. The glow is a SwiftUI layer in screen
blend over the scene, at the lamps projected from the camera.

The shop keeps no renderer: its stills are drawn one at a time by one off-screen
`RealityRenderer`, which goes, with the models it loaded, a few seconds after the last one.
