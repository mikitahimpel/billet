# Nooki performance plan, November 2026

What makes the app feel slow today, ranked by what the user feels against what a fix costs, with
the numbers behind each claim and how each fix will be proved. Written before any fix; the rules it
leans on are in [ios-performance.md](ios-performance.md). Phase 2 PRs cite this file by item number.

## In three lines

- The tabs and lists are main-thread bound, not GPU bound: the Shop scroll spends about 40 ms of
  main-thread CPU per frame in a Release build (CI), with the room unmounted. Sheets over the World
  are the one place the live room is the cost, because it keeps drawing under them.
- Every return to the World freezes the whole UI for one frame of 0.3–1.1 s (CI) while a new
  RealityView mounts; #421's snapshot hides the room, not the freeze.
- The rooms do far more per frame than they need to: 80 (Room) to 240 (City) separate entities with
  separate materials, 4–6 dynamic lights with a shadow pass, 26–30 bulb transforms written every
  frame, and a 286k-triangle furniture mesh drawn three times a frame.

## How this was measured, and how far to trust it

- Every number here is from `perf.yml` on GitHub's Mac runners (Release, Simulator, unsigned): the
  11-05 full runs 42089568750 and 42047015868, and today's runs 42363291154 (baseline, main vs
  main), 42363652666 (glass arms, `cost`) and 42363655489 (sheets over the room, `ab`).
- No local Instruments run was possible: the Mac ran at a load average of 575 on 8 cores all
  morning (13 agents), under the build lock or not, so any local frame or CPU number would have
  been noise. Phase 2 needs either a quiet hour on the Mac or a Time Profiler job on CI (H6 below).
- What CI can and cannot show, from ios-performance.md §4.4: main-thread CPU per frame
  (`mainCPU`), process CPU per second (`cpuMsPerS`), hitch and stall counts, launch marks, and
  memory peaks are trustworthy as *relative* numbers between two arms of one run. Absolute frame
  times are not: the runners carry a load average of 150–500, the room idles at 10–18 fps there,
  and the Simulator's Metal is a translation layer with no Apple GPU. GPU-bound costs (glass
  sampling, bloom, splat fill, shadows) only show on a phone. Energy and thermal only show on a
  phone.
- The CI cat is the mesh cat (no Apple7 GPU), so the splat skinning cost (B12) is invisible here.

## Baseline

From the 11-05 full runs on main (medians, min–max over 2 rounds, iPhone 17 Pro Simulator; the
runner's load average was 450–500). The new baseline on today's main is in run 42363291154 and is
added below when it lands.

| Phase | p50 ms | p95 ms | fps | mainCPU ms/frame | procCPU ms/frame | cpuMsPerS | hitches |
| --- | --- | --- | --- | --- | --- | --- | --- |
| launch: first frame | 3.4–4.0 s | | | | | | |
| launch: room drawing | 8.4–8.8 s | | | | | | |
| launch: cat placed | 9.2–10.4 s | | | | | | |
| room idle (full.idle) | 52–92 | 82–211 | 9–20 | 6–9 | 14–30 | 190–310 | 44–75 / 5 s |
| room orbit | 89–94 | 167–199 | 11 | 7.8–8.2 | | 195–200 | |
| Shop still | 16.7 | 16.7–42 | 50–60 | 2.9–3.7 | 3.0–3.8 | 177–193 | 1–23 / 3 s |
| Shop scroll | 40–52 | 92–102 | 17–24 | **34–45** | 37–49 | **850–890** | 171–182 / 10 s |
| settled room | 56–95 | 106–176 | 10–18 | 6–13 | 15–26 | 127–285 | 33–68 / 5 s |
| tab → Shop | 770–910 ms to "shop on screen" | worst frame 56–60 ms | | | | | |
| tab → Moments | 100–108 ms | worst frame 25–110 ms | | | | | |
| tab → World | 280–295 ms | **worst frame 670–1140 ms** | | | | | |
| memory peak, full run | 240 MB (mesh cat, 2048² textures) | | | | | | |

Read: the Shop scroll is the one phase where the app's own main thread is the bottleneck (34–45 ms
of CPU in a 50 ms frame). The room phases are runner-bound (main thread 6–9 ms of a 60–90 ms
frame), so their CI frame times say little; their `cpuMsPerS` says the room never idles.

