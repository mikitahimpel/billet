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
4. **One card, one inset.** Cards and grouped sections use `Radius.card` on `Ink.surface`; screens and sheets keep
   `Space.gutter` (20) at the sides, 16 over the room. No gradients, rims or shadows on a card.
5. **One primary action per screen:** `PrimaryButton`, honey, full width. Next to it `SecondaryButton`. A
   disabled button is flat (`Ink.disabledFill`, no border, no honey) and its label `Ink.disabledText` stays
   4.5:1; never fade a button yourself.
6. **Glass is for chrome that floats:** header buttons, the tab bar, the toolbar of a full-screen canvas. Never glass
   on glass, never glass behind reading text, and not on every card of a scrolling list.
7. **Spacing comes from `Space`**, sizes from `Size` (`Size.control` = 44 is the height of every header control).
8. Numbers that change get `.monospacedDigit()`; animate them with `.contentTransition(.numericText())` only
   while the value changes.
9. Text on honey is `Ink.heroInk`; white on honey is unreadable.
10. **Controls over the room or the city sit on `Ink.glassFill`** with `Ink.glassGlyph`, never white on clear
    glass: both adapt to the theme and pass 4.5:1 over the dark room, a bright room and the city. The coin has a
    dark ring so it never melts into honey.
11. **Icon tiles have one rule:** a full-tint glyph on the same tint at 16%, for every row. No tint is the
    accent (`Ink.accentText` glyph); destructive is `Ink.destructive` only.
12. **Switches, not tabs.** Toggles are `.toggleStyle(.switch)` with the honey tint. No segmented control in
    content; `GlassSegmented` is only the Room | City prototype.
13. **Scroll edges are soft.** Every scroll view fades out under bars, the header and the tab bar with
    `.softScrollEdges()` (iOS 26 scroll edge effect); `Page` and `BilletSheet` already apply it.
14. **A horizontal drag on the scene never switches rooms.** The room is changed only by the explicit control;
    drags belong to the cat, the camera and the laser.
15. **Contrast is tested.** `ContrastTests` computes the Ink pairs from `Palette` for light and dark; a new
    pair of colours gets a test there.

## Which component, when

| Need | Use |
| --- | --- |
| A sheet | `BilletSheet("Title", size:, onConfirm:) { content }` |
| A pushed or full screen of sections | `Page { ... }` |
| Rows in a settings-like list | `GroupedSection(header:footer:) { Row ... }` |
| A row | `Row(title, detail:, symbol:, tint:) { trailing }`, `ToggleRow`, `PickerRow`, `RowChevron` |
| Any other content on a card | `Card { ... }` or `.cardSurface()` |
| The main action | `PrimaryButton` (or `PrimaryButtonStyle` on a custom label) |
| A quieter action | `SecondaryButton` |
| A round control in a header | `GlassIconButton(symbol:label:badge:action:)` |
| Nothing here yet | `EmptyState`, sized to its content |
| The title of a block | `SectionHeader` |
| A tag: rarity, discount, count | `Chip(style: .tinted / .honey / .quiet)` |
| A filter or category | `FilterChip` |
| A price in coins | `PriceButton(price, was:)`; a deal's old price sits inside it |

### Do and don't

- Do give a sheet exactly one size: `.fit` for a few controls, `.medium` or `.large` for lists.
- Do put an empty state in `.fit`, not in a large sheet.
- Do keep the toolbar to close or confirm.
- Don't draw an `xmark` yourself, or add a `Button("Done")`.
- Don't put `ContentUnavailableView` in a large sheet; it fills the space.
- Don't force `.colorScheme(.light)` on a card to make it pop; use `Ink.surface`.
- Don't use a 28 pt card radius, or invent a 12 or 16 one. `Radius.control` is for fields inside a card.
- Don't make two sizes of header control; the avatars, the glass buttons and the coin pill are all 44 pt.
- Don't show a mood as an emoji. `MoodArt(mood:size:)` (`apps/ios/Shared/Mood`) draws its clay cat face from
  `Moods.xcassets`, and the plain face when there is no mood; the words beside it carry the label.

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
| `Space.xs…xl`, `Space.gutter`, `Radius.*`, `Size.*` | spacing, corners, sizes |

Over the room use `warmGlass`; elsewhere solid surfaces. Nothing in the app is red for the cat or the couple.

## Previews

Every file of the package has a `#Preview` drawn in light and dark (`BothSchemes`). Pick an iPhone in the
Canvas. A sheet's preview draws its content inline, because the Canvas cannot show a presented sheet. The
`Catalog` preview shows the Ink colours, the type ramp, Space and Radius and every component on one screen, and
the header over a room-like backdrop.
