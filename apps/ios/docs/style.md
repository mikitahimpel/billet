# Nooki style

One native, warm style for everything drawn over Ilya's scenes. Tokens are in `Nooki/UI/Kit/Ink.swift` (colour),
`Nooki/UI/Kit/Style.swift` (type, shape, spacing, buttons, rows), `Nooki/UI/Kit/Glass.swift` (materials) and
`Shared/Palette.swift` (honey). Settings → Labs → Style renders all of them on the device.

Native first: sheets with detents, `NavigationStack`, `ToolbarItem`, `Menu`, `ContentUnavailableView`,
system buttons. Build a custom control only when the system has none (the tab bar is one: the + is a menu and the
room stays behind every tab).

## Appearance
The app forces dark (`.preferredColorScheme(.dark)` in `NookiApp.swift`). Screens move onto the adaptive tokens one PR
at a time and keep looking dark. No single screen or sheet goes cream by itself. When every screen is on the
tokens, light and dark switch app-wide in one step: drop the root `.preferredColorScheme(.dark)` and post a
before/after for the owner.

## Colour
### Screens and sheets (adaptive)
| Token | Light | Dark | Use |
|---|---|---|---|
| `Ink.screen` | #FBF3E8 cream | #2A1A12 warm brown | full screens and sheets |
| `Ink.surface` | white | #3B2C25 | cards and list rows on `screen` |
| `Ink.surfaceRaised` | #F3E6D6 | #46352C | selected rows, pressed cards, chips on a surface |
| `Ink.separator` | #3A2114 12% | white 14% | hairlines |
| `Ink.text` | #3A2114 (13.6:1) | white 96% | titles, body |
| `Ink.textSecondary` | #7A5A45 (5.7:1) | white 72% | subtitles, captions |
| `Ink.textTertiary` | #3A2114 45% | white 50% | placeholders, disabled; never body text |
| `Ink.accentText` | #A4521C (5.0:1) | honey | links, text buttons, checkmarks |

### Accent (same in both appearances)
| Token | Value | Use |
|---|---|---|
| `Color.honey` | #F2A65E | `.tint`, primary fills, progress, selection |
| `Color.honeyDeep` | #D9784A | gradient end, pressed fill |
| `.honeyGradient` | #FFC27D → honeyDeep | filled discs and capsules before iOS 26 |
| `Color.blushPink` | #FF8FA3 | love and hearts only |

Text on honey is `Ink.heroInk` (7.4:1). White on honey is 2.0:1, so never use it for text.
Nothing in the app is red for the cat or the couple: no warning colours, blinking or shaking for a need or a streak.
Destructive system rows (Erase All Data) keep the system red.

### Over the room (always on room, whatever the appearance)
| Token | Value | Use |
|---|---|---|
| `Ink.primary` / `Ink.secondary` | white 96% / 72% | text on glass over the scene |
| `Ink.glassTint` | honey 16% | the tint inside Liquid Glass over the room |
| `Ink.sheet`, `Ink.card` | #2A1A12, white 8% | dark-only names, replaced by `screen`/`surface` screen by screen |

## Type
Text styles only, so every size follows Dynamic Type. SF Rounded for display and controls, SF Pro for reading.

