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
11. **Controls over the room or the city sit on `Ink.glassFill`** with `Ink.glassGlyph`, never white on clear
    glass: both adapt to the theme and pass 4.5:1 over the dark room, a bright room and the city. The coin has a
    dark ring so it never melts into honey.
12. **Icon tiles have one rule:** a full-tint glyph on the same tint at 16%, for every row. No tint is the
    accent (`Ink.accentText` glyph); destructive is `Ink.destructive` only.
13. **Switches, not tabs.** Toggles are `.toggleStyle(.switch)` with the honey tint. No segmented control in
    content; `GlassSegmented` is only the Room | City prototype.
14. **Scroll edges are soft.** Every scroll view fades out under bars, the header and the tab bar with
    `.softScrollEdges()` (iOS 26 scroll edge effect); `Page` and `BilletSheet` already apply it.
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

## Tokens

| Token | Use |
| --- | --- |
| `Ink.screen`, `Ink.surface`, `Ink.surfaceRaised`, `Ink.separator` | backgrounds and hairlines, adaptive |
| `Ink.text`, `.textSecondary`, `.textTertiary`, `.accentText` | text, adaptive |
| `Ink.glassFill`, `.glassGlyph`, `.glassGlyphSecondary` | controls over the room or city, adaptive |
| `Ink.disabledFill`, `.disabledText`, `.destructive` | disabled buttons, destructive text and tiles |
| `Ink.primary`, `.secondary`, `.glassTint` | white on dark scene glass only (labels on the room) |
| `Color.honey`, `.honeyDeep`, `.blushPink` | accent fills; blush is love and hearts only |
| `.nookiLargeTitle` `.nookiTitle` `.nookiHeadline` `.nookiBody` `.nookiCallout` `.nookiCaption` `.nookiMicro` | text styles |
| `Space.xs…xl`, `Space.gutter`, `CardMetrics.padding`, `Radius.*`, `Size.*` | spacing, corners, sizes |

Over the room use `warmGlass`; elsewhere solid surfaces. Nothing in the app is red for the cat or the couple.

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

## Previews

Every file of the package has a `#Preview` drawn in light and dark (`BothSchemes`). Pick an iPhone in the
Canvas. A sheet's preview draws its content inline, because the Canvas cannot show a presented sheet. The
`Catalog` preview shows the Ink colours, the type ramp, Space and Radius and every component on one screen, and
the header over a room-like backdrop.
