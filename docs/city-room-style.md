# City room restyled to the Room

Klein (FLUX.2-klein-4B, 4 steps, 832x1104) was given the first Room's screenshot as its only reference
(`docs/images/city-room-style/reference-room.webp`) and a prompt for the second room's layout (bed under a big window, nightstand
and lamp, round rug, pet bed, fairy lights, one cat on the sill). The wording is "stylised low-poly sculpt, broad flat facets,
flat-shaded matte clay". Seeds 100, 137, 174, 211.

| File | Window view | Read |
| --- | --- | --- |
| `candidate-1.webp` | cream and terracotta town, warm afternoon | closest to the Room: peach walls, plank floor, coral blanket |
| `candidate-2.webp` | dusk, a few lit windows, peach sky | best for the City's time-of-day idea; the lamp glow reads |
| `candidate-3.webp` | pale sky and rooftops | calmest; the nightstand stacked like the app's crate stack |
| `candidate-4.webp` | trees and tidy houses in cream and sage | the most faceted, the one that looks most like the Room's flat shading |

What to follow, from the candidates and `CityRoomScene.Tone`:

- Palette: the Room's walls are a peach-cream that glows towards orange; the City's `wall` 0xF6E4C8 is paler and
  greyer. Warm it a step towards 0xF2D2B0 and keep the corner posts in the Room's terracotta.
- Floor: the Room's boards are broad, three tones of terracotta and honey, and the same board width everywhere; the City alternates
  two woods. Use the Room's three and a rounded skirting.
- Materials: everything matte clay (roughness about 0.82-0.95), chunky bevels, no thin parts. Curtains are the only soft
  fabric: tied at the sides, flat pleats.
- Light: one warm key, a soft baked occlusion where furniture meets the floor and wall; no hard cast shadows.
  Window glow is a warm wash, not a bright white pane.
- Props: the Room's pieces are chunky and few (round rug, chunky pet bed, drawers, shelf). Give the City the same pet bed, a
  drawer chest and one picture; keep the bed, nightstand and fairy lights it has.
- Proportions: furniture about as wide as it is tall, large rounded corners (radius about a third of the thinnest side), a thick
  wooden window frame with cross muntins like the Room's round one.

The window view in these shots is only a guide. The real one is the baked street diorama (`apps/ios/Nooki/Resources/CityDiorama`).
