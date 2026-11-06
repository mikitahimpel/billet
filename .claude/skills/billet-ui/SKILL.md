---
name: billet-ui
description: Use for any SwiftUI or UI work in apps/ios or packages/ios: screens, sheets, cards, buttons, headers, colours, fonts, spacing. Reads the design system and builds with the `design` package.
---

# Billet UI

Before writing or editing any SwiftUI in `apps/ios` or `packages/ios`:

1. Read `docs/design-system.md`. It says which component to use when, and the rules.
2. Build with the `Design` package (`packages/ios/design`): `BilletSheet`, `Page`, `GroupedSection`, `Row`,
   `Card`, `PrimaryButton`, `SecondaryButton`, `GlassIconButton`, `EmptyState`, `SectionHeader`, `Chip`,
   `FilterChip`, `PriceButton`, and the tokens `Ink`, `Space`, `Radius`, `Size`, `.nooki*` fonts.
3. Never write a raw `Color(red:`, `.font(.system(size:` or a hand-made sheet header, close button or card in
   feature code. If the package lacks a part, add it there with a `#Preview`, then use it.
4. Check the change by eye in a Simulator (`agent-device`), and keep `Settings → Labs → Style` in step when a
   component changes.