| Token | Style | ≈ pt | Use |
|---|---|---|---|
| `.nookiLargeTitle` | largeTitle, rounded, bold | 34 | screen titles (or the navigation bar's own) |
| `.nookiTitle` | title2, rounded, bold | 22 | sheet titles, card heroes |
| `.nookiHeadline` | headline, rounded, semibold | 17 | buttons, row titles |
| `.nookiBody` | body | 17 | reading text |
| `.nookiCallout` | subheadline, medium | 15 | secondary rows |
| `.nookiCaption` | footnote, medium | 13 | captions, footers, in `textSecondary` |
| `.nookiMicro` | caption2, rounded, semibold | 11 | badges, counters |

Numbers that change (coins, counters, days) get `.monospacedDigit()` and `.contentTransition(.numericText())`.
Navigation titles use SF Rounded through `NavigationBarStyle.apply()` at launch.

## Shape and spacing
- `Radius.tag` 8, `.control` 14 (inner rows, fields), `.card` 20, `.hero` 28. Buttons, chips and pills are capsules.
- Sheets keep the system corners.
- `Space.xs` 4, `.s` 8, `.m` 12, `.l` 16, `.gutter` 20, `.section` 24, `.xl` 32. The gutter for screens and sheets is
  20, and 16 over the room.
- Tap targets are at least 44 pt. A full-width primary button is 52 tall (`.controlSize(.large)`).

## Materials
- **Over the room**: Liquid Glass via `warmGlass(shape)` (clear glass with `Ink.glassTint`, interactive for controls).
  It falls back to `.ultraThinMaterial` before iOS 26. Group neighbouring glass in `GlassGroup` so it blends.
- **Screens and forms** (onboarding, profile, settings): solid `Ink.screen` with rows on clay cards (`NookiForm`).
  Never put glass on glass, and don't put glass behind reading text.
- **Cards** (Us, the Shop, their sheets): `nookiCard()`, warm clay lit from above with a light rim along the top and
  a soft shadow cast by the card's shape only. `warm: true` pours honey into the light for a screen's hero card.
  `usCard()` and `shopCard()` are this card, and so is every `NookiSection`.
- **The Shop** keeps its own saturated accents for selling (`ShopInk`: coral, plum, teal, gold) and rarity colours:
  common sand, rare teal, epic plum, legendary gold. Frames are lit in their colour; epic and legendary glow.
  Discounts are coral; blush stays for love.
- **Sheets**: the system sheet with detents sized to the content (`.presentationDetents([.height(measured)])` or
  `.medium`/`.large`). On iOS 26 the sheet is the system's glass; give it `Ink.screen` once the screen moves to tokens.

## Buttons
| Role | iOS 26+ | iOS 18–25 | Notes |
|---|---|---|---|
| Primary | `.nookiPrimary()` (`.glassProminent`, honey) | `.borderedProminent`, honey | one per screen; capsule; heroInk label |
| Secondary | `NookiSecondaryStyle()` | same | honey words on a raised clay capsule; `.glass` only over the room |
| Tertiary | plain text in `Ink.accentText` | same | "Not now", "Skip" |
| Toolbar | `ToolbarItem` + system button | same | Done is `.confirmationAction` |
| Destructive | `Button(role: .destructive)` | same | always behind a confirmation |

`.plain` is only for whole-row or whole-card taps, with `PressScaleStyle` for feedback.

Buttons inside cards that scroll (the Shop's prices, claims and chips: `shopButton()`) are flat capsules, honey or
raised clay, never glass: glass is for chrome that floats over the room, grouped in a `GlassGroup`. Shadows are cast
by a shape behind the content, not traced from the content.

## Lists, cards, chips, sheets
- **Forms and settings**: `NookiForm` (a scroll view on `Ink.screen`, honey tint) of `NookiSection`s: a caption
  header, rows on one clay card with hairlines, a footer that explains in one or two sentences. Rows are
  `NookiRowLabel` (icon in a tinted circle, title, optional detail, a trailing control or `RowChevron`),
  `NookiToggleRow` and `NookiPickerRow`; a plain control in a section gets `.nookiCell()`. No system `List`/`Form`
  grouped look and no system blue.
- **Cards**: `nookiCard()`, `Radius.card`, `Space.l` padding. Over the room, a card is warm glass instead.
- **Chips**: capsule, `.nookiCallout`, `Space.m`×`Space.s` padding; `surfaceRaised` when selected on a screen, and warm
  glass over the room.
- **Header** (every tab): Inbox circle at the leading edge; coins, then the couple's avatars at the trailing edge (they
  open the profile as a plain full-height sheet), and nothing else.
- **Avatars** (`Monogram`): a face-centred square photo or the initial, in a soft clay ring with a gentle shadow; the
  couple's link is a honey heart.
- **Tab bar**: World / Moments / Shop and the + menu, a glass capsule over the room.
- **Empty states**: `ContentUnavailableView` with a symbol, a warm line and one primary action.

## SF Symbols
Weight `.semibold`, `.symbolRenderingMode(.hierarchical)`, or `.palette` with honey. Size symbols with the text style
they sit next to, and use `.fill` variants in tabs and badges. Needs: `fork.knife`, `moon.zzz.fill`,
`tennisball.fill`, `heart.fill`.

## Motion and haptics
- State changes `.spring(duration: 0.35)`, toggles `.snappy(duration: 0.25)`, bars and progress
  `.spring(duration: 0.6, bounce: 0.2)`.
- Reduce Motion (`@Environment(\.accessibilityReduceMotion)`): use plain short fades and no bounces.
- Haptics: `.sensoryFeedback(.selection)` on picks and tab changes, `.success` on completion, nothing on scroll. Every
  haptic respects Settings → Haptics.

## Copy
Warm, short, second person to the couple and third person for Mochi ("Mochi would love a treat"). Never guilt ("Mochi is
starving", "You forgot"), and never shout: no exclamation marks in titles. Sentence case.
