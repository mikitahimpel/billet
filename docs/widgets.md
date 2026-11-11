# Widgets

The widget extension is `apps/ios/OurioWidgets`. Every widget is one idea on warm paper (`Ink.screen`), with
honey spent once; text is the `.ourio*` styles, never smaller than `.ourioMicro`, and a widget caps Dynamic Type at
`xLarge` (`widgetTypeCap`).

| Kind | Families | Shows |
| --- | --- | --- |
| `com.ourio.app.cat` | small, medium, large | Mochi and how she is (`MochiPose`), Lv chip, Pet and Hug buttons |
| `com.ourio.app.us` | small, medium, large | days together, the next date, the streak (`StreakGlance`) |
| `com.ourio.app.partner` | small, medium | the partner's newest drawing or check-in on a stamped card (`PartnerNews`) |
| `com.ourio.app.coins` | small, medium | the balance and Mochi's care level (`CoinsGlance`) |
| `com.ourio.app.memory` | small, medium, large | the pinned moment as a print |
| `com.ourio.app.day` | large | Mochi, days together and the partner |
| `com.ourio.app.block` | small, medium | one configurable block: mood, list, date idea, moment |
| `com.ourio.app.lock.{us,streak,cat,partner}` | circular, rectangular, inline | the same facts for the Lock Screen |
| `com.ourio.app.drawing` | small, medium, large, rectangular | the partner's latest drawing |

Controls: `com.ourio.app.pet` (Pet Your Cat) and `com.ourio.app.hug` (Send a Hug, a Missing-you check-in).

## What a widget reads

`FamilyProvider` builds one `FamilyEntry` per entry date: the `OurioSnapshot`, `WidgetFacts` (streak, wallet and
latest drawing from the App Group) and, for the Memory widget only, the pinned photo downsampled to 600 px. All
mapping from state to words is pure and tested in `FamilyLogicTests`; the views only lay it out. Mochi's pose comes
from facts the extension has: a purr, the night, a fresh drawing or check-in. Her needs (hungry, tired) live in the
app and are not in the App Group, so no widget shows them yet.

## Timelines

`FamilyTimeline.entryDates` lists the moments the picture changes by itself (a purr ends, news goes stale, night
and day, midnight) and keeps entries at least ten minutes apart; the timeline policy is `.atEnd`. Saves elsewhere
reload through `WidgetCenter`: the app on backgrounding, and `LatestDrawing.widgetKinds` when a drawing arrives.

## Looking at them

`WidgetGalleryTests` renders every widget for a Pro Max and an SE, light, dark and accented, into
`$BILLET_SAMPLES/widgets` (CI keeps them as the `samples` artifact). With `BILLET_WIDGET_PREVIEWS=<dir>` it also
writes the ten pictures the in-app gallery (Settings, Widget gallery) shows, as `<Asset>-light.png` and
`-dark.png`; copy them into `apps/ios/Nooki/Assets.xcassets/WidgetPreviews/<Asset>.imageset` when a widget changes.
The test renders without WidgetKit, so the system tint and gauges are not drawn.
