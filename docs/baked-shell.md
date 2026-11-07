# Baked room shell (experiment)

Each room's static shell (floor, walls, beams, trim, window frames, curtains, bed, nightstand, shelf,
rug and the props that never move) can be one lightmapped model, `Room_shell.usdz` and `City_shell.usdz`,
instead of ~80 (Room) or ~220 (City) boxes built at launch. The procedural build is the default and
is unchanged; the baked shell is a second path chosen at runtime. Background and the estimate:
[perf-plan-2026-11.md](perf-plan-2026-11.md) item 9.

## The switch

- Labs, Settings > Labs > **Room shell**: Follow the test / Live / Baked (`labs.roomShell`), from the next launch.
- Remote flag `room-shell` (`live`, `baked`; draft, all weight on `live`). Start it in the admin to give
  `baked` to some pairs; set `live` as the only weighted variant or kill it to take it back for everyone, with no release.
- A Labs choice wins over the server's. A launch argument works too: `-labs.roomShell baked`.

## Rolling back

1. **Flag off**: Labs to Live, or the `room-shell` flag to `live` / killed in the admin. Nothing to ship.
2. **Delete the code**: remove `apps/ios/Nooki/Scene/BakedShell.swift`, `Room_shell.usdz`, `City_shell.usdz`,
   `scripts/bake-room/`, `NookiTests/BakedShellTests.swift`, `RoomShell.swift` and the Labs row; and the hooks:
   the one `useBakedShell(named:)` line in each of `DioramaScene.init` and `CityRoomScene.init`, the `isBaked` guard in
   `CityRoomScene.setPoint`, the `tintShell` line in `applyLight`, `ShellLive` on the garland and the clock hands, and
   the `skipsForShell` / `tagForShell` / `shape:` lines in `Kit.swift`.

## How it works

- A room's builders run as before. With the baked shell on, `useBakedShell` puts a `ShellMode` on the pivot and `Kit`
  does not build the static primitives under it (it checks the receiver's ancestors): glowing parts (bulbs, flame, lamp
  shade) and anything under a `ShellLive` (garland and its photos, the clock's hands) are built as ever. The baked
  model loads in the background, its material becomes `UnlitMaterial` (the light is in the texture) and is
  multiplied by a tint.
- The cat, the toys, bought items, bulbs, the candle, the window picture and the garland stay live. Lights: the City
  drops its sky, lamp, fairy and candle point lights (the sun, the fill and the ambient stay); the Room keeps all of
  its lights, because its furniture (`Room_furniture.usdz`) is still live.
- City time of day: one lightmap (15:00, lamps off) times a tint from the hour (`BakedShell.tint`).

## Re-baking

`scripts/bake-room/bake.sh [room|city] [--skip-export]` (one command, under the build lock):

1. `BakedShellTests.export` builds each room with its static parts tagged and writes their shapes, transforms and
   materials to `scripts/bake-room/shells/*.shapes` (one source: the Swift code).
2. `bake_shell.py` in headless Blender rebuilds the shapes with few triangles, merges them, unwraps one atlas, bakes
   Cycles light (sun, window, lamp, candle, sky, with the Room's furniture as a shadow caster) and writes a USDZ
   with one JPEG lightmap, 2048².
3. `sources.json` records what the shells were baked from. `BakedShellTests.theBakedShellsAreUpToDate` fails after
   any change to a room's static boxes until the bake is run again. The lights are a copy in `bake_shell.py`; change
   both when the Swift lights change.

## What can no longer change at runtime (baked path)

Wall, floor, bed, rug and other static colours; positions of static furniture; the sun's patch and the cat's
sun shadow on the shell (the shell is unlit: Mochi keeps her grounding shadow, but the sun does not shadow the walls);
City lamp pools at night (only the tint changes). Each needs a re-bake (about two minutes) after the Swift change.

## Differences seen, and what it costs

See the pull request for the measured budget and the A/B table.