Two things in the Shop number are not the Shop: the harness drives the scroll by writing
`ScrollPosition.scrollTo(y:)` sixty times a second, which re-runs `ShopView.body` each time, and the
`full` run's Moments scroll (`notes.scroll`) uses the same drive, so the two compare with each other.
Phase 2 adds one animated `scrollTo` per sweep (H4) so the drive costs one body pass, not sixty.

## The owner's report: menus, sheets and lists drop frames

Checked screen by screen against the code on main at fc590241 (#495's split is in).

**Settings (and the profile, mood, pairing and Coins sheets).** These are `BilletSheet`s over the
World tab. `HomeView.roomCovered` counts only the drawing canvas, the Inbox and the note composer as
covers (#439), so under every other sheet the room keeps drawing at full rate: the RealityView,
the cat, the bulbs, the City's window layers and (iOS 27) bloom, behind an opaque `Ink.screen`
ground that hides all of it once the sheet is at `.large`. The sheet's own content is cheap
(`Page` and `GroupedSection`, a plain `VStack`). This is item 1, and the `sheet` vs `sheet.paused`
covers in run 42363655489 give the number.

**Shop.** The room is unmounted here (#417). The cost is the scroll's main thread, 34–45 ms a frame
(CI). Suspects in order of likely weight, none yet measured on its own:

1. `FeaturedCard` carries two Liquid Glass effects *inside the scrolling content*
   (FeaturedCard.swift:28, :59) plus an 18 pt coral shadow (:66). Glass that moves re-samples its
   backdrop every frame; the Shop's chrome (header, tab bar) is glass too, but it stands still.
2. `RarityFrame` casts a 9 pt glow shadow from its shape for epic and legendary cards
   (ShopKit.swift:64): one offscreen blur per such card per frame while the card moves.
3. Every card has `shopAppear()`, a `scrollTransition(.animated(.spring))` (ShopKit.swift:166):
   SwiftUI evaluates the phase closure for every card in the lazy buffer on every scroll frame,
   and springs each one that crosses the edge.
4. `ShineSweep` on epic and legendary cards: a `GeometryEffect` moved by a repeating animation plus
   `onScrollVisibilityChange` per card (ShopKit.swift:93–112). Cheap per card, but it keeps the
   Shop from ever idling while such a card is on screen (`shop.still` at 60 fps with 3 ms of main
   thread a frame is this).
5. `ShopView.body` re-runs on each `ScrollPosition` write (the harness, see above; a user's fling
   does not write it) and rebuilds the whole `today` tree: FeaturedCard, DailyGiftCard, every
   BundleCard, InkShelf, every CollectionCard with its 4-column grid.
6. `Thumbnails.image` decodes on the main thread inside `body` for any card whose art the prefetch
   has not reached yet (Thumbnails.swift:10–15): the first scroll after opening the Shop pays it.

**Moments.** Two `LazyVStack` columns (fine), photos decoded off the main thread (fine, #440). The
cost is per visible print, every frame it moves: two CA shadows from the paper's shape
(Polaroid.swift:121–122), the whole print rotated (`rotationEffect`, MomentsView.swift:148), the
washi tape with a `.screen` blend and its own shadow (Polaroid.swift:144), the reaction or heart
badge with a shadow (MomentsView.swift:339, :349). Each of these is an offscreen pass on the render
server; with 6–10 prints in view that is 20–40 offscreen passes a frame. #473 removed the worst
(shadows traced from pixels, a multiply blend); what is left is the shape shadows and the rotation.

**Us.** A plain `ScrollView` of cards; the page itself is short. Its screens are sheets over the Us
tab (no room mounted), and they carry the largest shadows in the app: `DatePlanCard` 24 pt
(DatePlanCard.swift:54), `SwipeDeck` 16 pt (:183), `PickTonightScreen` 14–16 pt (:130, :285),
`StreakCard` a 12 pt glow (:105), `MovieCard` 8 pt (:90), `WatchList` 6 pt (:207), `ListCard` 4 pt
(:186). A 24 pt shadow is a 24 pt gaussian blur of the card's alpha each frame it moves. Posters in
`WatchList` and `SwipeDeck` come through `AsyncImage`, which neither downsamples nor documents its
cache (§2.6). The harness has no Us scroll or Us sheet step, so there is no number yet (H2).

**The header and the tab bar.** On iOS 26 they are `safeAreaBar`s with a `scrollEdgeEffectStyle`
over every tab (WarmBackdrop.swift:60–64) and two `GlassEffectContainer`s. The edge effect is a
progressive blur of whatever scrolls under each bar, every frame, plus the glass sampling. This is
the system's own toolbar cost and every iOS 26 app pays it; the glass experiment below measures our
part of it over the room, and `-perf.hud opaque` over the Shop.

## Top 10, by user impact against effort

Impact: what the user feels, how often. Effort: S under a day, M 1–3 days, L more. "Proof" names
the perf.yml phases an A/B must move. Owner: ours, or needs Ilya (his files: CatRoom, DioramaScene,
CityRoomScene, DioramaView, CatWalker, CatRig, Kit, Props, SplatLoader, Resources, Tools/make_*).

| # | Cause | Where | Owner | Impact | Effort | Fix | Expected gain | Proof | Risk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | The room keeps drawing under every sheet that is not a cover: profile/Settings, mood, pairing, Coins, pet sheet, item sheet's large detent. | HomeView.swift:52–57 (`roomCovered`), AppHeader.swift:38–47 | ours | high: the owner's Settings report; every sheet on the World | S | Count sheets as covers once their detent hides the room (`.large`, or `.mediumLarge` dragged up): #421's snapshot stays up, the RealityView unmounts, the sheet scrolls over a still image. Half-height sheets keep the room live. | The sheet's frames drop to the sheet's own cost; on CI `cover.sheet.paused` vs `cover.sheet` says how much (run 42363655489). Energy: the room's whole CPU and GPU for as long as a sheet is up. | `cover.sheet` p50/p95/fps/mainCPU/cpuMsPerS, head vs base | low; the cat holds still behind a tall sheet, which it does today behind the Inbox |
| 2 | Returning to the World mounts a new RealityView and blocks the main thread for one 0.3–1.1 s frame; every tab switch back to Home, every closed cover. | HomeView.swift:76–90, DioramaView.swift:39–44 | ours (HomeView); DioramaView is Ilya's if the view changes | high: felt on every return, as the tab bar and header freezing | S to test, M to land | Test the drawable-starvation reading of #417: keep the RealityView mounted at opacity 1 under the tabs' opaque surfaces with `root.isEnabled = false` (an empty scene costs a clear and a tick), instead of opacity 0 (where CA skips the layer, the drawables never recycle and `nextDrawable` waits its 1 s). If the 1 s stalls stay away, the remount and its freeze go. Fallback: mount the room a frame before the tab switch finishes. | `switch tab.home: worst frame` from 670–1140 ms (CI) to the switch's own frame; `shop.still` must keep 60 fps and no 1 s frames | `switch tab.home: worst frame`, `shop.still: max`, `PERF frame long` | medium: #417's stalls can come back; the A/B catches it before merge |
| 3 | Shop scroll: 34–45 ms of main thread per frame | ShopView.swift, FeaturedCard.swift:28,59,66, ShopKit.swift:64,93–112,166 | ours; look needs the owner | high: the Shop is where fps drops were first reported | M | In order, each as a `-perf.shop` switch first so the A/B names the weight: (a) FeaturedCard's two glass effects become opaque fills with a stroke, its 18 pt shadow a baked image; (b) the rarity glow baked into the frame image; (c) `shopAppear` only on the lazy grids, not on bundles, collections and the gift; (d) the shine as a `TimelineView(paused:)`-free animated image, or only on the hero; (e) prefetch the first screen's art before the Shop's first body. Harness: animated `scrollTo` (H4). | mainCPU per scroll frame down to 10–15 ms (CI), p95 under 33 ms; on a phone 60 fps scroll | `shop.scroll: mainCPU, p95, hitches, slowBusyMs`; `shop.still: mainCPU` | low–medium: the look changes slightly (FeaturedCard glass → opaque) |
| 4 | Moments feed: 3–5 offscreen passes per visible print per frame | Polaroid.swift:109–130, :144; MomentsView.swift:148, :339, :349 | ours | medium–high: the Moments list, reported | S–M | One pre-rendered paper image per paper colour with the two shadows baked in, drawn as a 9-part stretchable `Image` (no CA shadow); the tape without `.screen` blend (a lighter tint instead) and with its shadow baked; the badge's shadow a baked disc (as PetSheet.swift:49 already does); keep `rotationEffect` (a rotated flat layer is cheap once nothing under it is an offscreen pass). | `notes.scroll` p95 and hitches at the Shop-still level; mainCPU unchanged, since this is render-server work: on CI it shows as fewer hitches and `slow` frames, on a phone as GPU time | `notes.scroll: p95, hitches, slowMs` | low |
| 5 | Us screens: 12–24 pt shadows on moving cards; posters through `AsyncImage` | DatePlanCard.swift:54, SwipeDeck.swift:183, PickTonightScreen.swift:130,:285, StreakCard.swift:105, MovieCard.swift:90, WatchList.swift:207, ListCard.swift:186 | ours | medium: the Us lists, reported | S | Shadow radii capped at 8 on anything that scrolls or swipes, drawn from the card's shape; the deck's one big shadow on the top card only; posters through `Thumbnails`-style downsampling with a memory cache. First add a `us.scroll` step and a `us.dates` cover (H2) to have a number. | the new `us.*` phases at the Shop-still level | `us.scroll`, `cover.us.dates` | low |
| 6 | Glass over the live room (header, tab bar, pet button, room switch) | AppHeader.swift:18, TabBar.swift:24, HomeView.swift:117–127, PlayAllButton | ours; look needs the owner | unknown until measured: see "Glass over the room" | S | Decided by the experiment: keep glass, or opaque under Low Power and `.serious` thermal state only, or opaque everywhere. | see below | low |
| 7 | The City room: ~220 model entities with ~220 separate materials, 2 directional (1 shadowed) + 4 point lights + IBL, 30 bulb materials rewritten at dusk, `Calendar` and 12 point projections every frame | CityRoomScene.swift (whole), Props.swift, Kit.swift:16–30 (one material instance per call), Daylight.swift:77–80 | needs Ilya | high on the City (the owner's room switch and City fps), medium elsewhere | M | Share one material instance per tone (Kit); merge the static boxes of a room into one `MeshResource` with one part per material at build time (`MeshResource.Contents`, still Swift, still code-driven) so ~220 draw calls become ~15 in each of the colour and shadow passes; bulbs as one `MeshInstancesComponent`; the clock sampled once a second; `placeWindow` only when the camera or yaw moved. | render-thread and main-thread CPU per frame down by 3–8 ms on a phone (estimate from ~20–40 µs per entity per pass); `cpuMsPerS` on the City down 20–30 %; no look change | `room=city`: `steady: cpuMsPerS`, `orbit: p95, mainCPU`, `cost` once switches exist | low–medium: a merged mesh is culled as one (it is always on screen anyway) |
| 8 | The Room: 26 bulb scales and the flame written every frame; furniture is one 286k-triangle mesh (≈568k GPU vertices) with 59 subsets and duplicate materials, drawn in the colour pass, the sun's shadow pass and the grounding-shadow pass; every subset and every fur shell casts a grounding shadow | DioramaScene.swift:82–89, :289–292; Resources/Room/Room_furniture.usdz (9.9 MB); CatRoom.swift:303–306 | needs Ilya | medium–high: Home's resting cost and energy | M (make_room.py already builds the furniture) | Bulb pulse at 20 Hz and as one instanced mesh; decimate and weld in make_room.py (target ≤ 60k triangles) and merge duplicate materials (59 → ~8 subsets); one shadow technique for static furniture (the sun's shadow map, no grounding shadow); no shadow from the fur shells. | ~1 M triangles a frame down to ~0.2 M; draw calls per frame from ~300 to ~120; main-thread commits per frame from ~28 to ~2; expect 1–3 ms of GPU and 0.5–1 ms of main thread on a phone | `cost` with new switches `fairy pulse`, `furniture shadow`; `memory peakMB`; `steady: cpuMsPerS` | low–medium: the furniture gets slightly softer at the closest zoom |
| 9 | Bake the static shell of each room into one merged USDZ with lightmaps and AO (the manager's hypothesis) | DioramaScene, CityRoomScene, Kit, Props, Tools/ | needs Ilya and a pipeline | high per frame on phones, after 7 and 8 | L | See "Baking the static shell" below. | draw calls per pass ≈ 1–3 for the shell; lights from 4–6 to 1–2; fragment lighting cost of the room roughly halved | `cost` with a `baked shell` switch; `steady`; a phone run for GPU time | medium: a bake pipeline to keep, the loss of live tweaks, the time-of-day tint needs a design |
| 10 | Launch: `Tips.configure` and every store read synchronously in `App.init`; the splash decodes a 1200×1600 portrait on main; the room's assets load in series on the mesh path and the four 7.3 MB splat files one after another; the furniture is 9.9 MB | NookiApp.swift:13–37, CatHero.swift:23, CatRoom.swift:320–360, SplatLoader | ours (app, splash); needs Ilya (loads) | medium: once per launch; 3.4–4 s to first frame on CI, 8.5 s to the room | S (app) + M (loads) | Stores read off the main thread behind a placeholder state; `Tips.configure` after the first frame (measured first, B24); the splash portrait shipped at its drawn size; splat poses loaded in a `TaskGroup` and parsed from a mapped file into the buffers; furniture decimated (8). | first frame −100–300 ms (phone, estimate), room drawing −20–30 %, cat placed −30 % | `ab` launches: `first frame`, `room drawing`, `cat placed`, `memory peak` | low |

Not in the ten, worth their own line:

- **B13, no idle, thermal or Low Power policy.** On Home at rest the process burns 190–310 ms of
  CPU a second on CI: skinning near every frame, bulbs every frame, window life at 8 Hz, motes. A
  rest policy (nothing touched for 10 s and the cat asleep: skin at 30 Hz, bulbs at 10 Hz, life at
  4 Hz, bloom off) and a thermal step-down (§1.9–1.10) are the energy items. Proof: `steady:
  cpuMsPerS`; a phone's Power Profiler.
- **Games.** `GameCamera` and `GameSession` subscribe to `SceneEvents.Update` (fine), B17 is fixed.
  No step measures a game (H3), so nothing is claimed.
- **Memory.** 240 MB peak on CI with the mesh cat (two 2048² colour, normal and fur maps per
  model, B8). On a phone the four resident splat poses are ~55 MB (B11). Not a jetsam risk on
  phones with 4 GB or more; the widget's 30 MB is the one to watch.

## Glass over the room

The owner's experiment: what Liquid Glass over the live room costs, by arm.

**Arms, as run on CI (branch `perf/glass-arms`, harness only, no change to the app's look).**
All in one process, each arm on and off in turns, both orders at random, still then orbiting
(`cost`), so the runner's drift falls out:

| Arm | How it runs | Switch |
| --- | --- | --- |
| A, today | header and tab bar in Liquid Glass | every switch on |
| B, opaque | the same controls as an opaque `Ink.surface` fill of the same shape with a 1 pt stroke and an 8 pt shadow | `glass hud` off |
| C, glass, room paused | glass as today, the room's root disabled under it (RealityKit draws an empty scene; there is no public frame-rate cap for a `RealityView` on iOS, §1.9) | `room paused` off |
| D, no HUD | header and tab bar not in the tree | `hud` off |

Sheets, in the `full` run as covers over the live World, each held 5 s: `sheet` (the profile sheet
as it ships: opaque ground, room live under it), `sheet.paused` (same, root disabled), `sheet.glass`
(an `.ultraThinMaterial` ground). The Shop scroll under each HUD arm runs as separate `ab` runs with
`-f app_args="-perf.hud opaque"` and `"-perf.hud hidden"` (the launch argument the branch adds).

**What the Simulator can say.** The glass's own cost is GPU work (sampling and blurring the
backdrop); the Simulator runs Metal through a translation layer on the Mac's GPU, so an A vs B
difference in frame time there says the shape of the cost, not its size on an A17 or A19. The
main-thread and process CPU numbers (`mainCPU`, `cpuMsPerS`) are the trustworthy part: they show
whether glass adds CPU work (layout, backdrop capture) at all. A device run with Metal System Trace
would give the GPU ms per frame of the glass passes and the real thermal state after five
minutes; the Simulator has no thermal model.

**Results.** Runs 42363652666 (arms) and 42363655489 (sheets) were still in flight when this
revision was written; their tables go here, with the recommendation, when they land. Until then
the recommendation is conditional:

- If B (opaque) saves under 1 ms of frame time and no measurable CPU on CI, keep the glass and take
  the room-under-sheet win (item 1) instead, which is where the room's cost actually goes.
- If B saves 1 ms or more, or any CPU, make opaque the Low Power and `.serious` thermal variant,
  and ask the owner about opaque everywhere with the device numbers.

## Baking the static shell

The manager's hypothesis: build each room's walls, trim, floor, window, garland and non-movable
furniture into one merged USDZ per room with baked lightmaps and ambient occlusion, cutting
entities, draw calls and dynamic lights, while the cat, the toys and the time-of-day tint stay
live.

**Counts today, from the code.**

| | Room (DioramaScene) | City (CityRoomScene) |
| --- | --- | --- |
| Model entities built in code | ~81: floor 8, walls and beams 15, garland 30 (12 twine, 6 cards × 3), bulbs 26, flame 1, plus 5 invisible hit boxes and 1 emitter | ~220: floor 8, walls 7, window 12, bulbs 30, rug 2, bed 6, nightstand 8, sill props 11, curtains ~17, pictures 10, clock ~17, shelf and books 9, dresser ~8, radio 4, plants ~12, bed and bowls 15, slippers, mouse, plush, stacks ~20 |
| USDZ models | furniture (1 entity, 59 subsets, ~286k triangles), ball, yarn | none (the town picture plane) |
| Material instances | one per primitive call (`Clay.matte` is never shared) + 59 | one per primitive call (~220) |
| Draw calls per frame, estimate | colour ~145 + sun shadow ~140 + grounding shadows ~65 ≈ 350 | colour ~225 + sun shadow ~225 ≈ 450 |
| Triangles per frame, estimate | ~0.9 M (the furniture in three passes) | ~0.1 M |
| Dynamic lights | 1 directional with shadow, 3 point (candle, lamp, window), IBL | 2 directional (1 with shadow), 4 point (sky, lamp, fairy, candle), IBL |
| Per-frame writes | 26 bulb scales, the flame, the candle light every 3rd frame | the clock, 12 projections, lights when the hour moved; 30 bulb materials at dusk |

(Board room, behind the Moments board: 2 directional, 1 point.)

**After a bake, estimate.** The shell becomes 1–3 entities per room (one part per texture atlas),
the bulbs one instanced entity, the toys and the cat as today: draw calls per pass from ~145/225
to ~10–15, lights from 4–6 to 1–2 (one directional for the cat's shadow and the sun patch, the
IBL), triangles unchanged or lower (the furniture decimated in the same pass). With one light the
PBR fragment work on the room's pixels drops to about a third (each dynamic light is evaluated
per lit fragment; the lightmap is one texture read). Frame-time gain on a phone: 2–4 ms of a
10–14 ms frame in the Room, 3–6 ms in the City where the entity count is the cost; on CI 20–30 %
of the room's frame. These are estimates from counts, not measurements: the first `cost` switch
of Phase 2 (`merged shell`) turns the estimate into a number.

**What it costs.**

- A pipeline: `Tools/make_room.py` (433 lines, Blender) already builds the furniture USDZ, and
  `Tools/bake_maps.py` already bakes normal and AO maps with Cycles. The shell is new: the walls,
  floor, trim, window and props exist only as Swift `Kit` calls, so the script either re-describes
  them in Python (two sources of truth) or Swift exports the box list as JSON once for Blender to
  read (one source). Then UV unwrap, a Cycles lightmap bake per lighting state, an atlas at 2048²,
  export, and a Swift loader that puts an `UnlitMaterial` (lightmap × tint) on the shell. Two to
  four days for one person who knows Blender, plus Ilya's review of every room.
- The time of day: a lightmap is one lighting state. The City needs at least day and night maps
  blended by hour (a custom material, or two shells cross-faded), the lamps on and off, and the sun
  patch stays a real light. The Room has fixed lighting and bakes cleanly.
- Runtime tweaks: moving a shelf or changing a wall tone means a re-bake (minutes) instead of a
  constant in Swift. The toys, the garland photos, the cat and the bulbs stay live.
- Memory: a 2048² lightmap atlas per room is ~22 MB uncompressed (§1.4), ~4 MB as ASTC.

**A cheaper first step that keeps the code-driven rooms.** Share material instances (one per tone)
and merge the static primitives into one `MeshResource` per material at build time, in Swift
(item 7). That takes the draw calls down the same way without Blender, keeps every tweak in Swift,
and loses only the lighting win (the lights stay dynamic). It is a day's work in Kit and Props,
and the `cost` switch for it tells whether the lights are worth a bake afterwards.

## Harness gaps

Each is small and goes into the first Phase 2 PR, so every fix PR can show its number:

- **H2** a `us.scroll` step and a `us.dates` cover.
- **H3** a `game` cover and a `room.city` switch step (the City is rebuilt on every open,
  HomeView.swift:399–430, so the switch's frame is a number worth having).
- **H4** the scroll drive as one animated `scrollTo` per sweep, so a scroll phase measures the
  page, not sixty body passes. Both base and head keep the same drive, so A/Bs stay fair.
- **H5** `cost` switches for `fairy pulse`, `furniture shadow`, `fur shadow`, `merged shell`,
  `shop glass`, `shop glow`, `shop appear`, `shop shine`.
- **H6** a Time Profiler job: `xctrace record --template 'Time Profiler'` on the runner's
  Simulator for one `full` run, exported as the top 40 main-thread symbols. The Mac cannot profile
  while it hosts a dozen agents, and this is the only way to see what the Shop's 40 ms are.
- **H1, H5 from ios-performance.md** stay as listed there.

## Phase 2 PRs, in order

| PR | Items | Owner | Measured by |
| --- | --- | --- | --- |
| P1 harness | the glass arms (already on `perf/glass-arms`), H2–H6 | ours | the run itself |
| P2 room under sheets and the tab return | 1, 2 | ours; DioramaView if the mount changes (Ilya) | `cover.sheet*`, `switch tab.home`, `shop.still` |
| P3 Shop scroll | 3 | ours, look via the owner | `shop.scroll` |
| P4 Moments and Us | 4, 5 | ours | `notes.scroll`, `us.scroll` |
| P5 glass policy | 6 | ours, look via the owner | the arms, a phone run |
| P6 rooms per frame | 7, 8, B13 | needs Ilya | `cost`, `steady` |
| P7 launch | 10 | ours + Ilya for the loads | `ab` launches |
| P8 baked shell | 9 | needs Ilya and the owner | `cost: merged shell`, a phone run |

Each PR: one `perf.yml` A/B against the merge base, both sizes, the numbers in the PR body, no
screenshots unless a look changes and the owner asks for one.
