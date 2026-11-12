# Idle World heat

Why the phone gets hot with the room open (and on other tabs), what would cut it, and in what order to try.
Written from the code and Apple's documentation only: nothing here was built or run. Each claim is marked
**[code]** (read in this repo), **[docs]** (read in Apple's documentation or forums on 2026-11-11, links at the
end), **[memory]** (known API, not re-read today) or **[guess]** (inference to be tested).

## 1. What we know

Measured on the iPhone 17 Simulator, Release + Labs, quiet host (Labs Energy readout, 100 = one core):

| State | CPU | Split |
| --- | --- | --- |
| World, Living room, idle | ~35 | ~15 RealityKit's own frame loop (a paused root still costs it), ~8 dust motes, ~12 drawing the room and the cat |
| Other tabs (room view kept at 1 x 1 pt, #618) | ~10-12 | the same frame loop |
| Cat brain | ~0 | 3-21 µs a decision; awake and asleep cost the same |

Tried, no change: `ARView.__preferredFrameRate`, shadows off, bloom off. Sun shadow off or point lights off
cost more.

### 1.1 The Simulator numbers miss most of what heats a phone

This is the main finding of the code read. The 35 points describe a different room from the one on the owner's
phone.

- **The Simulator never draws the splat cat.** `SplatLoader.isSupported` is `false` under
  `targetEnvironment(simulator)` and the rooms fall back to the skinned meshes `Cat.usdz` / `CatStanding.usdz`
  **[code: `Scene/SplatLoader.swift`, `Scene/CatRoom.swift` `loadMochi`]**. On an iOS 27 phone with an A14 or
  later GPU the cat is a Gaussian splat of about 131,000 splats (`Mochi.ply` is 7.3 MB at 56 bytes a splat; four
  bodies of that size are loaded, one drawn at a time). RealityKit draws splats "during the transparency render
  pass, blending splats back-to-front", and "rendering cost correlates with splat count and overdraw" **[docs]**.
  None of that cost has ever been measured.
- **The Energy readout is CPU time of our process only** (`task_info`, `EnergyMeter.busySeconds`)
  **[code: `Perf/PerfLabViews.swift`]**. It does not see GPU time, the display, or the system compositor
  (`backboardd`), which blends our transparent room layer over the backdrop and draws the Liquid Glass bars over
  it every frame. A phone's heat is mostly GPU + display + SoC together; a Mac's GPU hides all of it.
- **Bloom is compiled only with the iOS 27 SDK and runs only on iOS 27** (`addBloom`) **[code]**. Whether the
  measured Simulator had it is not recorded.
- The odd result "lights off costs more" is a warning that the Simulator's renderer does not behave like the
  phone's. Do not rank options by Simulator CPU alone.

So the 35 is a floor, not the bill. Section 2 ranks causes for the phone, not for the Simulator.

### 1.2 Nothing in the room is ever still

Read from `CatRoom.tick`, `DioramaScene.tick`, `DioramaView` **[code]**:

- `pivot.orientation = .y(yaw + 0.035 * sin(t * 0.35))`: the whole room sways every frame. Every entity's world
  transform changes every frame, and the sun hangs on `root`, not on `pivot`, so the room turns under the sun
  and its shadow map is new every frame.
- 26 fairy bulbs get a new scale every frame; the flame every frame; the candle's `PointLightComponent` is
  re-set every third frame.
- `ZoomRig.update` calls `camera.look(at:from:)` every frame; the bubble point is projected every frame.
- The cat breathes; `SplatSkinner.run` skips a pass only while every bone is within `2e-4` of the last skinned
  pose, so slow breathing skips most frames and any tail or ear motion does not.
- `HeartBubble` runs `.repeatForever()`; it stays in the hierarchy off-World because `BubbleSpot.point` keeps
  its last value and the overlay only checks `point != nil` (the 1 x 1 view has `opacity(0)`, not removal).

With `RealityView` this does not matter for the frame count (it draws every frame regardless), but it means
"render only when something changed" has nothing to skip until the idle motion is made coarse.

## 2. Root causes, ranked

| # | Cause | Why plausible | Cheapest confirmation |
| --- | --- | --- | --- |
| 1 | **RealityKit renders every display frame, with no public pause or cap**, in World and at 1 x 1 pt | Measured: 15 points with a paused root, 10-12 off-World. Apple DTS on limiting the frame rate: "There is not." On pausing an `ARView`: "file an enhancement request". Another developer saw ~30% CPU for a hidden non-AR `ARView` with an empty scene on iOS 18; FB15831006 is titled "Prohibitively high energy usage from RealityKit when idling" **[docs]** | Already confirmed by the paused-root measurement |
| 2 | **GPU cost of the splat cat on the phone**: ~131k alpha-blended splats sorted back to front, large on screen at zoom, plus a compute pass rewriting 4 MB of splat data | Splats are drawn in the transparency pass and cost scales with count and overdraw **[docs]**; never measured (1.1). The room sways, so the view of the splat changes every frame and a sort can never be reused **[guess: a forum report says culling is refreshed "on the next camera transform delta", which suggests RealityKit does skip work for a still view]** | On the phone: Labs switch "cat as mesh" (the fallback exists) and compare Metal HUD GPU ms and battery drop (section 5) |
| 3 | **Compositing outside our process**: a full-screen, non-opaque Metal layer over the SwiftUI backdrop, under Liquid Glass bars that re-sample it every frame | A changing layer under glass forces the glass to redraw each frame; the room layer is transparent, so it cannot go straight to the display **[guess]**. Invisible to our CPU readout | On the phone: existing Labs switch "Glass header and tab bar" off, battery drop A/B; Power Profiler shows GPU and display power separately |
| 4 | **Scene complexity**: ~80 shell boxes + 26 bulbs + garland (30 parts) + un-flattened furniture, each with its own material instance (`Clay.matte` makes a new one per call), a sun shadow, three point lights, IBL, grounding shadows on every furniture descendant | "RealityKit invokes a draw call for each mesh"; "merge meshes that share a material"; "the more lights and shadows ... the more work the fragment shader does" **[docs]**. Measured share: ~12 points of CPU in the Simulator | Labs "Room shell: Baked" (exists, `docs/baked-shell.md`) A/B with the Energy readout |
| 5 | **Dust motes**: a particle emitter simulated every frame | Measured: ~8 points | Done (#619) |
| 6 | **Per-frame work we add** (1.2): sway, bulbs, flame, camera, bubble, `HeartBubble` | Small CPU each, but they keep every RealityKit system dirty | Labs switch "still room" (no sway, no bulb pulse), Energy readout |
| 7 | **Not the room at all**: socket, sync, Live Activity updates, radios | The owner reports heat on other tabs too; cause 1 explains 10-12 points but not all heat **[guess]** | MetricKit daily payload (5.2): CPU and GPU time against foreground time, network transfer |

Ruled out or unlikely:

- **Cat brain**: measured, microseconds.
- **120 Hz ProMotion**: the app has no `CADisableMinimumFrameDurationOnPhone` key **[code: `apps/ios/project.yml`]**,
  so display links are capped at 60 Hz on iPhone **[memory]**, and a developer who set the key reports
  `RealityView` still at 60 fps **[docs: forum 762074, no Apple reply]**. Not verified on iOS 27; the Metal HUD
  shows the true rate. Do not add the key.
- **Texture format (ASTC)**: the room has one 2048² lightmap (baked path), small contact shadows and 256²
  polaroids. Compression saves memory, not heat here.

## 3. Options

### 3.1 Own the frame loop with `RealityRenderer` (the only route to "half" and to "~0 off-World")

`RealityView` and `ARView` give no pause, no cap and no render scale control over their loop. `RealityRenderer`
draws a RealityKit scene into a Metal texture when we call it, so the schedule is ours.

Verified **[docs]**:

- `RealityRenderer`: iOS 18.0+. "All RealityKit APIs for loading resources, creating entities and adding
  components are compatible and work with `RealityRenderer`."
- `init() throws`, `var entities: EntityCollection`, `var activeCamera: Entity?`,
  `var lighting: ImageBasedLight`, `var cameraSettings: CameraSettings` (`antialiasing: AntialiasingMode`,
  `colorBackground`, `isToneMappingEnabled`), `func update(TimeInterval) throws`,
  `func updateAndRender(deltaTime:cameraOutput:whenScheduled:onComplete:actionsBeforeRender:actionsAfterRender:) throws`,
  `func subscribe(to:on:componentType:_:)` (so `SceneEvents.Update` in `CatRoom.start` has a home).
- Output is an `MTLTexture`; forum answers show it feeding a `CAMetalLayer` drawable.

How it would be used:

1. A `UIView` backed by `CAMetalLayer` (or an `MTKView`), wrapped for SwiftUI inside `Room/`. Nothing outside
   the Room changes: `RoomHost(input:)`, `RoomControlling` and `RoomEvent` stay as they are.
2. One `RealityRenderer` owned by `RoomController` for the app's life. The rooms' `root` entities go in
   `renderer.entities`; the `PerspectiveCamera` of `ZoomRig` becomes `renderer.activeCamera`; the gradient
   `EnvironmentResource` goes to `renderer.lighting`.
3. A `CADisplayLink` drives it: `preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 30,
   preferred: 30)` for the idle room, 60 while a finger is down, she walks, or a game runs; `isPaused = true`
   when `RoomVisibility` is not `.visible` **[memory: long-standing public API]**. With `MTKView` the same is
   `preferredFramesPerSecond`, `isPaused`, `enableSetNeedsDisplay` **[memory]**.
4. Render scale is the drawable size we choose (`CAMetalLayer.drawableSize`): 2x on a 3x screen is 44% of the
   pixels. Clay shapes and splats hide the difference better than text would.
5. Off-World: the link is paused and nothing is called, so the cost is zero frames. The renderer and its
   entities are never removed, which is the condition the blank-room bug needs **[guess, see below]**.
6. Leaving World, or the cat asleep for a while: keep the last drawable on screen (a paused `CAMetalLayer` keeps
   showing its last frame) or copy it to a `UIImage`; this is the "still image" idea with no swap to get wrong.

Not verified, and each can sink the option; a spike on a real phone answers all of them in a day:

- Whether `RealityRenderer` on iOS 27 draws `GaussianSplatComponent`, `ParticleEmitterComponent`,
  `GroundingShadowComponent`, directional-light shadows, point lights, `BloomComponent`. The doc sentence above
  says components "work"; no page lists exceptions, and one forum thread on mixing splats into a custom pipeline
  ended without an answer.
- The exact `CameraOutput` initializer. **[memory]**: `RealityRenderer.CameraOutput(.singleProjection(colorTexture:))`;
  the docs page fetched today lists the type but not its initializers.
- Taps. `.targetedToAnyEntity()` needs a `RealityView`. The room's targets are seven boxes and the polaroid
  cards (`CatRoom.tappable`), so a ray from the camera through the touch point against those boxes is 30 lines
  of our own maths; `Scene.raycast` may also work on `entity.scene` but is not verified under a
  `RealityRenderer`. The bubble's `content.project` becomes the camera's own projection matrix.
- That the GPU resources of entities held by a renderer that is not being ticked survive minutes or hours. This
  is the same family as the #618 bug, and the reason this must be tested with a 10-minute trip to another tab
  before anything else is built on it.
- That an idle `RealityRenderer` costs nothing while not called. Expected (there is no loop but ours), not
  measured.
- The UI tests' stand-in and the perf census keep working (`ScreenFrames`, `nextFrame` count `room.frame`,
  which still ticks).

Expected saving: World idle at 30 fps and 2x scale should be under half of today's CPU and well under half of
the GPU work; off-World and covered go to ~0. Risk: medium-high; it replaces the view layer of a sealed module
and depends on unverified component support. Size: one spike (a Labs switch "Room renderer: view / own loop"),
then a real change.

### 3.2 Stay on `RealityView`, draw less each frame (cheap, bounded)

None of these touches the 15-point loop; together they attack the other ~20 and the unmeasured GPU side.

| Change | API | Expected | Risk |
| --- | --- | --- | --- |
| Motes off by default, or on only at `thermalState == .nominal` and not in Low Power Mode | existing `showMotes` | -8 points (measured) | The room loses some life; owner's call |
| Turn off effects we do not use | `content.renderingEffects` on `RealityViewCameraContent` (iOS 18+): `antialiasing: AntialiasingMode`, `dynamicRange`, `motionBlur`, `depthOfField`, `cameraGrain` **[docs]**; case names (`.none`, `.disabled`, `.standard`) not verified | Unknown, GPU side; MSAA off is the likely gain | Edges of clay boxes alias; check by eye |
| Baked shell as the default | exists (Labs "Room shell") | Fewer draw calls and, in the City, fewer lights; the Room keeps its lights because the furniture is live | Listed in `docs/baked-shell.md`; needs the bake kept current |
| Flatten the furniture | `Entity.loadModel(named:in:)` / `ModelEntity(named:in:)`, which "automatically flattens the model" **[docs]**, instead of `Entity(named:)`; the `Glow_` parts need a split first | Fewer entities and draw calls | Named parts disappear when flattened; glows must be separate files |
| Share materials | one `Clay.matte` instance per tone, not per call | Lets RealityKit batch; unknown size | None |
| Still room when idle | drop the 0.035 rad sway and the bulb pulse, or step them at 10 Hz | CPU small; may let RealityKit reuse shadow and splat sorting **[guess]** | Room feels flatter; A/B by eye |
| Fewer splats | prune and cull low-opacity splats in `make_splat.py` ("reduce splat count through pruning", "culling low-opacity splats" **[docs]**); target half | GPU, roughly linear in count and overdraw | Fur quality; needs a look on the phone |
| Splat sort mode | `GaussianSplatResource.sortingMode`: `.depth` or `.distance` **[docs]**; which is cheaper is not documented | Unknown | None |
| Bubble | clear `BubbleSpot.point` when the room is not visible, so `HeartBubble`'s `repeatForever` leaves the hierarchy | Small, off-World | None |

Honest ceiling: this path can bring World idle from ~35 to ~20 in the Simulator's terms (motes 8, part of the
12) and an unknown but probably larger share of the phone's GPU load. It cannot reach "half" on CPU alone and it
does nothing for off-World.

