# One system

**Clay holds the content. Glass holds the controls. Nothing else draws a surface.**

The app has two materials and each has one job. This page is the model; [design-system.md](../design-system.md)
is the component reference, [cards-v2.md](cards-v2.md) the clay's exact drawing, and
[audit-2026-11-11.md](audit-2026-11-11.md) where the app stands against it.

## The model

| | Clay | Glass |
| --- | --- | --- |
| What it is | our volumetric look: an opaque slab lit from above, a hairline of lamplight on its upper edge, one pre-rendered shadow | Apple's iOS 26 Liquid Glass, drawn by the system |
| What it holds | **content**: what the couple reads, owns, made or will do | **chrome**: what moves you around or acts on the screen |
| Where | cards, sections of rows, tiles, posters, a sheet's grouped sections, empty and failed states | the tab bar, the header's controls, the room switch, a sheet's close and confirm and its grabber, a canvas toolbar, the scroll edge |
| Moves with | the scroll | the screen; content passes under it |
| Costs | a gradient and a stretched texture; no blur, ever | the system's blur, the only blur in the app |
| Kit | `cardSurface()` and what is built on it | `glass(_:role:)` in a `GlassGroup`, `GlassSegmented`, `GlassIconButton`, the system toolbar |

The test for any new element: **does it scroll with the page?** Then it is content and it is clay (or it sits
on clay). Does it stay while the page moves? Then it is chrome and it is glass. A thing is never both, and
there is no third material: no flat fill, no material, no card with a blur, no glass card in a list.

One exception, on purpose: a `Toast` is clay. It floats, but it carries a sentence to read, and reading text
sits on an opaque surface (rule 7 of the design system: never glass behind reading text).

## Levels

A screen has four levels and no more. Each is drawn by exactly one thing.

| Level | Is | Drawn by | Never |
| --- | --- | --- | --- |
| 0 Ground | the screen's or sheet's own colour, `Ink.screen` | `TabPage`, `Page`, `Screen`, `BilletSheet` | a gradient or picture behind a list (the room is the only backdrop, on Home) |
| 1 Slab | a card or a section of rows | `cardSurface()` through `Card`, `ContentCard`, `GroupedSection`, `ItemCard`, `PosterCard`, `ActionTiles` | a slab on a slab |
| 2 Well | a recess in a slab: an art slot, a thumbnail's backdrop, an inset note | `.wellSurface()` | its own shadow or highlight; a well in a well |
| 3 Mark | what sits on a slab or in a well: a clay icon tile, a chip, a button, a picture | `RowIcon`, `Chip`, the buttons, `.corners(.inner)` on a picture | a fill behind a mark that is not one of these |

Above them all, **chrome**: glass, at the screen's edges, in at most two groups (the header and the tab bar).

The well is what replaces every "flat dark rounded rectangle inside a card". A slab is raised and lit from
above; a well is pressed in: one flat tone a step down from the slab's lit top (the kit's, opaque), a hairline of
shade on its upper edge where a slab has light, and no shadow. A picture in a well keeps the well's corners (`Radius.inner`), so no thumbnail has a hard
edge.

## Surfaces: which one

