---
name: billet-ui
description: Use for any SwiftUI or UI work in apps/ios or packages/ios: screens, sheets, cards, buttons, headers, colours, fonts, spacing. Reads the design system and builds with the `design` package.
---

# Billet UI

Before writing or editing any SwiftUI in `apps/ios` or `packages/ios`:

1. Read `docs/design-system.md`. It says which component to use when, the rules, and three recipes for a
   screen ("How to build a screen"): `Screen` with the bottom action slot, a list of `ContentCard`s, an
   `ItemGrid` of `ItemCard`s.
2. Build with the `Design` package (`packages/ios/design`): `BilletSheet`, `Page`, `GroupedSection`, `Row`,
   `Card`, `CardHeader`, `Field`, `PrimaryButton`, `SecondaryButton`, `GlassIconButton`, `EmptyState`, `SectionHeader`, `Chip`,
   `FilterChip`, `PriceButton`, and the tokens `Ink`, `Space`, `Radius`, `Size`, `.ourio*` fonts.
3. Feature code (`apps/ios/Nooki`, `packages/ios/features`) uses only the package's tokens and components: no
   number for a padding, height, corner or font size, no raw colour or font, no `RoundedRectangle`, `.shadow`,
   `.blur`, material, `GeometryReader` or system button style, no `popoverTip` without `.hint`, no `Text`
   without a `.ourio*` style. `check-design.mjs` fails a file that goes past its count in
   `packages/ios/design/lint/baseline.json`, which only shrinks. If the package lacks a part, add it there with
   a `#Preview` and a place in the gallery (`apps/ios/OurioTests/Gallery/GalleryPage.swift`), then use it.
4. Before the PR: `scripts/check-ui.sh` (rules against main, their fixtures, swift-format) and
   `scripts/gallery.sh` (every component and the key screens at SE, Pro Max and the largest text size against
   their WebP references; `--record` after a deliberate change). Keep `Settings → Labs → Style` in step when a
   component changes.

5. Sheets use the native toolbar through `BilletSheet` (close leading + confirm trailing, or close trailing
   alone); controls over the room use `Ink.glassFill`/`Ink.glassGlyph`; scroll views get `.softScrollEdges()`.