### 3.3 Off-World to ~0 without the rewrite (experiments, not known to work)

The 1 x 1 view exists because a `RealityView` that goes away frees GPU resources a few seconds later and
re-attached entities then draw nothing. Two cheap questions decide whether there is a shortcut:

1. **Is the trigger the view leaving the window, or the view being destroyed?** Host the `RealityView` in a
   `UIHostingController` that `RoomController` retains, and on leaving World call `view.removeFromSuperview()`
   while keeping the controller. If the frame loop stops off-window and the room draws again after a 10-minute
   trip, off-World is ~0 for an afternoon's work. Unknown either way; the forum report of 30% CPU for a hidden
   `ARView` says hiding alone does not stop the loop, and says nothing about leaving the window.
2. **Does a rebuilt room draw?** Destroy the view and build new entities and resources on return (not
   re-attach), under a still image. This needs every cache dropped (`Meshes.boxes`, the shared `Mochi` rigs,
   `CatRoom.bodies`) and costs the City's main-thread build on every return. Only worth it if 1 fails and 3.1 is
   rejected.

`ARView(frame:cameraMode:.nonAR, automaticallyConfigureSession:false)` is not a way out: same loop, no pause
**[docs]**. It adds `renderOptions`, `contentScaleFactor` and `snapshot(saveToHDR:completion:)` **[docs]**, none
of which stops frames.