| The content is | Use | Not |
| --- | --- | --- |
| one thing with a title, a state, actions | `ContentCard`, or `Card` + `CardHeader` | a `VStack` with `.cornerFill(.card, …)` |
| several like rows (settings, a day of the Inbox, a wishlist's facts, upcoming dates) | `GroupedSection { Row … }`: every row on one slab, hairlines between | a `List` with `.listRowBackground`; one card per row when the rows are one list; a hand-made `Rectangle` hairline |
| several unlike things, each opened on its own | one card each, `Space.m` apart | a section |
| a thing to own or open, with art | `ItemGrid { ItemCard }` | a tile with its own fill and corners |
| something to open on a sideways shelf | `PosterCard` | a photo with text over it |
| the screen's one hero | `Card(warm: true)`, once per screen | a second warm card; a honey fill of your own |
| a state at a glance that a tap acts on | `StatusRow` in a `GroupedSection` | a progress bar per row |
| art, a slot or a thumbnail inside a card | `.wellSurface()`, the picture inside it | `Ink.surfaceRaised`, `.cornerFill(.inner, …)` |
| a card over a dimmed screen (a match, a reward) | `cardSurface()` on the scrim; the scrim separates it | a live `.shadow`; a taller shadow of your own |
| nothing yet, or a load that failed | `EmptyState`, `ErrorState` on the ground | an empty card |
| a passing confirmation | `Toast` | a hand-made capsule |
| a first-run hint | `.hint(…)`, `Callout` | `popoverTip` |

Rows versus cards, the question the audit kept meeting: rows that are **the same kind of thing in one list**
share a slab; things that are **each their own object** (a wish with a photo and actions, a planned date)
get a card each. A calendar's upcoming dates are rows of one list, so they are one section, not twelve cards.

## Chrome: which one

| The control | Use | Not |
| --- | --- | --- |
| the tabs and the "+" | the tab bar's `GlassGroup`; `accentGlass()` for the "+" | |
| a header's round control, the coin pill, the avatars | `GlassIconButton`, `glass(.control)`, in the header's `GlassGroup`, all `Size.control` | two sizes of control |
| a switch between two views of one tab (Living room \| Bedroom, Photos \| Board) | `GlassSegmented` in the header's `below` slot | a segmented control in content |
| a sheet's close and confirm | `BilletSheet`: the system toolbar draws them | an `xmark` of your own, "Done" |
| a pushed screen's back | the system's chevron | |
| a filter or category over a list | `FilterChip`s in `.scrollHeader { }` | chips stacked over a `ScrollView` |
| the tools of a full-screen canvas | `glass(.control)` in one `GlassGroup` | `warmGlass` on a sheet |
| where content meets a bar | the system scroll edge effect, soft, through `.ourioScrollEdges()` (it replaces `.softScrollEdges()`); the scaffolds apply it | a hard edge, a gradient mask or a blur of your own |
| a round control on content, not over a scene (add to a list, next photo) | `IconButton(symbol:label:style:)`: clay, opaque | glass; a `Circle().fill(…)` |

Large titles are not used. A tab's name is its tab bar item; a sheet's title is the toolbar's inline title;
a section's is `SectionHeader`.

Glass never sits on a card, and a card never sits under a bar's group at rest: a scaffold starts its content
below the bar (`TabPage`, `.tabContentInsets()`, `BilletSheet`), and the scroll edge effect softens what
passes under it. A header that floats over rows with nothing behind it (the Calendar's chips, the Inbox's
"Today") is this rule broken: the chips belong in `.scrollHeader`, the day's title in the section's header.

## One scale

**Corners.** Four, concentric, from `Radius`; `MetricsTests` holds the relations.

| | Value | For |
| --- | --- | --- |
| `Radius.sheet` | 48 | the system's sheet |
| `Radius.card` | 28 | every slab: card, section, tile, poster |
| `Radius.inner` | 12 | every well and picture inside a slab's padding |
| capsule | height / 2 | every button, chip, pill, price, one-line field |

A clay icon tile is a squircle at 0.32 of its side. Nothing else has a corner; a number for a radius does not
compile past the lint.

**Type.** Seven roles; a card uses at most four of them.

| Role | Style | Ink |
| --- | --- | --- |
| Hero number | `.ourioHeroDigits` | `text` |
| Value | `.ourioValue` | `text` |
| Title | `.ourioHeadline`; a sheet's or screen's own `.ourioTitle` | `text` |
| Body, a row's title | `.ourioBody` | `text` |
| Status | `.ourioCallout` | `textSecondary`; `accentText` when it asks for something |
| Meta | `.ourioCaption` | `textSecondary` |
| Micro | `.ourioMicro`, 12 pt, the floor | on its chip |

Weights belong to the styles: no `.weight(.semibold)` on a style to make a seventh role. Numbers that change
are `.monospacedDigit()`.

**Space.** `Space` only: 2, 4, 8, 12, 16, 20, 24, 32.

| Gap | Token |
| --- | --- |
| screen and sheet side | `Space.gutter` (16 over the room: `TabMetrics.side`) |
| inside a slab, every side | `CardMetrics.padding` |
| inside a well | `Space.s` |
| mark to words | `Space.m` |
| title to its meta line | `Space.xxs` |
| blocks in a slab; slabs in a list | `Space.m` |
| a header over its section | `Space.s` |
| between sections | `Space.section`; `Space.xl` before a new topic |

**Icons.** SF Symbols, one weight (semibold), always in a tile, never loose beside a title.

| Where | Style | Size |
| --- | --- | --- |
| the mark of a card, an empty state | `RowIcon(style: .clay)` | `Size.cardMark` 44, 64 in an empty state |
| the mark of a tile | `.clay` | `Size.tileMark` 36 |
| a row in a list | `.well` | 34 |
| in glass | `GlassSymbol` | the control's |

A screen shows a few clay tiles and its lists stay quiet. Tints are the object's own (a date is sky, love is
blush); honey is the accent and is not spent on an icon that is not the action. Mood is `MoodArt`, never an
emoji.

**Colour.** `Ink` and `Color.honey` only. Honey marks one thing per screen: the primary action, or the
selected card's ring. Blush is love. Red is destructive text and nothing else.

## States

