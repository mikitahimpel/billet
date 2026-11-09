# Design system

One look for the whole app: native iOS 26 with a warm honey accent. Everything below lives in the Swift
package `packages/ios/design` (module `Design`); `Settings → Labs → Style` draws it on a device. Read this
before writing or changing any SwiftUI under `apps/ios` or `packages/ios`.

`docs/design.md` is the old Little House design and does not describe the app.

## Rules

1. **No raw colours or fonts in feature code.** Colours are `Ink.*` and `Color.honey`; type is the
   `.nooki*` text styles. `Color(hex:)` is for art (scenes, icons' own tints), never for UI chrome. CI fails on a
   new `Color(red:` or `.font(.system(size:` outside the package (`packages/ios/scripts/check-design.mjs`).
2. **One sheet scaffold:** `BilletSheet`. No hand-built headers, no `NavigationStack` + `toolbar` of your own for a sheet.
3. **Close and confirm have one place, drawn by the system.** `BilletSheet` puts them in the native toolbar
   (`.cancellationAction` / `.confirmationAction`), so iOS 26 draws the Liquid Glass buttons, the tinted confirm
   and the hit areas. A sheet that confirms something (edit, add, compose) has `xmark` leading and the honey
   `checkmark` trailing; an informational sheet has only `xmark`, trailing. Pushed screens get the system back
   chevron. Never "Done" or "Cancel" text, never a hand-drawn circle. With `hasChanges:` confirm stays disabled
   until something changed, closing asks "Discard changes?" and a swipe down is blocked meanwhile. A count under
   the title is `subtitle:`, in the same slot.
4. **One card, one inset.** Cards and grouped sections use `Radius.card` on `Ink.surface`, padded by
   `CardMetrics.padding`; screens and sheets keep `Space.gutter` (20) at the sides, 16 over the room. A card that opens
   something starts with `CardHeader`. No gradients, rims or shadows on a card; the hero is only `warm`.
5. **One shape language** (see [Shape](#shape)): corners come from `Radius`, fields from `Field`, and nothing in
   feature code writes a radius as a number. CI fails on a new one (`check-design.mjs`, `radius-baseline.json`).
6. **One primary action per screen:** `PrimaryButton`, honey, full width. Next to it `SecondaryButton`. A
   disabled button is flat (`Ink.disabledFill`, no border, no honey) and its label `Ink.disabledText` stays
   4.5:1; never fade a button yourself.
7. **Glass is for chrome that floats:** header buttons, the tab bar, the toolbar of a full-screen canvas. Never glass
   on glass, never glass behind reading text, and not on every card of a scrolling list.
8. **Spacing comes from `Space`**, sizes from `Size` (`Size.control` = 44 is the height of every header control).
9. Numbers that change get `.monospacedDigit()`; animate them with `.contentTransition(.numericText())` only
   while the value changes.
10. Text on honey is `Ink.heroInk`; white on honey is unreadable.
11. **One glass, three roles** (below): every floating surface is `glass(_:role:)` or `accentGlass()`, tinted
    `Ink.glassFill` with `Ink.glassGlyph`, never white on clear glass: both adapt to the theme and pass 4.5:1 over
    the dark room, a bright room and the city. The coin has a dark ring so it never melts into honey.
12. **Icon tiles have one rule:** a full-tint glyph on the same tint at 16%, for every row. No tint is the
    accent (`Ink.accentText` glyph); destructive is `Ink.destructive` only.
13. **Switches, not tabs.** Toggles are `.toggleStyle(.switch)` with the honey tint. No segmented control in
    content; `GlassSegmented` is only the Room | City prototype.
14. **Scroll edges are soft.** Every scroll view fades out under bars, the header and the tab bar with
    `.softScrollEdges()` (iOS 26 scroll edge effect, the same at the top and the bottom); `Page` and
    `BilletSheet` already apply it. Before iOS 26 Home's bars draw the fade themselves. Never a hard edge: the
    glass is tinted enough that nothing ghosts through it. `check-design.mjs` fails on a tab's scroll view
    without it and on any `.hard` edge.
15. **A horizontal drag on the scene never switches rooms.** The room is changed only by the explicit control;
    drags belong to the cat, the camera and the laser.
16. **Contrast is tested.** `ContrastTests` computes the Ink pairs from `Palette` for light and dark; a new
    pair of colours gets a test there.

## Which component, when

| Need | Use |
| --- | --- |
| A sheet | `BilletSheet("Title", size:, onConfirm:) { content }` |
| A pushed or full screen of sections | `Page { ... }` |
| Rows in a settings-like list | `GroupedSection(header:footer:) { Row ... }` |
| A row | `Row(title, detail:, symbol:, tint:) { trailing }`, `ToggleRow`, `PickerRow`, `RowChevron` |
| Any other content on a card | `Card { ... }` or `.cardSurface()` |
| The top of a card | `CardHeader(title, detail:, symbol:, tint:)`, or with `leading:` / `detail:` / `trailing:` views; art goes in `CardArt` |
| A text field | `Field(placeholder, text:, axis:, lines:, font:, failed:)` |
| A control that is not a `TextField` but sits with fields (a search bar with an icon, a picker or toggle row in an editor) | `.fieldSurface()` |
| The main action | `PrimaryButton` (or `PrimaryButtonStyle` on a custom label) |
| A quieter action | `SecondaryButton` |
| A round control in a header | `GlassIconButton(symbol:label:badge:action:)` |
| Any other surface that floats | `glass(_:role:)` inside the bar's `GlassGroup`; the main action `accentGlass()` |
| A badge on glass | `glassBadge(_:)` |
| Nothing here yet | `EmptyState`, sized to its content |
| The title of a block | `SectionHeader` |
| A tag: rarity, discount, count | `Chip(style: .tinted / .honey / .quiet)` |
| A filter or category | `FilterChip` |
| A price in coins | `PriceButton(price, was:)`; a deal's old price sits inside it |
| A note's stamp and seal | `PostageStamp`, `WaxSeal`, or `.postage(stamp:seal:width:)` on the note's face |

### Do and don't

- Do give a sheet exactly one size: `.fit` for a few controls, `.medium` or `.large` for lists.
- Do put an empty state in `.fit`, not in a large sheet.
- Do keep the toolbar to close or confirm.
- Don't draw an `xmark` yourself, or add a `Button("Done")`.
- Don't put `ContentUnavailableView` in a large sheet; it fills the space.
- Don't force `.colorScheme(.light)` on a card to make it pop; use `Ink.surface`.
- Don't write a radius as a number, or pick one by eye; see [Shape](#shape).
- Don't draw a field with `TextField` + `.background(...)`; use `Field` or `.fieldSurface()`.
- Don't make two sizes of header control; the avatars, the glass buttons and the coin pill are all 44 pt.
- Don't show a mood as an emoji. `MoodArt(mood:size:)` (`apps/ios/Shared/Mood`) draws its clay cat face from
  `Moods.xcassets`, and the plain face when there is no mood; the words beside it carry the label.

## Tokens

| Token | Use |
| --- | --- |
| `Ink.screen`, `Ink.surface`, `Ink.surfaceRaised`, `Ink.separator` | backgrounds and hairlines, adaptive |
| `Ink.text`, `.textSecondary`, `.textTertiary`, `.accentText` | text, adaptive |
| `Ink.glassFill`, `.glassGlyph`, `.glassGlyphSecondary`, `.glassRim`, `.glassSelection` | the glass roles, adaptive |
| `Ink.disabledFill`, `.disabledText`, `.destructive` | disabled buttons, destructive text and tiles |
| `Ink.primary`, `.secondary`, `.glassTint` | white on the dark full-screen canvas's warm glass only |
| `Color.honey`, `.honeyDeep`, `.blushPink` | accent fills; blush is love and hearts only |
| `.nookiLargeTitle` `.nookiTitle` `.nookiHeadline` `.nookiBody` `.nookiCallout` `.nookiCaption` `.nookiMicro` | text styles |
| `Space.xs…xl`, `Space.gutter`, `CardMetrics.padding`, `Radius.*`, `Size.*` | spacing, corners, sizes |
| `Motion.*` | every animation, see Motion |

Over the room use the glass roles; elsewhere solid surfaces. Nothing in the app is red for the cat or the couple.

## Glass

Every piece of glass in the app's chrome is one of these. `Tokens/Glass.swift` holds them.

| Role | Where | Glass | Tint | Rim | Shadow | Ink |
| --- | --- | --- | --- | --- | --- | --- |
| `control` | header buttons, coin pill, the pet, a sheet's close over a canvas | regular, interactive | `Ink.glassFill` | 1 pt `Ink.glassRim` | the system's own | `Ink.glassGlyph` |
| `bar` | tab bar, Room \| City switch, a label over the scene | regular | `Ink.glassFill` | 1 pt `Ink.glassRim` | the system's own | `glassGlyph`; unselected `glassGlyphSecondary`; selected on `Ink.glassSelection` |
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
| `Radius.card` | 24 | every card, grouped section, tile, panel and large picture on a screen or sheet |
| `Radius.inner` | `card − CardMetrics.padding` | what sits inside a card's padding: thumbnails, posters, peeks, small grid tiles |
| `Radius.control` | `Size.button / 2` | every text field and choice row: a one-line field is the buttons' capsule |

- Buttons, chips, pills and price tags are capsules (`PrimaryButton`, `SecondaryButton`, `Chip`, `PriceButton`).
  A `Field` has their height and, at one line, their shape; a taller one keeps the round ends.
- A card is the container shape for what is inside it, so an iOS 26 `ConcentricRectangle` there follows its
  corners. Prefer `Radius.inner` where the inset is the card padding.
- One card family: `Card`, `CardMetrics.padding`, `CardHeader` with a `Size.cardMark` icon (`RowIcon`) or
  `CardArt`, the title in `.nookiHeadline` over a `.nookiCaption` line, a `RowChevron` when it opens something.
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