### 3.4 Adapt to heat and Low Power Mode

- `ProcessInfo.processInfo.thermalState` with `ProcessInfo.thermalStateDidChangeNotification`;
  `isLowPowerModeEnabled` with `.NSProcessInfoPowerStateDidChange` **[memory; both already read in
  `EnergyMeter` and `ShopKit`]**. A feature may not use `NotificationCenter` (AGENTS.md), so the app target turns
  them into a value on `RoomInput`, as `motes` is today.
- Tiers: `nominal` full; `fair` or Low Power Mode: motes off, still room, no bloom; `serious`: 30 fps and 1.5x
  scale (needs 3.1), mesh cat or a still cat; `critical`: a still image of the room.
- This limits the damage; it reacts after the phone is already warm. It does not replace 3.1 or 3.2.

### 3.5 Other renderers

- **SceneKit**: has `SCNView.isPlaying`, `rendersContinuously`, `preferredFramesPerSecond` **[memory]**, which is
  exactly the control missing here, but no Gaussian splats and it is in maintenance. A rewrite of every scene.
- **Own Metal renderer**: full control, and a splat renderer, clay PBR, shadows and particles to write. Not
  proportionate.

## 4. Recommended path

Smallest first. Each step is a Labs switch or a measurement, so a TestFlight build answers it on the owner's
phone. "Readout" is Labs → Performance → Energy line (`CPU n% · room … · heat`), read after 60 s still.

