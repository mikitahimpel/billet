# Design system

One look for the whole app: native iOS 26 with a warm honey accent. Everything below lives in the Swift
package `packages/ios/design` (module `Design`); `Settings → Labs → Style` draws it on a device. Read this
before writing or changing any SwiftUI under `apps/ios` or `packages/ios`.

`docs/design.md` is the old Little House design and does not describe the app.

## Rules

1. **No raw colours or fonts in feature code.** Colours are `Ink.*` and `Color.honey`; type is the
   `.ourio*` text styles. `Color(hex:)` is for art (scenes, icons' own tints), never for UI chrome. CI fails on a
   new `Color(red:` or `.font(.system(size:` outside the package (`packages/ios/scripts/check-design.mjs`).
2. **One sheet scaffold:** `BilletSheet`. No hand-built headers, no `NavigationStack` + `toolbar` of your own for a sheet.
3. **Close and confirm have one place, drawn by the system.** `BilletSheet` puts them in the native toolbar
   (`.cancellationAction` / `.confirmationAction`), so iOS 26 draws the Liquid Glass buttons, the tinted confirm
   and the hit areas. A sheet that confirms something (edit, add, compose) has `xmark` leading and the honey
   `checkmark` trailing; an informational sheet has only `xmark`, trailing. Pushed screens get the system back
   chevron. Never "Done" or "Cancel" text, never a hand-drawn circle. With `hasChanges:` confirm stays disabled
   until something changed, closing asks "Discard changes?" and a swipe down is blocked meanwhile. A count under
   the title is `subtitle:`, in the same slot.
4. **One card, one inset.** Cards and grouped sections are `cardSurface()` at `Radius.card`
   ([cards-v2.md](design/cards-v2.md): an opaque fill lit from above, a 1 pt highlight edge, one pre-rendered
   shadow), padded by
   `CardMetrics.padding` (`check-design.mjs` fails on a `.cardSurface()` padded by anything else on every side); screens and sheets keep `Space.gutter` (20) at the sides, 16 over the room. A card that opens
   something starts with `CardHeader`. The surface's gradient, edge and shadow are the package's; feature code adds
   none of its own, and a card with its own fill takes `.cardShadow()`. One `warm` card per screen. No blur or
   material on a card.
5. **One shape language** (see [Shape](#shape)): corners come from `Radius`, fields from `Field`, and nothing in
   feature code writes a radius as a number. CI fails on a new one (`check-design.mjs`, `radius-baseline.json`).
6. **One primary action per screen:** `PrimaryButton`, honey, full width. Next to it `SecondaryButton`. A
   disabled button is flat (`Ink.disabledFill`, no border, no honey) and its label `Ink.disabledText` stays
   4.5:1; never fade a button yourself.
7. **Glass is for chrome that floats:** header buttons, the tab bar, the toolbar of a full-screen canvas. Never glass
   on glass, never glass behind reading text, and not on every card of a scrolling list.
8. **Spacing comes from `Space`**, sizes from `Size` (`Size.control` = 44 is the height of every header control).
   A padding or spacing written as a number, a `.buttonStyle(.plain)` (no pressed state) and a system text style
   (`.font(.title)`) are counted per file by `check-design.mjs`; the counts only go down.
9. Numbers that change get `.monospacedDigit()`; animate them with `.contentTransition(.numericText())` only
   while the value changes.
10. Text on honey is `Ink.heroInk`; white on honey is unreadable.
11. **One glass, three roles** (below): every floating surface is `glass(_:role:)` or `accentGlass()`, tinted
    `Ink.glassFill` with `Ink.glassGlyph`, never white on clear glass: both adapt to the theme and pass 4.5:1 over
    the dark room, a bright room and the city. The coin has a dark ring so it never melts into honey.
12. **Icon tiles are `RowIcon`, in two styles.** `.clay` is the mark of a card, a tile or an empty state: a
    rounded tile filled with its tint, the glyph in the tint's deep shade. `.well` is a row's quiet mark: the
    glyph on the tint at 20%. No tint is the accent; destructive is `Ink.destructive` only. A list of rows stays
    quiet, so a screen never shows more than a few clay tiles.
13. **Switches, not tabs.** Toggles are `.toggleStyle(.switch)` with the honey tint. No segmented control in
    content; `GlassSegmented` is only the Living room | Bedroom switch. The Shop's category row is navigation, not a
    switch: pinned `FilterChip`s with an icon each.
14. **Scroll edges are soft.** Every scroll view fades out under bars, the header and the tab bar with
    `.softScrollEdges()` (iOS 26 scroll edge effect, the same at the top and the bottom); `Page` and
    `BilletSheet` already apply it. Before iOS 26 Home's bars draw the fade themselves. Never a hard edge: the
    glass is tinted enough that nothing ghosts through it. Chips, a search field or a subtitle pinned over a
    sheet's list go in `.scrollHeader { }`, which pins them over the scroll view so the rows fade under them on
    the sheet's ground instead of being cut at their edge. `check-design.mjs` fails on a scroll view without
    either in a file on the design package, and on any `.hard` edge. In an opaque sheet the fade alone lets text
    show behind the title, so `Page` and `BilletSheet` also lay the sheet's ground under its bar and fade it out
    just below; a `List` in a sheet adds `.sheetBarBacking()` under its `.scrollHeader`.
15. **A horizontal drag on the scene never switches rooms.** The room is changed only by the explicit control;
    drags belong to the cat, the camera and the laser.
16. **Contrast is tested.** `ContrastTests` computes the Ink pairs from `Palette` for light and dark; a new
    pair of colours gets a test there.

## Which component, when

| Need | Use |
| --- | --- |
| A sheet | `BilletSheet("Title", size:, onConfirm:) { content }` |
| A tab's root (World, Moments, Shop, Us) | `TabPage { ... }`, or `.tabContentInsets()` on its own scroll view; no title of its own, the tab bar names it. A tab's switch (Living room \| Bedroom, Photos \| Board) is a `GlassSegmented` in the header's `below` slot, the same size and place on every tab |
| A pushed or full screen of sections | `Page { ... }` |
| A full screen with a main action | `Screen { content } primary: { } secondary: { }`; over art or a camera `.bottomActions(primary:secondary:)`; under a fixed header `ActionSlot` |
| Rows in a settings-like list | `GroupedSection(header:footer:) { Row ... }` |
| A row | `Row(title, detail:, symbol:, tint:) { trailing }`, `ToggleRow`, `PickerRow`, `RowChevron` |
| Any other content on a card | `Card { ... }` or `.cardSurface()`; `state: .selected / .disabled` for a card that is chosen or can't be |
| A state read at a glance that a tap acts on (the cat's needs) | `StatusRow(title, state:, symbol:, tint:, emphasis:, action:) { }` in `GroupedSection(inset: StatusRow.inset)`; `note:` instead of `action:` when nothing can be done. The state is a word, never a bar or a percentage (VoiceOver gets the number through `value:`); only a state that wants something now is `.raised` |
| What an avatar or a round control wants, while it matters | `SymbolBadge(symbol:tint:)` at its top trailing corner; nothing when nothing is wanted |
| A card with a title, a state and actions | `ContentCard(title, subtitle:, chip:) { content } actions: { }`; its buttons sit in an `ActionRow` |
| Text with one action beside it on a card (a bundle, a bonus) | `CardActions { text } trail: { action }` |
| A shelf of things to open or buy | `ItemGrid { ItemCard(name, subtitle:, tag:, open:) { art } leadingBadge: trailingBadge: footer: }`; `tag: ItemTag(title, color:)` is its kind (a rarity) as a dot and a word |
| A picture or tile clipped to the scale | `.corners(.card / .inner / .control)`, a tile's fill `.cornerFill(.inner, style)` |
| The top of a card | `CardHeader(title, detail:, symbol:, tint:)`, or with `leading:` / `detail:` / `trailing:` views; art goes in `CardArt` |
| A text field | `Field(placeholder, text:, axis:, lines:, font:, failed:)` |
| A labelled field with its error or footnote | `FormField(label, placeholder:, text:, footer:, error:)` |
| A control that is not a `TextField` but sits with fields (a search bar with an icon, a picker or toggle row in an editor) | `.fieldSurface()` |
| The main action | `PrimaryButton` (or `PrimaryButtonStyle` on a custom label) |
| A quieter action | `SecondaryButton` |
| On or off (Love, Pin to wall), or one of a row of choices | `ToggleButtonStyle(isOn:tint:)` |
| A whole row that opens something | `RowButtonStyle()`: the row lights up while pressed; a card or tile takes `PressScaleStyle()` |
| Try a failed load or send again | `RetryButton` under an `EmptyState` or in a card; `RetryButton(compact: true)` in a row |
| A round control in a header | `GlassIconButton(symbol:label:badge:action:)` |
| Any other surface that floats | `glass(_:role:)` inside the bar's `GlassGroup`; the main action `accentGlass()` |
| A badge on glass | `glassBadge(_:)` |
| Nothing here yet | `EmptyState`, sized to its content |
| A load that failed, in place of the content | `ErrorState(title, text:) { retry }`, with the one `RetryButton` |
| Chips or a search field over a sheet's list | `.scrollHeader { ... }` on the list's `ScrollView` (`BilletSheet(scrolls: false)`) |
| The title of a block | `SectionHeader` |
| A tag: rarity, discount, count | `Chip(style: .tinted / .honey / .quiet)` |
| A filter or category | `FilterChip` |
| A price in coins | `PriceButton(price, was:)`; a deal's old price sits inside it |
| A small action inside a card or toast (Place, Undo) | `PillButton(title, symbol:)`, 36 pt tall with a 44 pt tap area, the price tag's height |
| A passing confirmation over the screen | `Toast { }`: card surface and padding, above the tab bar with `Space.m` to spare |
| A first-run hint on a control | `.hint(tip, arrowEdge:, target:)`: a popover in the card style, with a ring on the target |
| The same card outside TipKit | `Callout(symbol:title:message:close:)` on `.calloutBubble(pointer:)` |
| A note's stamp and seal | `PostageStamp`, `WaxSeal`, or `.postage(stamp:seal:width:postmark:)` on the note's face |
| A screen's few big actions side by side | `ActionTiles([ActionTile(title, status:, symbol:, tint:) {}])`: equal squares while every label fits on one line, a `GroupedSection` of rows otherwise |
| A progress toward one goal, in a hero | `ProgressRing(value:tint:) { centre }` |
| Something to open on a shelf that scrolls sideways, with art | `PosterCard(title, status:, emphasis:, action:) { PosterScene(tone:framing:hero:prop:) }`, the title on a paper ribbon over the art, three fifths of the width each (`containerRelativeFrame(count: 5, span: 3)`), stacked at accessibility sizes |
| A stamp on its own | `PostageStamp(_:size:rare:postmark:pinned:)`: `.small` in a control, `.regular` in a row, `.large` alone; `pinned` in a row, `postmark` once sent |

### Do and don't

- Do give a sheet exactly one size: `.fit` for a few controls, `.medium` or `.large` for lists.
- Do put an empty state in `.fit`, not in a large sheet.
- Do mark a page pushed from a `.fit` sheet with `.expandsSheet()`, so the sheet rises to full height for it.
- Do keep the toolbar to close or confirm.
- Don't draw an `xmark` yourself, or add a `Button("Done")`.
- Don't put `ContentUnavailableView` in a large sheet; it fills the space.
- Don't force `.colorScheme(.light)` on a card to make it pop; use `Ink.surface`.
- Don't write a radius as a number, or pick one by eye; see [Shape](#shape).
- Don't draw a field with `TextField` + `.background(...)`; use `Field` or `.fieldSurface()`.
- Don't make a "Try again" `Button` of your own; `check-design.mjs` fails on one (`retry-baseline.json`).
- Don't stack chips or a field above a sheet's `ScrollView` in a `VStack`; the rows cut hard under them. Use
  `.scrollHeader`.
- Don't make two sizes of header control; the avatars, the glass buttons and the coin pill are all 44 pt.
- Don't label a button with a bare symbol outside a toolbar: its tap area is the glyph. Frame the label
  `Size.control` square with `.contentShape(.rect)`, or use `GlassIconButton` (check-design fails otherwise).
- Don't show a mood as an emoji. `MoodArt(mood:size:)` (`apps/ios/Shared/Mood`) draws its clay cat face from
  `Moods.xcassets`, and the plain face when there is no mood; the words beside it carry the label.

## How to build a screen

Feature code (`apps/ios/Nooki`, `packages/ios/features`) is assembled from the package; it never draws its own
corners, gaps, heights, shadows or type. Start from one of these three and fill the slots.

**1. A full screen with a main action** (onboarding pages, a pairing step, a paywall-like explainer):

```swift
Screen {
    SectionHeader("Name your cat")
    FormField("Name", placeholder: "Mochi", text: $name, error: nameError)
} primary: {
    PrimaryButton("Continue", action: next)
} secondary: {
    SecondaryButton("Skip for now", action: skip)
}
```

The primary is always last, `Space.s` over the safe area, at the same height on every page; the content scrolls
under it at any text size. A page whose content is art or a camera keeps its own layout and adds
`.bottomActions(primary:secondary:)` for the same slot.

**2. A list of cards** (Us, the Shop's Today, a settings-like page): `Page { ... }` or `BilletSheet`, then

```swift
ContentCard("Weekend in Lisbon", subtitle: "Saved by both of you", chip: Chip("Plan", style: .honey)) {
    SecondaryButton("Edit", fullWidth: false, action: edit)
    PrimaryButton("Book it", fullWidth: false, action: book)
}
Card { CardActions { title } trail: { PriceButton(price, action: buy) } }
GroupedSection(header: "Notifications") { ToggleRow(...); Row(...) { RowChevron() } }
```

`ActionRow` (inside `ContentCard`) puts buttons side by side while they fit and stacks them, full width,
when they don't; `CardActions` keeps one trailing action at its own size beside text that wraps.

**3. A grid of things** (shop shelves, a collection):

```swift
ItemGrid {
    ForEach(items) { item in
        ItemCard(item.name, subtitle: item.blurb, open: { open(item) }) {
            art(item)
        } leadingBadge: { item.rarity.chip } trailingBadge: { dealChip(item) } footer: {
            BuyButton(...)
        }
    }
}
```

Columns are equal and `Space.m` apart, every tile in a row has the row's height so the footers line up, badges
stack instead of covering each other, and at accessibility sizes the grid is one column.

Loading, empty and failed states are `EmptyState` and `ErrorState` (with the one `RetryButton`); a message that
floats is `Toast`; a hint is `.hint(tip, arrowEdge:, target:)`, and the same card outside TipKit is `Callout`
on `.calloutBubble(pointer:)`.

## Enforcement

- `packages/ios/scripts/check-design.mjs` (CI, `ios:format:check`) runs the rules in `design-rules.mjs` over
  feature code: raw colours, non-`.ourio` fonts, numeric paddings and heights, hand-made corners, shadows,
  blurs and materials, `GeometryReader`, system or plain button styles, TipKit without the Hint style, and Text
  without a text style. Each file may keep at most its count in `packages/ios/design/lint/baseline.json`, which
  only shrinks (`node packages/ios/scripts/check-design.mjs --update` lowers it after a cleanup, never raises it).
  `lint/allow.json` exempts a path from one rule and grows only together with a change to the design package.
  Every rule has a failing and a passing fixture (`packages/ios/scripts/fixtures/design`).
- `scripts/check-ui.sh` is the pre-merge check for a UI pull request: the rules against main, their fixtures,
  swift-format. `scripts/gallery.sh` draws every component and the key screens at the SE and Pro Max sizes and
  at the largest text size and compares them with the WebP references in `packages/ios/design/Tests/Gallery`;
  `--record` takes a new drawing as the reference after a deliberate change.

## Never

- A number for a padding, a gap, a height, a corner or a font size in feature code.
- `Color(...)`, `.white`, `.black` or a system colour for UI; `.font(.system...)`, `.headline` and friends.
- `RoundedRectangle`, `.cornerRadius`, `.clipShape(.rect(cornerRadius:))`: use `Card`, `.cardSurface()`,
  `.corners(_:)`.
- `.shadow`, `.blur`, a `Material`, `.glassEffect` of your own (`Toast` and `glass(_:role:)` have theirs);
  `GeometryReader` for layout.
- `.buttonStyle(.plain / .bordered / .borderedProminent)` on a visible button; a hand-made toast, hint or
  "Try again".
- A CTA anywhere but the bottom slot of `Screen` on a full screen, and two buttons squeezed into one row.

## Tokens

| Token | Use |
| --- | --- |
| `Ink.screen`, `Ink.surface`, `Ink.surfaceRaised`, `Ink.separator` | backgrounds and hairlines, adaptive |
| `Ink.cardFill`, `.honeyFace` | the card's own gradient and a honey button's lit face; feature code reaches them through `cardSurface()` and the buttons |
| `Ink.text`, `.textSecondary`, `.textTertiary`, `.accentText` | text, adaptive |
| `Ink.glassFill`, `.glassGlyph`, `.glassGlyphSecondary`, `.glassRim`, `.glassSelection` | the glass roles, adaptive |
| `Ink.disabledFill`, `.disabledText`, `.destructive` | disabled buttons, destructive text and tiles |
| `Ink.primary`, `.secondary`, `.glassTint` | white on the dark full-screen canvas's warm glass only |
| `Color.honey`, `.honeyDeep`, `.blushPink` | accent fills; blush is love and hearts only |
| `.ourioLargeTitle` `.ourioTitle` `.ourioValue` `.ourioHeadline` `.ourioBody` `.ourioCallout` `.ourioCaption` `.ourioMicro` | text styles; `ourioMicro` is 12 pt, the smallest text in the app |
| `Space.xs…xl`, `Space.gutter`, `CardMetrics.padding`, `Radius.*`, `Size.*` | spacing, corners, sizes |
| `Motion.*` | every animation, see Motion |

Over the room use the glass roles; elsewhere solid surfaces. Nothing in the app is red for the cat or the couple.

## Glass

Every piece of glass in the app's chrome is one of these. `Tokens/Glass.swift` holds them.

| Role | Where | Glass | Tint | Rim | Shadow | Ink |
| --- | --- | --- | --- | --- | --- | --- |
| `control` | header buttons, coin pill, the pet, a sheet's close over a canvas | regular, interactive | `Ink.glassFill` | 1 pt `Ink.glassRim` | the system's own | `Ink.glassGlyph` |
| `bar` | tab bar, Living room \| Bedroom switch, a label over the scene | regular | `Ink.glassFill` | 1 pt `Ink.glassRim` | the system's own | `glassGlyph`; unselected `glassGlyphSecondary`; selected on `Ink.glassSelection` |
| accent | the "+" beside the tab bar | prominent, interactive | honey | the system's own | the system's own | `Ink.heroInk` |
| badge | counts, Lv., heart and crown, the partner's mood | none, solid | honey, blush or `Ink.surface` | 1.5 pt `Ink.glassFill` | none | `Ink.heroInk` |

- **One container per bar.** The header (with the World's room switch under it) is one `GlassGroup`, the tab
  bar and the "+" another. Every group blends at `GlassMetrics.blend` and every row keeps `GlassMetrics.gap`,
  so neighbours morph when they appear and never merge at rest.
- **No shadows of our own on glass.** The system casts one; another is a blur pass over a backdrop that
  changes every frame. The avatars beside the glass take the badge ring, `Ink.glassFill`, and no shadow.
- **Reduce Transparency** draws a role solid on `Ink.surface` with the same rim; the system frosts the native
  glass (sheet close and confirm, the accent) itself.
- **Sheets' close and confirm** are the system's toolbar glass (`BilletSheet`), not a role.
- **The perf arms** (`-perf.hud opaque|flat`) replace a role by an opaque or flat `Ink.surface`; they keep the
  rim, so only the glass changes.
- The two-argument `glass(_:tint:clear:interactive:)` and `warmGlass` are for art inside content and the dark
  full-screen canvas only; chrome never uses them.

## Shape

One corner scale, and corners are concentric: a shape nested in another, inset by `p`, has the outer radius minus
`p`, so the gap between them is even all round. The values live in `Metrics.swift` and `MetricsTests` holds the
relations, so a redesign changes a token, not the screens.

| Token | Value | Use |
| --- | --- | --- |
| `Radius.sheet` | `card + Space.gutter` | the system sheet's corner, which iOS draws; content at the gutter is a `card` |
| `Radius.card` | 28 | every card, grouped section, tile, panel and large picture on a screen or sheet |
| `Radius.inner` | `card − CardMetrics.padding` | what sits inside a card's padding: thumbnails, posters, peeks, small grid tiles |
| `Radius.control` | `Size.button / 2` | every text field and choice row: a one-line field is the buttons' capsule |

- Buttons, chips, pills and price tags are capsules (`PrimaryButton`, `SecondaryButton`, `Chip`, `PriceButton`).
  A `Field` has their height and, at one line, their shape; a taller one keeps the round ends.
- A card is the container shape for what is inside it, so an iOS 26 `ConcentricRectangle` there follows its
  corners. Prefer `Radius.inner` where the inset is the card padding, which is why a card's content always
  sits at `CardMetrics.padding`: art in a tile padded tighter has corners squarer than the card's.
- One card family: `Card`, `CardMetrics.padding`, `CardHeader` with a `Size.cardMark` clay icon (`RowIcon`) or
  `CardArt`, the title in `.ourioHeadline` over a `.ourioCaption` line `Space.xxs` under it, a `RowChevron` when it opens something.
  The screen's hero differs only by `warm`.
- Art (paper, pens, gift boxes, window views, widgets) may keep its own drawn corners; those files are in
  `packages/ios/scripts/radius-baseline.json` and may only shrink.

## Motion

One scale, in `Tokens/Motion.swift`: two durations and one spring. Screens never pick a raw curve or time.

| Token | Value | Use |
| --- | --- | --- |
| `Motion.quick` | 0.2 s | a control's own change and a page swapped in place: the selection pill, a hover, a tab's page |
| `Motion.standard` | 0.35 s | a larger move that brings in something new: a panel, a card opening |
| `Motion.spring(_:)` | spring, bounce 0 | everything that moves; nothing overshoots |
| `Motion.fade(_:)` | ease-in-out opacity | a page swapped in place, what leaves, and everything under Reduce Motion |

- **A tab switch fades the page and nothing else.** The new page fades in over the old one on
  `Motion.fade()`; the header and the tab bar stay put and never animate as a whole (no `withAnimation`
  around `state.tab`).
- **The selection pill follows the finger.** One pill for the bar, moved by an offset: it slides on
  `Motion.spring(Motion.quick)` while the finger is on the bar and is already in place when the switch
  lands, so the switch's frames redraw no glass. A switch from elsewhere (a link, VoiceOver) moves it at once.
- **Opacity and drawn offsets only**, never a frame, a padding or a safe area: those lay the page out again
  on every frame of the animation. Nothing is inserted or removed inside glass to animate it.
- **Keep the switch's frame light.** It already builds the new page; state written in
  `onChange(of: state.tab)` runs Home's body a second time, so write only what changes the screen.
- **Reduce Motion fades.** The selection pill fades out of one tab and into the next instead of sliding.
- **The room comes and goes at once.** Leaving the World, its last frame fades out under the new page; coming
  back, the room mounts in the switch's frame under that last frame, which fades once the room has drawn.

## Previews

Every file of the package has a `#Preview` drawn in light and dark (`BothSchemes`). Pick an iPhone in the
Canvas. A sheet's preview draws its content inline, because the Canvas cannot show a presented sheet. The
`Catalog` preview shows the Ink colours, the type ramp, Space and Radius and every component on one screen, and
the header over a room-like backdrop.
