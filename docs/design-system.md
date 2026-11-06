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
3. **Close and confirm have one place.** Close is the glass `xmark`, top trailing. A sheet that confirms
   something (edit, add) shows the glass honey `checkmark` top trailing and its close moves to top leading.
   Pushed screens get the system back chevron. Never "Done" or "Cancel" text.
4. **One card, one inset.** Cards and grouped sections use `Radius.card` on `Ink.surface`; screens and sheets keep
   `Space.gutter` (20) at the sides, 16 over the room. No gradients, rims or shadows on a card.
5. **One primary action per screen:** `PrimaryButton`, honey, full width. Next to it `SecondaryButton`. A
   disabled button stays readable; never fade a button to an unreadable label yourself.
6. **Glass is for chrome that floats:** header buttons, the tab bar, the toolbar of a full-screen canvas. Never glass
   on glass, never glass behind reading text, and not on every card of a scrolling list.
7. **Spacing comes from `Space`**, sizes from `Size` (`Size.control` = 44 is the height of every header control).
8. Numbers that change get `.monospacedDigit()`; animate them with `.contentTransition(.numericText())` only
   while the value changes.
9. Text on honey is `Ink.heroInk`; white on honey is unreadable.

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
| A price in coins | `PriceButton` |

### Do and don't

- Do give a sheet exactly one size: `.fit` for a few controls, `.medium` or `.large` for lists.
- Do put an empty state in `.fit`, not in a large sheet.
- Do keep the toolbar to close or confirm.
- Don't draw an `xmark` yourself, or add a `Button("Done")`.
- Don't put `ContentUnavailableView` in a large sheet; it fills the space.
- Don't force `.colorScheme(.light)` on a card to make it pop; use `Ink.surface`.
- Don't use a 28 pt card radius, or invent a 12 or 16 one. `Radius.control` is for fields inside a card.
- Don't make two sizes of header control; the avatars, the glass buttons and the coin pill are all 44 pt.

## Tokens

| Token | Use |
| --- | --- |
| `Ink.screen`, `Ink.surface`, `Ink.surfaceRaised`, `Ink.separator` | backgrounds and hairlines, adaptive |
| `Ink.text`, `.textSecondary`, `.textTertiary`, `.accentText` | text, adaptive |
| `Ink.primary`, `.secondary`, `.glassTint` | white on glass over the room |
| `Color.honey`, `.honeyDeep`, `.blushPink` | accent fills; blush is love and hearts only |
| `.nookiLargeTitle` `.nookiTitle` `.nookiHeadline` `.nookiBody` `.nookiCallout` `.nookiCaption` `.nookiMicro` | text styles |
| `Space.xs…xl`, `Space.gutter`, `Radius.*`, `Size.*` | spacing, corners, sizes |

Over the room use `warmGlass`; elsewhere solid surfaces. Nothing in the app is red for the cat or the couple.