| # | Experiment | Expected | Risk | Measure |
| --- | --- | --- | --- | --- |
| 0 | **Make the phone measurable** (section 5): Metal HUD key in Labs builds, MetricKit payload in Labs, battery-drop and time-to-`fair` in the Energy readout, per-thread CPU | No saving; turns every later step from a guess into a number | Low | - |
| 1 | Phone A/B with switches that exist or are trivial: motes off; glass bars off; baked shell; **cat as mesh instead of splat** (new switch, the fallback path exists) | Tells which of causes 2, 3, 4 is the bill. Motes -8 CPU | Low | Readout CPU; HUD GPU ms and fps; battery % per 10 min |
| 2 | `renderingEffects`: antialiasing off, HDR off, the unused effects off | GPU, unknown; free if it shows | Low; aliasing by eye | HUD GPU ms |
| 3 | Still room when idle (no sway, bulbs at 10 Hz), `HeartBubble` out when hidden | 1-3 CPU; possibly more GPU if RealityKit reuses the sort | Low | Readout, HUD |
| 4 | Off-World: retained off-window host (3.3, question 1) | 10-12 → ~0 if it works | Low to try; the blank-room bug is the failure, so the test is a 10-minute tab trip, three times | Readout on Shop: CPU and `room off` |
| 5 | **Spike: `RealityRenderer` into a `CAMetalLayer` behind a Labs switch**, Living room only, 30 fps idle, 2x scale, paused off-World | World idle to under half; off-World and covered ~0 | Medium-high; unverified component support, taps by our own ray | Readout CPU, HUD fps = 30 and GPU ms, battery % per 10 min, the 10-minute trip |
| 6 | If 5 holds: move the rooms onto it, add the thermal tiers (3.4), delete the 1 x 1 view | The target | The Room's tests and perf census | perf.yml cost job + the phone |
| 7 | If the mesh-cat A/B in step 1 shows the splat is the bill: prune to half, compare sort modes | GPU roughly halves for the cat | Fur quality | HUD GPU ms at full zoom |