| State | Slab | Row | Control |
| --- | --- | --- | --- |
| Rest | fill, lit edge, shadow | on its section | |
| Pressed | `PressScaleStyle`: 0.97, 6% darker | `RowButtonStyle`: the row lights | the button styles' own |
| Selected | the lit edge becomes a 2 pt honey ring; nothing else | a checkmark, trailing | `ToggleButtonStyle(isOn:)`, a `FilterChip`'s fill |
| Disabled | flat `Ink.disabledFill`, no edge, no shadow | `Ink.disabledText` | flat, 4.5:1 label |
| Loading | `LoadingState` in place of the content; a slab never shimmers | | the button's own progress |
| Empty | `EmptyState` on the ground, the sheet at `.fit` | | |
| Failed | `ErrorState` with the one `RetryButton` | `RetryButton(compact: true)` | `ErrorLine` under a field |
| New | a blush dot, trailing | the same | a `glassBadge` |

Selected is always the honey ring and only the honey ring, so rarity, deals and ownership never use a ring.

## Motion

- Curves and times are `Motion.quick`, `Motion.standard`, `Motion.spring(_:)`, `Motion.fade(_:)`. A raw
  `.snappy`, `.spring(duration:)` or `.easeInOut` in feature code is a debt.
- Clay does not move at rest: no `repeatForever`, no `TimelineView` on a card, a row or a sheet. The room and
  the cat are where the app is alive.
- A screen has one orchestrated moment at most (a purchase, a match, a reward), and it is a state change.
  Settings, lists and forms have none beyond a pressed state.
- Glass does not animate as a whole; nothing is inserted into or removed from a `GlassGroup` to animate it.
- Opacity and drawn offsets only; never a frame, a padding or a safe area.
- Reduce Motion: every move becomes `Motion.fade`.

## Looks

`Look.classic` (cream, honey, SF Rounded) and `Look.dusk` (warm night, amber, Bricolage Grotesque) are two
palettes and two display faces for the **same** model. A look changes `Palette`'s tones, the display face and
what the kit already reads from `Look.current` (the accent face, the selection rim, an icon tile's shaping). A
look never changes which component a screen uses, a radius, a gap or a level. So feature code never reads
`Look.current`; if a screen needs to, the token is missing from the kit. `ContrastTests` holds every ink pair
for each look in light and dark: body text 4.5:1 on a slab's lightest stop and in a well.

## Performance and access

- No blur, material or live shadow on content. The system's bars and scroll edge are the only blur.
- A slab's shadow is the kit's stretched texture. A `.shadow(` in feature code is a blur pass per frame.
- No text under 12 pt (`.ourioMicro`).
- Every tap target is `Size.control` or larger; a symbol button has a VoiceOver label.
- At accessibility sizes a row stacks (the kit's `Row`, `SectionHeader`, `ItemGrid`, `ActionRow` already
  do); a hand-made `HStack` row does not, which is one more reason there are none.
- A state is a word, with the number given to VoiceOver as its value.

## Never

- A fill of your own on content: `.cornerFill`, `.background(Ink.surface…)`, `Ink.surfaceRaised`,
  `.listRowBackground`, `Circle().fill`, a `Capsule().fill` that is not a kit button or chip.
- A stroke, shadow, corner, blur, material or `.glassEffect` in feature code.
- A slab inside a slab. Inside a slab there are wells and marks.
- Glass on content, glass on glass, glass behind reading text.
- A `List` for content. Rows are `Row`s in a `GroupedSection`.
- A second kit: a row, card, chip, icon tile or progress bar defined in `apps/ios` or a feature package.
- A header, chips or a title floating over scrolling rows without `.scrollHeader`.
- A large title; a segmented control in content; "Done" or "Cancel" as text.
- Two warm cards, two primary buttons or two honey things on one screen.
- An animation at rest on a card, a row or a sheet; a raw curve.
- `Look.current` in feature code.

## Enforcement

The kit is the only easy way, and the lint is the only door.

| Rule | Fails on | Since |
| --- | --- | --- |
| `corner-shape`, `shadow`, `blur-material`, `raw-color`, `raw-font`, `padding-literal`, `frame-literal`, `button-style`, `text-role`, `geometry-reader`, `tip` | see [design-system.md](../design-system.md#enforcement) | before |
| `flat-surface` | `.cornerFill(`, `Ink.surface`, `Ink.surfaceRaised`, `.listRowBackground(` in feature code | this system |
| `raw-stroke` | `.stroke(`, `.strokeBorder(` in feature code | this system |

Every rule has a baseline per file in `packages/ios/design/lint/baseline.json` that may only shrink. A
migrated area ends at zero for `flat-surface`, `raw-stroke`, `corner-shape` and `shadow`; art files keep
their counts until their chrome is migrated, and nothing new may be added to them. Next, in this order: a
`raw-motion` rule for curves, a `content-list` rule for `List`, and moving the app-side kits
(`Us/ListRow.swift`, `Us/ListCard.swift`, `UsKit.swift`'s `UsIcon`, `Kit/ProgressCapsule.swift`,
`ShopKit.swift`'s `OwnedCheck`) into the package or onto its components.