If step 4 works and step 1 shows the GPU side is small, steps 5-6 can wait. If step 5 fails on component
support, the fallback is 3.2 in full plus 3.4, and Feedback to Apple citing FB15831006.

## 5. Measuring on a phone that is not on the Mac

### 5.1 Metal Performance HUD (fps and GPU ms on screen)

- Add `MetalHudEnabled` = `YES` to the Info.plist of Labs builds. Apple: the HUD shows "for your own
  applications; that is, applications you have installed via Xcode or using TestFlight" **[docs]**. The
  spelling matters (`MetalHudEnabled`, not `MetalHUDEnabled`, per a forum thread).
- Or Settings → Developer → Graphics HUD, which needs Developer Mode on the phone.
- It is the only cheap way to see the true frame rate of the RealityKit layer (our `FrameMeter` times its own
  display link, not RealityKit's) and GPU time per frame.
- Not verified: that the HUD attaches to RealityKit's layer in a TestFlight build on iOS 27.

### 5.2 MetricKit (daily totals, no cable, no service)

- `MXMetricManager.shared.add(subscriber)`; `didReceive(_ payloads: [MXMetricPayload])` at most once a day
  **[docs]**; collected for TestFlight builds **[docs: WWDC20 10081]**.
- `payload.gpuMetrics?.cumulativeGPUTime` (`MXGPUMetric`, iOS 13+ **[docs]**),
  `cpuMetrics?.cumulativeCPUTime`, `applicationTimeMetrics?.cumulativeForegroundTime`, network transfer
  **[memory for the last two]**. GPU time ÷ foreground time is the GPU duty the Simulator cannot show.
- Show `payload.jsonRepresentation()` in Labs with a copy button. No upload needed.

### 5.3 Extend the Labs Energy readout

- **Battery drop**: `UIDevice.current.isBatteryMonitoringEnabled = true`, `batteryLevel` at start and after 10
  minutes, unplugged, fixed brightness **[memory]**. Coarse (1% steps) but it is the only number that includes
  GPU, display and radios. This is the A/B metric for every step above.
- **Time to `fair`**: seconds from a cold phone until `thermalState` leaves `.nominal`.
- **Per-thread CPU**: `task_threads` + `thread_info(THREAD_BASIC_INFO)` + `pthread_getname_np` **[memory;
  public Mach calls, the readout already uses `task_info`]**: splits main thread, RealityKit's render thread
  and the rest, so "the loop" and "our tick" stop being one number.
- **Splat skinning**: `SplatSkinner.stats` (passes, skipped, GPU ms) already exists; print it.

### 5.4 Power Profiler on the device (iOS 26+)

Settings → Developer → Performance Trace → on, mode Power Profiler; add the Performance Trace control to
Control Center; tap to start and stop; share the trace file from Settings (AirDrop); open in Instruments on any
Mac **[docs]**. It records up to 10 hours and splits power into CPU, GPU, display and networking. Needs
Developer Mode; whether a TestFlight-only phone offers the Developer Mode switch without ever meeting Xcode is
not verified.

### 5.5 Later, with the phone on a Mac

- Instruments: Game Performance or Metal System Trace (frame time, GPU time per pass), Time Profiler filtered
  to the render thread, Power Profiler tethered **[memory]**.
- Xcode: Debug → Capture GPU Workload on the room: draw call count, the shadow pass, the transparency pass
  with the splats, overdraw **[memory]**. Whether RealityKit's passes are labelled in a capture on iOS 27 is
  not verified.
- `ARView.debugOptions` statistics do not apply to `RealityView`.

## 6. What not to do

- **Do not remove the `RealityView` off-World again** without the 10-minute test passing: that is the blank-room
  bug (#618).
- **Do not trust Simulator CPU for anything about the splat, bloom, glass or lights.** It draws a mesh cat on a
  Mac GPU. Rank by phone numbers once section 5 exists.
- **Do not turn off the sun shadow or the point lights for speed**: measured slower, and the contact shadows
  are already baked.
- **Do not use `ARView.__preferredFrameRate` or any underscored API**: private in practice, and it measured
  nothing.
- **Do not add `CADisableMinimumFrameDurationOnPhone`**: it can only raise the rate.
- **Do not move to `ARView`** for this: same loop, no pause, an older API.
- **Do not spend time on ASTC, texture sizes or the cat brain**: not where the heat is.
- **Do not ship thermal tiers as the fix**: they hide the base cost and the owner's phone is hot before they
  act.
- **Do not rewrite in SceneKit or raw Metal** before the `RealityRenderer` spike has failed on the phone.
- **Do not build "render on demand" on `RealityView`**: it has no way to skip a frame, and the room is never
  still anyway (1.2).

## 7. Not verified

- Any number on a real phone. Everything in section 1 is the Simulator.
- `RealityRenderer` with splats, particles, grounding shadows, bloom, lights on iOS 27; its `CameraOutput`
  initializer; resource survival while idle; `Scene.raycast` under it.
- Whether RealityKit reuses the splat sort or shadow map for a still scene.
- Enum case names of `RealityViewRenderingEffects` members.
- The true frame rate of `RealityView` on a ProMotion phone under iOS 27.
- That `MetalHudEnabled` shows the HUD over RealityKit content in TestFlight builds; that Developer Mode can be
  switched on without Xcode.
- Apple's forum answer on splats says changing the buffer at runtime is "I don't think ... supported", while
  the `GaussianSplatResource` page says "you can update the contents of the underlying `LowLevelBuffer`
  instances to animate the splats over time". The page is the later and more specific source; our skinning
  depends on it.
- `project.yml` still says `deploymentTarget: iOS 18.0` while the brief says iOS 26+. Every API in 3.1 and 3.2
  is iOS 18+, so it does not matter here.

## 8. Round 2: splat cost, throttling and adaptive quality

Added after section 7. Everything here is a Labs switch or follows the phone's heat; nothing was measured on a
phone, and the Simulator cannot draw splats, so the Simulator can only show that nothing else regressed.

### 8.1 What shipped

| Change | Where | Default | Why it should help |
| --- | --- | --- | --- |
| **Splat pruning at load**: the least important splats (opacity times covered area, `SplatPruning`) are dropped, the rest enlarged by half the volume-conserving amount. Levels: `balanced` keeps 55% (~72k), `light` keeps 40% (~52k). The skin rows follow the kept splats. The pinned PLY and skin files are untouched; coats are cut from the whole file and pruned the same way | `SplatReduction.swift`, `RoomInterface/SplatDetail.swift` | Full (131k), unless the phone is warm or in Low Power Mode at launch, or Labs asks | Fragment cost and sort cost fall roughly with count |
| **Skinning/sort rate limit**: `SplatSkinner` runs at most N times a second, so RealityKit sees a changed buffer, and re-sorts, at that rate | `CatRig.swift` (checksum in `apps/ios/nooki-cat.sha256` updated) | Every frame; 30 Hz at `fair`, 20 Hz at `serious`, 15 Hz at `critical` | Halves the compute pass and, if RealityKit sorts only on a changed buffer, the sort. The pass already skipped when no bone moved |
| **Quality tiers**: `RoomQualityPolicy` maps `thermalState` and Low Power Mode to `full`, `fair`, `serious`, `critical`; degrades at once, recovers one step after 90 s of calmer readings | `RoomInterface/RoomQuality.swift`, `QualityMonitor` in `Perf/PerfLab.swift` | On, every build | `fair`: motes, antialiasing and the backdrop drift off, splats 30 Hz, pruned on the next launch or reload. `serious`: also no sway and bulb pulse, 20 Hz. `critical`: the room is held on its last frame (the covered state) |
| **Labs tier picker**: the current tier and a control that forces one | Labs → Performance | Auto | Lets the owner see each tier's cost without a hot phone |
| **Backdrop drift switch** (`drift`): the bokeh behind the room, 10 Hz, redrawn under the room layer and the glass | Labs, `HomeView` | On | The one SwiftUI animation that runs behind the room; off isolates the compositor cost |
| New switches `splatLean` (55%, next launch) and `splatRate` (30 Hz) | Labs | Off | A/B on the phone |

Not changed, with the reason:

- **Splat sort mode** stays as it is; which of `.depth` and `.distance` is cheaper is undocumented.
- **Screen-size LOD** (fewer splats when the cat is small in frame) is not built: the `GaussianSplatResource` buffers
  are fixed at load, so a live change means swapping resources, which the Simulator cannot exercise. Pruning at load
  by tier covers the same ground without a swap. Revisit only if the phone shows the splat is the bill and 55% is not
  enough.
- **Compositing**: the room layer is non-opaque on purpose. The walls do not fill the view (the City's window hole,
  the margins around the shell) and the warm backdrop shows through, so `isOpaque` would change the picture. The
  bars are the system's Liquid Glass over it, which cannot be made cheaper from our side except by the existing
  switch. The only per-frame work behind the room is the 10 Hz bokeh, now switchable. Nothing over the room uses
  `compositingGroup` or `drawingGroup`; the Flatten switch applies to pages only.
- **Static batching, baked light pools and one static shadow** are not done in this round. They touch
  `DioramaScene` placement code that the furniture-placement work is changing, and a merged mesh breaks
  per-piece selection while arranging. The plan: batch only the shell and fixed furniture after the layout settles,
  keep placed pieces as entities, bake the string-light and flame pools with `tools/scene-bake/contact_shadow.py`
  and `RoomBake` and delete the point lights. Do it after the phone A/B below says draw calls and lights, not the
  splat, are the bill (section 2, causes 2 and 4).

### 8.2 Phone test plan (TestFlight Labs build)

Fixed conditions: unplugged, same brightness, Wi-Fi, app freshly launched, Home open and left alone. Read each line
after 60 s still (the Energy line), and let the battery number run 10 minutes per step. After each step use Labs →
Performance → Copy settings and paste it back; the line carries the switches, the tier, fps, CPU, heat and the battery
slope. Turn the Metal HUD on once (next launch) to see fps and GPU ms.

| Step | Flip | Compare | Reading |
| --- | --- | --- | --- |
| 0 | Nothing, tier Auto | Baseline | CPU, HUD GPU ms, battery/10 min |
| 1 | "Cat as splats" off (relaunch) | Is the splat the bill? | GPU ms and battery against step 0 |
| 2 | Back on; "Cat splats cut to 55%" on (relaunch) | Pruning's gain; look at the fur at full zoom for holes | GPU ms, by eye |
| 3 | "Cat splats updated at 30 Hz" on | Skin and sort throttle; look for judder when she walks | GPU ms, by eye |
| 4 | Tier forced `fair`, then `serious`, then `critical` | Cost of each tier; `critical` is the floor with the room frozen | Battery and GPU ms per tier |
| 5 | Auto again; "Backdrop bokeh drift" off, then "Glass header and tab bar" off | Compositor share | Battery |
| 6 | "Antialiasing" and "HDR" toggled | Per-pixel cost | GPU ms |
| 7 | "Room sway" off | Whether a still room lets RealityKit reuse work | GPU ms |

How to read it: the step with the largest battery/GPU drop is the next thing to build. If step 1 saves little, the
splat is not the bill and the batching and light work (8.1, last bullet) is next. If steps 1 to 3 save most of it,
ship pruning at 55% as the default and re-run.

## 9. Room and furniture audit

Numbers are from Labs → Performance → Room stats on a Simulator (iPhone 17 Pro, iOS 27.2, Debug), so the cat is her
mesh stand-in there: the triangle counts include her 131k-splat mesh and are far above a phone's. The counts of
entities, parts, lights and shadows do not depend on that. Nothing here is a GPU measurement.

### 9.1 What the scenes hold

| | Living room | Bedroom |
| --- | --- | --- |
| Entities enabled (+ disabled) | 191 (+12) | 270 (+0) |
| Models / mesh parts (draw units per pass) | 106 / 176 | 236 / 236 |
| Distinct materials by value / slots | 87 / 181 | 64 / 236 |
| Directional lights (with a shadow map) | 1 (1) | 2 (1) |
| Point lights | 3 (window 1800 lm r 1.1, lamp 700 r 0.7, candle 450 r 0.6) | 4 (sky 2500 r 1.2, lamp 2200 r 1.1, fairy 900 r 1.0, candle 500 r 0.5) |
| Image-based light | 1 | 1 |
| Grounding shadows (cast, receive) | 51, 51 | 0 |
| Contact blobs | 9 (+10 plates, off until selected) | 0 |
| IBL receivers | 171 | 263 |

Stowing the window seat removed 8 entities, 32 parts and 4 grounding shadows: cost scales with the pieces' parts, not
with the pieces.

### 9.2 Ranked findings

| # | Finding | Est. impact | Switch |
| --- | --- | --- | --- |
| 1 | The sun's shadow map redraws every shadow-casting model from the light each frame the room renders (both rooms; size is not settable, `maximumDistance` is 4 m for a 1 m room). Draw calls roughly double | High on GPU and `encodeDrawCalls` | `noSunShadow` |
| 2 | Living room has 176 parts and Bedroom 236, each drawn at least once, plus again in the shadow pass; the 10 base pieces carry 62 material parts that never move outside Decorate | High (CPU encode, shadow pass) | `mergeFurniture` |
| 3 | Dynamic lights: 4 in the Living room, 6 in the Bedroom. Every light adds to the per-fragment loop and the light constant buffers; the Bedroom rewrites all of them whenever the hour moves 0.1 h | Medium-high | `fewerLights` |
| 4 | 9 transparent blob quads, each its own blended draw, plus 51 grounding shadows | Medium | `bakedBlobs` (blobs); grounding shadows fall with merging |
| 5 | Bloom (iOS 27 only, unbounded scope): a full-screen downsample chain | Medium on GPU, if the phone is on iOS 27 | `noBloom` |
| 6 | Living room pulse runs while `swaying` is true, which is the setting, not idleness: flame scale at 30 Hz, candle light intensity at 15 Hz (a light update), 26 bulb scales at 10 Hz, in an idle room | Medium (keeps the light data dirty) | `sway` (existing) |
| 7 | Bedroom tick every frame: `Calendar.dateComponents` and `Daylight.sample`, two clock-hand orientation writes (a same-value write still dirties the subtree), 12 projections for the window | Low-medium CPU; keeps the scene dirty. Not changed here: Bedroom code is being reworked | none |
| 8 | Sway rewrites `pivot.orientation` each frame while active, so every descendant transforms; scales with entity count (191 / 270) | Low-medium while she walks or a finger is down; idle is already still (`SwayEnvelope`) | merging cuts the entity count |
| 9 | `showDecor` recomputes occupancy and cat routes per input change (not per frame) | Low | none |

Already fine: the camera pose is guarded against rewrites, the pivot turns only when the yaw changed, motes and AA are
off by default, a covered or hidden room does not render, and `ownLoop` caps an idle room at 30 fps. A scene-tick cap
was not added: the tick is cheap next to the render, and `ownLoop` is the cap.

### 9.3 Labs switches (all off by default, runtime toggles)

`mergeFurniture` bakes the opaque plain-PBR parts of the stage's pieces into one mesh per material and shadow
behaviour while the player is not arranging; opening Decorate or changing the layout puts every piece's own model back
at once, and the merge is rebuilt after 0.4 s of stillness. `bakedBlobs` replaces the 9 blobs with one 512 px layer.
`noSunShadow` removes the shadow component from every directional light. `fewerLights` keeps each room's widest point
light. `noBloom` removes the bloom pass. Tests count each switch with the room stats and check that switching back
restores the scene.

### 9.4 Phone steps

Labs → Performance: Refresh room stats, Copy settings (baseline). Flip one of `noSunShadow`, `fewerLights`,
`mergeFurniture`, `bakedBlobs`, `noBloom` at a time, leave Home alone for 60 s, Copy settings, paste it back, and flip
it off again. The line holds the switches, fps, CPU, heat, battery slope and the room stats.

## Sources

- [RealityRenderer](https://developer.apple.com/documentation/realitykit/realityrenderer),
  [CameraSettings](https://developer.apple.com/documentation/realitykit/realityrenderer/camerasettings-swift.struct)
- [RealityViewCameraContent](https://developer.apple.com/documentation/realitykit/realityviewcameracontent),
  [RealityViewRenderingEffects](https://developer.apple.com/documentation/realitykit/realityviewrenderingeffects)
- [ARView](https://developer.apple.com/documentation/realitykit/arview)
- [GaussianSplatComponent](https://developer.apple.com/documentation/realitykit/gaussiansplatcomponent),
  [GaussianSplatResource](https://developer.apple.com/documentation/realitykit/gaussiansplatresource),
  [SortingMode](https://developer.apple.com/documentation/realitykit/gaussiansplatresource/sortingmode-swift.enum)
- [Reducing CPU utilization in your RealityKit app](https://developer.apple.com/documentation/realitykit/reducing-cpu-utilization-in-your-realitykit-app),
  [Reducing GPU utilization in your RealityKit app](https://developer.apple.com/documentation/realitykit/reducing-gpu-utilization-in-your-realitykit-app)
- Forums: [How to limit RealityKit's framerate?](https://developer.apple.com/forums/thread/704886),
  [How can I pause ARView?](https://developer.apple.com/forums/thread/763551),
  [Allow RealityView to render at 120 fps?](https://developer.apple.com/forums/thread/762074),
  [GaussianSplatComponent: dynamic buffer updates, splat-count limit](https://developer.apple.com/forums/thread/831663),
  [GaussianSplatComponent: stale visibility set](https://developer.apple.com/forums/thread/838974),
  [Building a custom render pipeline with RealityKit](https://developer.apple.com/forums/thread/761846)
- [MXGPUMetric](https://developer.apple.com/documentation/metrickit/mxgpumetric),
  [MXMetricManager](https://developer.apple.com/documentation/metrickit/mxmetricmanager)
- [Monitoring your Metal app's graphics performance](https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance),
  [Enable Metal Performance HUD on iPhone & iPad?](https://developer.apple.com/forums/thread/760649)
- [Measuring your app's power use with Power Profiler](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler),
  [WWDC25 session 226](https://developer.apple.com/videos/play/wwdc2025/226)
