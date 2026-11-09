# iOS performance: rules and audit

How Ourio (`apps/ios`) should spend its frame, its memory and its launch, and where it doesn't today.
Part A is the rules, each with its source. Part B checks our code against them, ranked.

Read this before you change the room, the cat, the window views, or a scrolling screen.

**How far to trust the numbers.** The rules come from Apple's documentation and WWDC sessions
2020–2025. Claims that rest on forums, third parties or our own reasoning are tagged `[unverified]`
or `[inference]`. In Part B, counts (entities, texture sizes, splat counts) come from the code and
the bundled assets. Every millisecond and megabyte figure there is an estimate until it has been
measured; the "Measure" column says how.

**Where to measure.**

- The CI Simulator (`perf.yml`, macos-26) has no Apple7 GPU and an Xcode 26 SDK. It draws the mesh
  cat, not the splats, and it has no bloom.
- So CI numbers cover the room, the window, the mesh cat and the UI. Splat and bloom findings need a
  phone: Instruments RealityKit Trace, Metal System Trace and Allocations, in a Release build with no
  debugger attached.
- Simulator numbers only show trends (A/B on the same runner). Thermal and energy behaviour only
  shows on a device (§4.4).

## Part A: rules

### 1. Scenes (RealityKit / Metal)

#### 1.1 Frame budget
- **Keep main and render threads at about 12 ms or less on average, below the 16.6 ms limit for 60 fps.** At 60 fps, going over 16.6 ms drops frames. Even under it, a slow render thread makes RealityKit drop frames. Running near the limit also makes thermal throttling more likely. ([RealityKit: Reducing CPU utilization](https://developer.apple.com/documentation/realitykit/reducing-cpu-utilization-in-your-realitykit-app))
- **At 120 Hz, each stage of the pipeline gets 8.3 ms.** Main thread, render server CPU and GPU each have about one vsync interval. ([Understanding hitches in your app](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app))
- **Find out first whether you are CPU-bound or GPU-bound, then use the matching guide.** The fixes are different for each. ([Improving the performance of a RealityKit app](https://developer.apple.com/documentation/realitykit/improving-the-performance-of-a-realitykit-app))

#### 1.2 Entities, draw calls, merging, instancing, LOD
- **Count about one draw call per mesh part and material.** Each call costs CPU to set up. Instancing gives one call per material for all instances. ([Reducing CPU utilization](https://developer.apple.com/documentation/realitykit/reducing-cpu-utilization-in-your-realitykit-app); [visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos))
- **As a budget reference, Apple's visionOS figures are under about 250 draw calls and 250k vertices/triangles (Shared Space), or 500 / 500k (Full Space).** These are the only numbers Apple publishes. iPhone is a single view at a lower resolution, so a small room should sit far below them. ([visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos))
- **Merge static props that share a material, but don't merge parts that are far apart.** RealityKit culls whole meshes, so a mesh that is partly visible is drawn in full. ([Reducing CPU utilization](https://developer.apple.com/documentation/realitykit/reducing-cpu-utilization-in-your-realitykit-app))
- **Flatten entity hierarchies unless you need the children in code.** ECS work runs every frame for every entity that has the relevant components. `loadModel` flattens automatically. ([Reducing CPU utilization](https://developer.apple.com/documentation/realitykit/reducing-cpu-utilization-in-your-realitykit-app))
- **Use `MeshInstancesComponent` (iOS 26) for repeated meshes such as books, plants or tiles, not cloned entities.** The mesh and materials go to the GPU once. Split very large instance sets across a few entities so culling still works. ([WWDC25 287 What's new in RealityKit](https://developer.apple.com/videos/play/wwdc2025/287/))
- **Measure before you replace merging with instancing.** An Apple engineer says the benefit depends on the scene. ([Forums 831723](https://developer.apple.com/forums/thread/831723)) `[unverified: forum]`
- **RealityKit has no automatic mesh LOD. Swap `ModelComponent.mesh` yourself by camera distance or zoom level, and keep the simple fallback mesh.** I found no LOD API in the docs. ([RealityKit docs](https://developer.apple.com/documentation/realitykit)) `[unverified]`
- **Lower polygon counts on background props first, especially when they cast shadows.** Reserve detail for what the user looks at. ([Reducing GPU utilization](https://developer.apple.com/documentation/realitykit/reducing-gpu-utilization-in-your-realitykit-app))

#### 1.3 Materials, transparency, blending
- **Use PBR only for small opaque objects. Use `UnlitMaterial` or a custom unlit material with baked lighting for large or transparent surfaces** such as walls, window glass and the sky behind the window. PBR's environment lighting is expensive on large or transparent content. ([visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos); [WWDC23 10100](https://developer.apple.com/videos/play/wwdc2023/10100/))
- **Avoid stacked transparent layers that cover a lot of the screen.** The fragment shader runs once per layer on every covered pixel. ([Reducing GPU utilization](https://developer.apple.com/documentation/realitykit/reducing-gpu-utilization-in-your-realitykit-app))
- **Use `ModelSortGroupComponent`, with `depthPass: .prePass` where needed, to fix the order of transparent parts** (window glass in front of the life layers, splat in front of the room). It sets a deterministic order without extra entities. ([ModelSortGroupComponent](https://developer.apple.com/documentation/realitykit/modelsortgroupcomponent))
- **Animate material parameters on a single retained material.** Building new materials each frame causes allocations and overhead. ([visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos))
- **Preload assets with custom materials, because their shaders compile at runtime.** Otherwise the first use hitches. ([visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos))

#### 1.4 Textures and texture memory
- **Cap textures at 2048 px per side on iPhone and use power-of-two sizes.** Apple says larger gives no benefit there. ([Reducing GPU utilization](https://developer.apple.com/documentation/realitykit/reducing-gpu-utilization-in-your-realitykit-app))
- **Budget memory as channels × width × height × 4/3.** RealityKit generates mipmaps automatically. A 2048² RGBA PNG takes about 22 MB uncompressed. ([Reducing GPU utilization](https://developer.apple.com/documentation/realitykit/reducing-gpu-utilization-in-your-realitykit-app))
- **Atlas small textures together, and mix resolutions across one mesh.** Fewer texture files means less memory. ([Reducing GPU utilization](https://developer.apple.com/documentation/realitykit/reducing-gpu-utilization-in-your-realitykit-app))
- **Export through Reality Composer Pro or `usdcrush` so textures are compressed.** RCP compresses on export. iOS 26 adds AVIF textures, which are smaller than JPEG and support 10-bit. ([visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos); [WWDC25 287](https://developer.apple.com/videos/play/wwdc2025/287/))
- **For textures created at runtime (life-layer snapshots), set `TextureResource.CreateOptions.mipmapsMode = .none` when the texture is never minified.** The default allocates and generates every mip level. ([TextureResource.MipmapsMode](https://developer.apple.com/documentation/realitykit/textureresource/mipmapsmode))
- **For textures that update every frame, use `LowLevelTexture` instead of regenerating a `TextureResource`.** It updates in place from the CPU or a Metal command buffer. ([WWDC24 10103](https://developer.apple.com/videos/play/wwdc2024/10103/)) `[inference: no perf numbers given]`
- **Which ASTC/KTX containers RealityKit loads directly is unverified.** Prefer the RCP/`usdcrush` pipeline over hand-rolled KTX. `[unverified]`

#### 1.5 Lights, shadows, render effects, bloom
- **Use few dynamic lights, and turn off shadow casting on props that don't need it.** Each light and shadow adds fragment work. Use `DynamicLightShadowComponent(castsShadow: false)`. ([WWDC24 10103](https://developer.apple.com/videos/play/wwdc2024/10103/); [Reducing GPU utilization](https://developer.apple.com/documentation/realitykit/reducing-gpu-utilization-in-your-realitykit-app))
- **Bake room lighting into textures and keep dynamic light for the cat only.** This matches Apple's unlit-plus-baked-lighting advice. ([visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos)) `[inference]`
- **Remove grounding shadows where a baked contact shadow is enough.** Apple lists them as an effect to drop when the GPU is under pressure. ([visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos))
- **Set each `content.renderingEffects` field (`antialiasing`, `dynamicRange`, `motionBlur`, `depthOfField`, `cameraGrain`) on purpose.** The defaults depend on GPU capability. Disabling effects saves GPU time and some render-thread CPU. Apple names shadows, HDR, motion blur, DoF and environment texturing as candidates. ([RealityViewRenderingEffects](https://developer.apple.com/documentation/realitykit/realityviewrenderingeffects); [Reducing GPU utilization](https://developer.apple.com/documentation/realitykit/reducing-gpu-utilization-in-your-realitykit-app); [Reducing CPU utilization](https://developer.apple.com/documentation/realitykit/reducing-cpu-utilization-in-your-realitykit-app))
- **Ourio uses RealityKit's built-in `BloomComponent` (iOS 27, `CatRoom.addBloom`), not a custom effect.** Its cost is Apple's to tune; ours is the scope (`.unbounded`, full screen) and leaving it on when nothing glows. The custom-effect rules below apply only if we ever write our own `PostProcessEffect`.
- **Write bloom in `PostProcessEffect.postProcess(context:)` with GPU work only: Metal compute, MPS or Core Image.** It runs every frame. It must write `targetColorTexture`, or nothing is displayed. ([PostProcessEffectContext](https://developer.apple.com/documentation/realitykit/postprocesseffectcontext); [PostProcessEffect](https://developer.apple.com/documentation/realitykit/postprocesseffect))
- **Create pipeline states and intermediate textures in `prepare(for:)`, not per frame.** That is the setup hook Apple provides for this. ([PostProcessEffect](https://developer.apple.com/documentation/realitykit/postprocesseffect)) Per-frame PSO or texture creation causes hitches. ([WWDC22 10102](https://developer.apple.com/videos/play/wwdc2022/10102/))
- **Do bloom at half or quarter resolution (downsample, blur, upsample), and reuse textures across frames.** A full-resolution multi-tap blur is the main cost of bloom. `[unverified: general practice; Apple gives no bloom numbers]`
- **To toggle bloom often, keep the effect registered and blit source to target when it is off.** Apple's doc shows this pattern. Set `customPostProcessing = .none` to remove it for good. ([PostProcessEffectContext](https://developer.apple.com/documentation/realitykit/postprocesseffectcontext))
- **Use `.dontCare` load/store actions and memoryless attachments for intermediate textures in your own Metal passes.** Apple GPUs are tile-based deferred renderers with no dedicated VRAM, so bandwidth is the scarce resource. ([WWDC20 10602 Harness Apple GPUs with Metal](https://developer.apple.com/videos/play/wwdc2020/10602/))

#### 1.6 Update loop: Systems vs SceneEvents.Update
- **Prefer a registered `System` with an `EntityQuery` for per-frame logic. Use `SceneEvents.Update` only for small, scoped closures.** Both run every frame. Systems run in dependency order, once per step, and keep state in components. ([System](https://developer.apple.com/documentation/realitykit/system); [RealityView](https://developer.apple.com/documentation/realitykit/realityview))
- **Do work in systems only when needed, not every frame.** Use `updatingSystemWhen:` and early exits. ([System](https://developer.apple.com/documentation/realitykit/system); [visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos))
- **Don't write to a component or transform unless the value actually changed.** Every write becomes an entity commit that the renderer has to process. ([visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos))
- **Create entities up front and toggle `isEnabled`. Don't add and remove them each frame.** Creating and destroying entities causes commit spikes. ([visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos); [WWDC23 10100](https://developer.apple.com/videos/play/wwdc2023/10100/))
- **Don't allocate in the update loop.** Avoid class instances, `any` existentials, closures, arrays and string formatting. Use generics and borrowed values on hot paths. ([WWDC24 10217 Explore Swift performance](https://developer.apple.com/videos/play/wwdc2024/10217/))
- **Don't route per-frame RealityKit state through SwiftUI `@Observable` or `@State`.** It triggers extra SwiftUI redraws. ([visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos); [WWDC23 10100](https://developer.apple.com/videos/play/wwdc2023/10100/))
- **Lower the update rate of code-driven animations, and touch fewer entities.** Cost scales with the number of entities changed per frame. ([visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos))
- **Use simple colliders with `isStatic: true`, and avoid recursive `generateCollisionShapes` for tap targets.** Many colliders are expensive. ([visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos))

#### 1.7 Animation (skeletal, blend shapes, baked)
- **Keep joint count, vertex count and weights per vertex low on the skinned cat.** Skinning runs as GPU deformers, and the cost grows with mesh complexity. ([Reducing GPU utilization](https://developer.apple.com/documentation/realitykit/reducing-gpu-utilization-in-your-realitykit-app); [visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos))
- **Attach props to joints with `Entity.attach(_:to:)` (iOS 26), not by copying transforms by hand each frame.** It avoids expensive hierarchical transform updates. ([WWDC25 287](https://developer.apple.com/videos/play/wwdc2025/287/))
- **Animate window "life" with baked clips or shader parameters, not per-frame transform writes on many entities.** Fewer entities touched means fewer commits. ([visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos)) `[inference]`
- **Relative cost of blend shapes vs skeletal animation is unverified.** Apple publishes no comparison. Profile with RealityKit Animations (CPU/GPU) in RealityKit Trace. `[unverified]`

#### 1.8 Gaussian splat cat
- **Ourio draws Mochi with RealityKit's `GaussianSplatComponent` (iOS 27, Apple7 GPUs; `SplatLoader.make`) and skins her with its own compute pass (`SkinSplats.metal`) into a `LowLevelBuffer`.** RealityKit owns the sort and the blend, so the levers we hold are splat count per pose, how often the buffer is rewritten, how many poses stay resident, and the file format. The engine-level rules below explain why those matter.
- **Splat cost has three parts: per-splat projection, a depth sort, and alpha-blended fill.** The reference renderer culls per 16×16 tile and uses a GPU radix sort. ([Kerbl et al. 2023, 3D Gaussian Splatting](https://arxiv.org/abs/2308.04079))
- **Fill rate is usually the limit on mobile.** Each splat is a blended quad with heavy overdraw, often dozens of fragments per pixel. Lowering render resolution is the most direct lever. ([PlayCanvas: Splat performance](https://developer.playcanvas.com/user-manual/gaussian-splatting/building/performance/))
- **Render the splat pass at a lower resolution scale, and do it before raising splat count.** Fragment count scales with pixels. PlayCanvas tells you to drop device pixel ratio and to disable MSAA for splats. ([PlayCanvas: Splat performance](https://developer.playcanvas.com/user-manual/gaussian-splatting/building/performance/))
- **Set a splat budget. PlayCanvas's mobile default is about 1M.** A single cat should be far below that. Prune offline: LightGaussian cuts splats by about 60% and storage by about 15× with little quality loss, and also distills SH to a lower degree. ([PlayCanvas: Splat performance](https://developer.playcanvas.com/user-manual/gaussian-splatting/building/performance/); [LightGaussian, NeurIPS 2024](https://arxiv.org/abs/2311.17245))
- **Use SH degree 0 or 1 on phone.** Higher SH bands multiply per-splat memory and shading cost. PlayCanvas offers an approximate SH mode for mobile. ([LightGaussian](https://arxiv.org/abs/2311.17245); [PlayCanvas GSplatComponent API](https://api.playcanvas.com/engine/classes/GSplatComponent.html)) `[inference for "0 or 1"]`
- **A CPU sort on a background thread lags behind fast camera moves. A GPU sort keeps step every frame and scales better.** This trade-off is documented for PlayCanvas's two renderers. ([PlayCanvas: Renderers](https://developer.playcanvas.com/user-manual/gaussian-splatting/rendering-architecture/renderers/))
- **Re-sort only when the view direction or position changed past a threshold, or the cat moved.** An idle orbit camera doesn't need a new sort every frame. `[unverified: common practice, not in a primary source]`
- **Keep the whole splat pipeline on the GPU (project, key, sort, draw) with no CPU readback in the frame.** A CPU wait on a GPU sort stalls the frame. ([Ghifary: 3DGS on Apple Silicon](https://ghifary.notion.site/Production-Grade-3D-Gaussian-Splatting-on-Apple-Silicon-with-Native-MPS-Kernels-30ca59d3736080febd77f45330e41f75)) `[unverified: third-party]`
- **Reorder splats spatially (Morton order) at load time.** It improves cache locality. MetalSplatter does this. ([dev.to write-up on MetalSplatter](https://dev.to/john-rocky/real-time-relighting-of-gaussian-splatting-reflections-on-iphone-metal-3b26)) `[unverified: third-party]`
- **Profile Metal splat code in Release with no debugger attached.** MetalSplatter reports Debug loads as over 10× slower and frame rates as lower with a debugger attached. ([MetalSplatter README](https://github.com/scier/MetalSplatter))
- **To draw splats inside RealityKit, feed instance data through `LowLevelMesh` or `LowLevelBuffer` updated by a Metal compute pass (`replace(bufferIndex:using:)`).** This keeps the data on the GPU without CPU copies. ([LowLevelMesh](https://developer.apple.com/documentation/realitykit/lowlevelmesh); [WWDC25 287](https://developer.apple.com/videos/play/wwdc2025/287/))
- **Ship a compressed format rather than raw `.ply`.** PlayCanvas recommends SOG over PLY for size and load time. A 7 MB float PLY is load and memory cost you pay every launch. ([PlayCanvas: Splat performance](https://developer.playcanvas.com/user-manual/gaussian-splatting/building/performance/))

#### 1.9 Frame pacing, idling, pausing
- **Add `CADisableMinimumFrameDurationOnPhone` only if you deliberately want 120 Hz.** It lets ProMotion iPhones run custom animations above 60 Hz, at an energy cost. ([CADisableMinimumFrameDurationOnPhone](https://developer.apple.com/documentation/bundleresources/information-property-list/cadisableminimumframedurationonphone); [Optimizing ProMotion refresh rates](https://developer.apple.com/documentation/quartzcore/optimizing-promotion-refresh-rates-for-iphone-13-pro-and-ipad-pro))
- **Request rates through `CADisplayLink.preferredFrameRateRange` or `CAFrameRateRange` for your own Metal or Canvas loops, and ask for a low rate when idle.** The display drops its refresh rate when nothing changes. ([Understanding hitches](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app); [Optimizing ProMotion refresh rates](https://developer.apple.com/documentation/quartzcore/optimizing-promotion-refresh-rates-for-iphone-13-pro-and-ipad-pro))
- **`RealityView` has no public frame-rate API on iOS.** Developers report it capped at 60 fps even with the plist key. ([Forums 762074](https://developer.apple.com/forums/thread/762074)) `[unverified: forum]`
- **Pause the scene when Home is hidden: when a sheet covers it, the tab changes, or `scenePhase != .active`.** Disable updating systems, stop splat sorting, and set bloom to a blit or `.none`. If the room is fully covered, remove the `RealityView` from the hierarchy. Apple's guidance is to cut work you don't need. ([visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos)) `[inference]`
- **In Low Power Mode, pause optional activities, reduce display updates and minimize animations.** ([Responding to power notifications](https://developer.apple.com/documentation/xcode/responding-to-power-notifications)) The 60 Hz cap on ProMotion in Low Power Mode is `[unverified]`.

#### 1.10 Thermal state
- **Observe `ProcessInfo.thermalStateDidChangeNotification` and step quality down by state.** At `.fair`, defer deferrable work. At `.serious`, cut screen updates and animations: lower frame rate, drop bloom, lower splat resolution scale, pause life layers. At `.critical`, stop or greatly reduce all work. ([Responding to power notifications](https://developer.apple.com/documentation/xcode/responding-to-power-notifications); [ThermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum))
- **Read `thermalState` once before you register for the notification.** The doc says you must, or the notification won't arrive. ([thermalStateDidChangeNotification](https://developer.apple.com/documentation/foundation/processinfo/thermalstatedidchangenotification))
- **Test under load with Xcode's thermal inducers.** The Simulator has no thermal model. ([WWDC23 10100](https://developer.apple.com/videos/play/wwdc2023/10100/))

#### 1.11 Load time
- **Load asynchronously: use `async` `make`, `await Entity(named:)` or `ModelEntity(named:)`, and `loadModelAsync`.** Synchronous loads block the main thread and hang. ([RealityView](https://developer.apple.com/documentation/realitykit/realityview); [Reducing CPU utilization](https://developer.apple.com/documentation/realitykit/reducing-cpu-utilization-in-your-realitykit-app))
- **Share `MeshResource` and texture instances across entities. Load each file once and clone it.** Shared assets load once and cost memory once. ([Reducing CPU utilization](https://developer.apple.com/documentation/realitykit/reducing-cpu-utilization-in-your-realitykit-app))
- **Split big assets into small ones and load them over time.** Load the room shell first, then props, then the cat. ([Reducing CPU utilization](https://developer.apple.com/documentation/realitykit/reducing-cpu-utilization-in-your-realitykit-app))
- **Preload custom-material assets and particle effects, and avoid loading several at once.** Shader compilation and particle loading are expensive. ([visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos))
- **For custom Metal (splat, bloom), build PSOs once at startup off the main thread. Consider offline compilation or binary archives.** Pipelines built just in time cause first-use hitches. ([WWDC22 10102 Target and optimize GPU binaries with Metal 3](https://developer.apple.com/videos/play/wwdc2022/10102/); [WWDC20 10615 Build GPU binaries with Metal](https://developer.apple.com/videos/play/wwdc2020/10615/))
- **Prefer `.reality` files or RCP-exported content over raw USDZ.** Apple says they load faster and use less memory. ([Reducing CPU utilization](https://developer.apple.com/documentation/realitykit/reducing-cpu-utilization-in-your-realitykit-app))

#### 1.12 RealityView lifecycle
- **Build the scene once in `make`, which is async and shows the `placeholder` meanwhile.** Keep `update` cheap and idempotent. `update` runs when the SwiftUI state it reads changes, so diff before you mutate. ([RealityView](https://developer.apple.com/documentation/realitykit/realityview)) `[inference for "idempotent/diff"]`
- **Keep the `RealityView`'s structural identity stable.** Don't put it inside `if` branches, `.id(...)` changes or `AnyView`. A new identity throws away its state, which here would rebuild the whole scene. ([WWDC21 10022 Demystify SwiftUI](https://developer.apple.com/videos/play/wwdc2021/10022/)) `[inference: applied to RealityView]`
- **Make the `update` closure read only the few observable properties it needs.** Observation tracks reads, so every property read makes `update` re-run when it changes. ([WWDC23 10149 Discover Observation in SwiftUI](https://developer.apple.com/videos/play/wwdc2023/10149/))
- **Keep the subscription returned by `content.subscribe(to:)`, and cancel it on teardown.** If you discard it, the handler leaks or stops. ([RealityViewCameraContent](https://developer.apple.com/documentation/realitykit/realityviewcameracontent)) `[unverified: exact lifetime semantics]`

### 2. UI (SwiftUI)

#### 2.1 Observation, dependencies, invalidation
- **Pass views only the data they use, for example `dog.image` rather than `dog`, and split views to narrow dependencies.** Any change to an input re-runs the body. ([WWDC23 10160 Demystify SwiftUI performance](https://developer.apple.com/videos/play/wwdc2023/10160/))
- **Use `@Observable` and give each shop card its own observable model. Put lookup dictionaries behind `@ObservationIgnored`.** Then toggling one item updates one body instead of all of them. ([WWDC25 306 Optimize SwiftUI performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/306/))
- **Don't put fast-changing values (geometry, timers, scroll offset, camera orbit) in the Environment.** Every reader gets checked, even when its body doesn't re-run. ([WWDC25 306](https://developer.apple.com/videos/play/wwdc2025/306/))
- **Use the Cause & Effect graph to ask what marked a body outdated, not why the body ran.** Backtraces don't explain declarative updates. ([WWDC25 306](https://developer.apple.com/videos/play/wwdc2025/306/))
- **Use `Self._printChanges()` only while debugging, and never ship it.** ([WWDC23 10160](https://developer.apple.com/videos/play/wwdc2023/10160/))

#### 2.2 Identity and body cost
- **Prefer one view with changing parameters over `if/else` branches. Use inert modifiers such as `opacity(cond ? 1 : 0)` instead of conditional modifiers.** Branches create new identities, which resets state and turns transitions into fades. ([WWDC21 10022](https://developer.apple.com/videos/play/wwdc2021/10022/))
- **Avoid `AnyView`. Use `@ViewBuilder` and `some View`.** `AnyView` hides structure from SwiftUI and hurts diffing. ([WWDC21 10022](https://developer.apple.com/videos/play/wwdc2021/10022/); [WWDC23 10160](https://developer.apple.com/videos/play/wwdc2023/10160/))
- **Keep `body` free of formatters, filtering, bundle lookups and allocations, and cache the results.** Bodies run on the main thread, and slow bodies miss frame deadlines. ([WWDC25 306](https://developer.apple.com/videos/play/wwdc2025/306/); [WWDC23 10160](https://developer.apple.com/videos/play/wwdc2023/10160/))
- **Don't do synchronous work in `@State` or model initializers. Load in `.task {}`.** Slow initializers hang view creation. ([WWDC23 10160](https://developer.apple.com/videos/play/wwdc2023/10160/))

#### 2.3 Lists, lazy stacks, scrolling
- **Inside `List` and `Table`, have each `ForEach` element produce a constant number of views. Filter in the model, not with `if` inside `ForEach`.** List gathers IDs eagerly, and a variable view count forces it to build every row. ([WWDC23 10160](https://developer.apple.com/videos/play/wwdc2023/10160/))
- **Use stable, cheap IDs.** Generating IDs is on the load and update path. ([WWDC23 10160](https://developer.apple.com/videos/play/wwdc2023/10160/))
- **Use `LazyVStack` or `LazyVGrid` for the Shop scroll, not an eager `VStack`.** Rows are created on demand for the visible region plus a buffer. In WWDC25 226's demo, switching to a lazy stack cut CPU power impact. ([WWDC23 10160](https://developer.apple.com/videos/play/wwdc2023/10160/); [WWDC25 226 Profile and optimize power usage](https://developer.apple.com/videos/play/wwdc2025/226/)) `[the 21→4.3 figure is unverified]`
- **Choosing between `List` and `LazyVStack`: `List` gives cell reuse and system styling, `LazyVStack` gives freer layout.** Pick by design, then measure with the SwiftUI instrument. Apple publishes no benchmark between them. `[unverified]`

#### 2.4 Glass, materials, blur, shadows, offscreen passes
- **Group nearby glass elements in one `GlassEffectContainer`, and limit how many glass effects are on screen at once.** A container renders its shapes together for better performance. Many containers, or many loose glass effects, degrade performance. ([Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views); [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer))
- **Apply `glassEffect` after the other appearance modifiers.** It captures the content it is applied to. ([Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views))
- **Keep glass and blur off large areas over the animating 3D room where you can.** Glass samples and blurs the content behind it, so a constantly changing backdrop means re-blurring every frame. ([Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)) `[inference]`
- **Treat shadows, masks and blur as offscreen passes and keep them to a minimum, especially on many shop cards.** Offscreen passes make each redraw more expensive and cause render hitches. ([Tech Talk 10857 Demystify and eliminate hitches in the render phase](https://developer.apple.com/videos/play/tech-talks/10857/); [WWDC23 10100](https://developer.apple.com/videos/play/wwdc2023/10100/))
- **Use `drawingGroup()` only on subtrees that SwiftUI draws itself (shapes, text, images), such as a shine sweep on a card.** It flattens the subtree into a single bitmap. UIKit-backed or layer-composited views render as placeholders, and it adds an offscreen pass. ([drawingGroup](https://developer.apple.com/documentation/swiftui/view/drawinggroup(opaque:colormode:)))
- **Use `compositingGroup()` only when you need effects such as opacity applied to the group as a whole.** It also creates an offscreen layer. ([compositingGroup](https://developer.apple.com/documentation/swiftui/view/compositinggroup())) `[inference]`

#### 2.5 TimelineView, Canvas, animations
- **Drive life layers with `TimelineView(.animation(minimumInterval:paused:))` and set `paused` when hidden.** A capped interval means fewer redraws. ([TimelineView](https://developer.apple.com/documentation/swiftui/timelineview); [AnimationTimelineSchedule](https://developer.apple.com/documentation/swiftui/animationtimelineschedule))
- **Draw many small moving elements in one `Canvas`, not as many views.** Canvas is immediate-mode drawing with no per-element view diffing. You lose per-element accessibility and hit testing. ([Canvas](https://developer.apple.com/documentation/swiftui/canvas)) `[inference]`
- **Don't animate through high-frequency `@State` writes from a display link.** Each write is a body update. Use SwiftUI animations, `TimelineView`, or a layer- or Metal-driven path. ([WWDC25 306](https://developer.apple.com/videos/play/wwdc2025/306/)) `[inference]`
- **Use stable IDs in a namespace for `matchedGeometryEffect` and `glassEffectID`.** The IDs let SwiftUI animate the same shape instead of tearing it down and rebuilding it. ([Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views))

#### 2.6 Images
- **Decode at display size with ImageIO `CGImageSourceCreateThumbnailAtIndex`, `kCGImageSourceThumbnailMaxPixelSize` set to points × scale.** Decoded memory is width × height × 4, whatever the file size. ([WWDC18 219 Image and Graphics Best Practices](https://developer.apple.com/videos/play/wwdc2018/219/))
- **Decode off the main thread with `UIImage.byPreparingThumbnail(ofSize:)` or `prepareForDisplay()` and their async variants.** Otherwise lazy decode happens on the main thread during commit and causes a commit hitch. ([byPreparingThumbnail(ofSize:)](https://developer.apple.com/documentation/uikit/uiimage/bypreparingthumbnail(ofsize:)); [prepareForDisplay](https://developer.apple.com/documentation/uikit/uiimage/preparefordisplay(completionhandler:)))
- **Don't rely on `AsyncImage` for wishlist link previews in a scrolling list.** It doesn't downsample, and how it caches is not documented. Use your own loader with downsampling and an in-memory cache. ([AsyncImage](https://developer.apple.com/documentation/swiftui/asyncimage)) `[unverified: caching behavior]`

#### 2.7 Sheets, TipKit
- **Keep the view a sheet is built from cheap, and load its content in `.task`.** Presentation runs the body on the main thread during the transition. ([WWDC23 10160](https://developer.apple.com/videos/play/wwdc2023/10160/)) `[inference]`
- **Call `Tips.configure()` once at launch, off the critical path, and keep tip rules simple.** Apple publishes no TipKit performance guidance. `[unverified]` ([TipKit](https://developer.apple.com/documentation/tipkit))

#### 2.8 Main thread and Swift concurrency
- **Treat 100 ms as the responsiveness target and 250 ms as a hang.** Tools flag hangs from 250 ms, and 500 ms or more is a severe hang. ([WWDC23 10248 Analyze hangs with Instruments](https://developer.apple.com/videos/play/wwdc2023/10248/))
- **With Swift 6.2 default `MainActor` isolation (new Xcode 26 app targets), push heavy work off the main thread explicitly with `@concurrent` or nonisolated types.** Under this mode, unannotated code and nonisolated async functions run on the caller's actor, which is the main actor in UI code. ([WWDC25 268 Embracing Swift concurrency](https://developer.apple.com/videos/play/wwdc2025/268/); [SE-0466](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md); [SE-0461](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md))
- **Keep `View` code on the main actor, as SwiftUI requires, and do JSON decoding, `.ply` parsing, image decoding and sorting prep in nonisolated or `@concurrent` code.** ([WWDC25 266 Explore concurrency in SwiftUI](https://developer.apple.com/videos/play/wwdc2025/266/))
- **Batch `@MainActor` hops: send one result back to the main actor, not a stream of small updates.** Each hop is a main-thread job, and each state write invalidates views. ([WWDC25 306](https://developer.apple.com/videos/play/wwdc2025/306/)) `[inference]`

### 3. App level

#### 3.1 Launch
- **Organizer and MetricKit measure launch as time to first frame. Make the first frame cheap: placeholder room, no scene load and no network before it.** ([Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time))
- **Remove static initializers (C++ static constructors, `+load`, `__attribute__((constructor))`) and limit embedded dynamic frameworks, or use mergeable libraries.** These run before `main`. ([Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time); [WWDC19 423 Optimizing App Launch](https://developer.apple.com/videos/play/wwdc2019/423/))
- **Initialize storage, StoreKit, TipKit and networking on first use or after the first frame. Show stale data while syncing.** App delegate and `App.init` run synchronously on the main thread. ([Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time))
- **Wrap post-first-frame startup (scene ready, cat visible) in `os_signpost` Points of Interest.** The launch metric stops at the first frame, but users perceive what comes after. ([Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time))

#### 3.2 Memory and jetsam
- **Track the memory footprint, meaning dirty pages × 16 KB. Watch peak and memory-at-suspend in Organizer and MetricKit.** The limit varies by device, and going over it terminates the app. ([Reducing your app's memory use](https://developer.apple.com/documentation/xcode/reducing-your-app-s-memory-use))
- **Free splat CPU buffers once they are uploaded, and drop textures on memory warnings or when Home goes to the background.** A smaller suspended footprint means fewer jetsam kills and faster resumes. ([Responding to low-memory warnings](https://developer.apple.com/documentation/xcode/responding-to-low-memory-warnings); [Reducing your app's memory use](https://developer.apple.com/documentation/xcode/reducing-your-app-s-memory-use))
- **Use Allocations and the memory graph to find transient and persistent growth.** ([WWDC24 10173 Analyze heap memory](https://developer.apple.com/videos/play/wwdc2024/10173/))

#### 3.3 Widgets and Live Activities
- **Plan for 40–70 widget reloads a day, and space timeline entries at least about 5 minutes apart.** Use `Text` date styles for counters instead of reloading. Reloads are free while the app is in the foreground. ([Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date))
- **Call `reloadTimelines(ofKind:)` only when a matching widget configuration exists.** Unnecessary reloads spend budget. ([Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date))
- **Keep the widget extension well under about 30 MB. Downsample images and never decode full photos in the provider.** Widgets have been seen jetsammed at a 30 MB high-water mark. ([Forums 842805](https://developer.apple.com/forums/thread/842805)) `[unverified: no Apple doc states the limit]`
- **Keep Live Activity static and dynamic data under 4 KB combined, and images no larger than the presentation size.** Oversized images can stop the activity from starting. Activities last 8 hours, plus up to 4 hours on the Lock Screen. ([Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities))
- **Send routine Live Activity pushes at `apns-priority` 5 and keep priority 10 for alerting updates.** Priority-10 pushes draw from an hourly budget and get throttled. ([WWDC23 10185 Update Live Activities with push notifications](https://developer.apple.com/videos/play/wwdc2023/10185/)) `[exact budget unverified; Apple publishes none]`
- **Don't build Live Activity UI that depends on custom animations.** The system ignores animation modifiers and doesn't animate in Always On. ([Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities))

#### 3.4 Energy and networking
- **Profile energy with Power Profiler: system power, CPU, GPU, display, network and thermal lanes.** Re-measure after each fix. ([WWDC25 226](https://developer.apple.com/videos/play/wwdc2025/226/); [Measuring power with Power Profiler](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler))
- **A continuously rendering 3D room is the app's biggest energy cost. Idle it (lower fps, no bloom, no sort) when nothing moves.** Display updates and animations are the first things Apple says to cut. ([Responding to power notifications](https://developer.apple.com/documentation/xcode/responding-to-power-notifications)) `[inference]`
- **Use async `URLSession` from nonisolated code, coalesce requests, and reduce polling in Low Power Mode.** The `URLSession` work runs off the main thread, but decoding inherits the caller's isolation. ([Responding to power notifications](https://developer.apple.com/documentation/xcode/responding-to-power-notifications); [SE-0461](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md))

### 4. Tooling and measurement

#### 4.1 Instruments
- **RealityKit Trace (RealityKit Frames and RealityKit Metrics): use it for frame times and bottlenecks in 3D render CPU/GPU, entity commits, custom systems, animations and physics.** Focus on bottlenecks that line up with missed deadlines. Profile on a device. ([WWDC23 10099 Meet RealityKit Trace](https://developer.apple.com/videos/play/wwdc2023/10099/); [visionOS rendering cost](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos))
- **SwiftUI instrument (Instruments 26): use the Long View Body Updates, Representable Updates and Update Groups lanes and the Cause & Effect graph.** Start with the orange and red entries. ([WWDC25 306](https://developer.apple.com/videos/play/wwdc2025/306/))
- **Time Profiler or CPU Profiler for main-thread cost. Processor Trace and CPU Counters for hot loops such as a CPU splat sort.** CPU Profiler samples by cycle counter, which avoids timer bias. ([WWDC25 308 Optimize CPU performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/308/))
- **Hitches / Animation Hitches: tell commit hitches (app) from render hitches (render server).** ([Understanding hitches](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app); [Tech Talk 10855](https://developer.apple.com/videos/play/tech-talks/10855/))
- **Hitch targets:** Organizer rates 10 ms/s or less as good, up to 25 warning and up to 50 critical. The tech talk aims for under 5 ms/s. Use under 5 ms/s for scroll and orbit. ([Understanding hitches](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app); [Tech Talk 10855](https://developer.apple.com/videos/play/tech-talks/10855/))
- **Metal System Trace (with GPU counters) for the splat and bloom passes.** ([WWDC23 10100](https://developer.apple.com/videos/play/wwdc2023/10100/))
- **Allocations and Leaks for growth and per-frame allocations, App Launch for launch, Power Profiler for energy.** ([WWDC24 10173](https://developer.apple.com/videos/play/wwdc2024/10173/); [Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time); [WWDC25 226](https://developer.apple.com/videos/play/wwdc2025/226/))

#### 4.2 Signposts, MetricKit
- **Add `os_signpost` intervals (Points of Interest) around scene load, splat load, sort, first cat frame and shop open.** They appear in Instruments and can drive `XCTOSSignpostMetric`. ([Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time))
- **Subscribe to `MXMetricManager` for field launch, hitch, memory, CPU/GPU and custom `mxSignpost` metrics, and diagnostics.** This is the only source of real-device numbers from users. ([MetricKit](https://developer.apple.com/documentation/metrickit))

#### 4.3 XCTest metrics
- **`XCTApplicationLaunchMetric`** for launch, **`XCTClockMetric`** or **`XCTCPUMetric`** for code paths, **`XCTMemoryMetric`** for footprint, **`XCTOSSignpostMetric`** with your signposts, and `.scrollDecelerationMetric` or `.scrollDraggingMetric` for scroll hitches. ([XCTMetric](https://developer.apple.com/documentation/xctest/xctmetric); [WWDC20 10077 Eliminate animation hitches with XCTest](https://developer.apple.com/videos/play/wwdc2020/10077/); [Preventing memory-use regressions](https://developer.apple.com/documentation/xcode/preventing-memory-use-regressions))
- **`XCTHitchMetric(application:)` (iOS 26) counts hitches in UI tests directly.** ([XCTHitchMetric](https://developer.apple.com/documentation/xctest/xcthitchmetric))
- **Run perf tests in a Release-configured test scheme with screenshots and code coverage off.** ([WWDC20 10077](https://developer.apple.com/videos/play/wwdc2020/10077/))

#### 4.4 Simulator vs device
- **Simulator Metal runs on the Mac's GPU through a translation layer. It exposes roughly Apple GPU family 2 features and different limits.** It doesn't emulate the A-series GPU. ([Developing Metal apps that run in Simulator](https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator))
- **Don't design or tune the renderer in the Simulator.** It lacks features the fast device paths use, such as programmable blending and memoryless attachments, and Xcode can't measure performance or memory footprint there. ([Developing Metal apps that run in Simulator](https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator))
- **Simulator numbers can't tell you about thermal throttling, real GPU fill rate, ProMotion pacing or jetsam limits.** Profile on a device. ([WWDC23 10099](https://developer.apple.com/videos/play/wwdc2023/10099/); [WWDC23 10100](https://developer.apple.com/videos/play/wwdc2023/10100/); [Developing Metal apps that run in Simulator](https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator))
- **What CI Simulator numbers can show:** *relative* regressions on the same runner image in CPU-side work. That covers SwiftUI body counts and durations, signpost intervals for load and parse, allocation counts, and launch-to-first-frame trend. Compare A/B on the same runner, not against absolute budgets. `[inference]`
- **What they can't show:** GPU-bound costs (bloom, splat fill, transparency, shadows), absolute frame times, energy and thermal behavior. Gate those on device runs or MetricKit. `[inference]`

## Part B: audit of Ourio (main at 392fdced, 2026-11-05)

Read-only. Nothing was built or profiled for this part.

**Owner tags.**

- **needs Ilya:** Ilya's room and cat files. These are CatRoom, CityRoomScene, DioramaScene,
  DioramaView, CatWalker, CatRig, CatGait, CatBehavior, CatDirector, SplatLoader, SkinSplats.metal,
  Kit, Props, Daylight and TownPicture, plus `Resources/` (Cat*.usdz, Mochi*.ply, Room/) and
  `Tools/make_*.py`. They change only with Ilya's or the owner's OK.
- **ours:** everything else.

Prior work this builds on:

- #391: Shop backdrop still, shine and shadows cheap, art decoded ahead.
- #417: the room's RealityView is unmounted off the room tabs.
- #421: a snapshot of the room shows on return.

All three are in place: `WarmBackdrop(drifts: showsRoom)` and `} else if let scene, showsRoom {` in
HomeView.swift:42 and :51, and the snapshot at :183-200. Remaining gaps from #391 are B7 and B16.

### Top 10

Ranked by expected win over risk.

| # | Issue | Where | Owner | Expected cost today | Fix | Measure | Risk |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | The City window paints its view on the main thread inside the frame loop. Life repaints at 12 Hz through a new `ImageRenderer` and a texture upload. The sky repaints every 4 s. A new look paints five stills of up to 1800×1000 px. | WindowPane.swift:20, :104-107, :149; WindowLayers.swift:103, :173-178; driven from CityRoomScene.swift:111,170 | ours (WindowPane, WindowViews), the call site needs Ilya; coordinate with billet-window | ~36–120 ms of main thread per second for life; a 20–60 ms frame every 4 s; ~28–37 MB of stills | Life at 6–8 Hz and only when the moment changed. Sky every 15–30 s. Middle, street and near at density 7. One reused renderer or a `LowLevelTexture`. Life pauses while orbiting. | `perf.yml -f room=city -f jobs=steady`, then `ab`: `cpuMsPerS`, hitches, p99, `PERF frame long` | low |
| 2 | Launch loads every store several times on the main thread. `HomeView()` is built in `OurioApp.body`, and its `@State` starts from `HomeState(stores: .live())`. That runs on every App-body pass, at least 3 per launch (sign-in idle → signingIn → signedIn), and each pass reads ~9 JSON files and both avatar JPEGs. Then `onChange(of: scenePhase, initial: true)` runs `refresh()` and reads them again. `isSignedIn` reads the Keychain on each pass. The polaroids are built twice. | HomeView.swift:9, :158-162, :224-227; OurioApp.swift:40-74; HomeState.swift:194-207; ServerSession.swift:64 | ours | ~10–40 ms of main thread during the splash, plus invalidations | Build `HomeState` once, in OurioApp or as an optional `@State` filled in `.task`. Keep `.id(wornCoat)` and erase. Skip `refresh()` on the initial pass and reload a store only when its file's mtime changed. Cache `hasSavedAccount`. Drop the first `setPolaroids`. | `perf.yml` `ab` launches: `room on screen`, `styled cat placed`. Time Profiler on launch. | low |
| 3 | The room keeps drawing while it is covered: under the full-screen drawing canvas, the large Inbox sheet and ItemSheet (which has its own RealityView), and while the app is inactive. `showsRoom` looks only at the tab. | HomeView.swift:36, :251-271, :224-247 | ours | the room's full CPU+GPU for as long as it is covered; competes with pen latency | Unmount the room the same way #417 does when it is fully covered (drawing, large detents, not `.active`). #421's snapshot covers the way back. Keep it live under half-height sheets. | New ScenePerf step that opens the drawing and records. Energy Log on a phone. | low |
| 4 | Photos are encoded and written on the main thread: partner photos on every foreground and socket frame, "Add to Moments", doodles. Wish cards read their JPEG from disk inside `body`. The moment viewer rasterizes a 1080 px polaroid while it zooms open. | Moments.swift:110-131 (via PhotoSync.swift:74, Journal.swift:28); Notes `add(doodle:)`; WishlistScreen.swift:299, :652; MomentsView.swift:688, :742-749 | ours | ~20–60 ms per photo; ~15–40 ms on viewer open | Encode and write in a detached task, then insert on main. Write received ≤2048 px JPEGs as they are. Cache downsampled wish thumbnails in `.task`. Render the polaroid only when sharing. | Hitches + Time Profiler (not in perf.yml) | low |
| 5 | The bokeh backdrop redraws a full-screen `Canvas` (14 radial gradients) at 30 Hz under the live room. The room and every glass control over it composite against it. | HomeView.swift:527-548 | ours | ~0.5–3 ms main/render per update, plus a full-screen layer | Render-server motion (pre-rendered blobs moved by one repeating animation) or 10–15 Hz. The drift is only ±18–24 pt. | `jobs=steady` A/B. `-uitestStill YES` already freezes it, so a with/without run gives the cost. | low |
| 6 | Moments feed: every print is flattened (`compositingGroup`) and casts two shadows traced from its alpha, plus a multiply-blended grain. That is offscreen passes per visible print, the same thing #391 fixed in the Shop. Board faces re-render all 8 with `ImageRenderer` when one changes. | Polaroid.swift:89-92, :109-113; MomentsView.swift:350-352, :420-422; BoardFaces.swift:8-52 | ours | GPU per scroll frame × ~6–10 prints; up to ~100 ms per board change | Shape shadows from the paper's `RoundedRectangle`. Bake the grain. Cache board faces by id + content. | Add a `notes.scroll` step (like `shopScroll`), then `ab` | low |
| 7 | Shop glass: every card has its own Liquid Glass button. The category chips and the header pills aren't in a glass container. Today is a non-lazy `VStack`. 15–25 glass effects re-sample on every scroll frame. | ShopKit.swift:189-201; PriceButton.swift:34,61; ShopItemCard.swift:41; BundleCard.swift:28; FeaturedCard.swift:27,55,58; CollectionCard.swift:87; DailyGiftCard.swift:28; ShopView.swift:104-113; AppHeader.swift:17-23 | ours, look via billet-glass and the owner | likely the largest remaining part of `shop.scroll` | Flat filled capsules inside cards; glass only on floating chrome. `GlassGroup` around chips and header. `LazyVStack` for Today. | `ab`: `shop.scroll` p95/p99, hitches; `shop.still` | low–medium (look) |
| 8 | Mesh cat textures: each of Cat.usdz and CatStanding.usdz carries 2048² color, normal and fur (PNG, of which only `.r` is read) plus a 1024² roughness map. Both models stay resident. This is the cat on iOS 26 phones, pre-Apple7 GPUs and CI. | Resources/Cat.usdz, CatStanding.usdz; CatRoom.swift:331-340 | needs Ilya | ~140 MB of GPU memory if decoded to RGBA8 with mips (to verify); 2 × 11 MB usdz to load | 1024² maps; fur as one channel; ASTC in the usdz | `memory peakMB` in any CI run (the CI cat is this one); `styled cat placed` | low–medium (softer at closest zoom) |
| 9 | Mochi loads her four poses one after another before the splash lifts. Each 7.3 MB ply is read whole, split into two `[Float]` arrays, then copied on main into LowLevelBuffers and the skinner's buffers. All four poses stay resident at ~13.6 MB each, plus RealityKit's own buffers. | CatRoom.swift:324-359; SplatLoader.swift:51-94; CatRig.swift:353-354 | needs Ilya | ~100–400 ms to cat-ready on a phone; ~55 MB resident; ~16 MB transient per file | Load the poses in a `TaskGroup`. Map the file and parse straight into the buffer. Free the arrays after `make`. Start the walker once standing and seated are in (#392's guard stays via `needBody`). | phone: Allocations, launch marks. CI sees only the mesh path. | low |
| 10 | Room geometry and passes. Room_furniture.usdz is one ~286k-triangle mesh with face-varying normals (~568k GPU vertices) and 59 subsets with duplicate materials. All of it casts grounding shadows on top of the directional shadow. The City has ~240 primitive entities, each with its own PBR material. The cat's six alpha-tested fur shells and fins all cast shadows. | Resources/Room/Room_furniture.usdz; DioramaScene.swift:289, :377; Kit.swift:17-30, :66; Props.swift:157; CityRoomScene.swift:262-274; CatRoom.swift:303-306 | needs Ilya | ~18 MB of geometry × 3 passes; ~0.5–2 ms GPU and render-prep per frame (guess) | Decimate and weld in make_room.py. Merge duplicate materials. One shadow technique for static furniture. Bake static primitives per room into one mesh grouped by material. No shadows from fur shells. | `jobs=cost` once switches exist (B-H1); `memory peakMB`; orbit p95 | medium |

### The rest

Scene:

- **B11. All four splat poses stay resident** (needs Ilya). Loaf and sleep add ~27 MB while
  disabled. Check whether `GaussianSplatResource` takes half floats for the still part. Phone only.
- **B12. Skinning runs almost every frame** (needs Ilya). The drift threshold is `2e-4`
  (CatRig.swift:331), and breathing (CatWalker.swift:544-546) keeps crossing it, so most frames run a
  131k-thread compute pass and hand RealityKit a new buffer. There are per-frame allocations at
  CatRig.swift:198 and :238, and copy-on-write copies of pose arrays (CatWalker.swift:416-513).
  - Fix: scale the threshold by the cat's size on screen, skin at 30 Hz while she only breathes,
    and keep the buffers in the rig.
  - Measure: the `skin_passes`, `skin_skipped` and `skin_ms` census (OurioPerf.swift:57-59), on a
    phone.
- **B13. No thermal, Low Power or frame-rate policy anywhere.** Use `thermalState` and
  `isLowPowerModeEnabled` (§1.9, §1.10).
  - At `.serious` or in Low Power: motes off (CatRoom.swift:382-398), bloom off, window life at
    4 Hz, skinning at 30 Hz, fewer fur shells.
  - The harness asks for 120 Hz (ScenePerf.swift:411) and the app never does, so the measured pacing
    isn't production's. Make them match.
  - Owner: mixed. The switches live in Ilya's files.
- **B14. The City room is rebuilt on every open** (HomeView.swift:337, :341). That is ~240 entities
  plus all the window stills: a 30–80 ms tap hitch and a few rough frames (guess).
  - Fix: keep the City, or keep its `WindowPane` painter and textures (a memory trade).
- **B15. The frame subscription may outlive the RealityView** after you leave World (guess). It
  captures `content` and the camera rig (CatRoom.swift:164-172), and `stop()` runs only on a room
  switch.
  - Fix: `.onDisappear { scene.stop() }`. Check with the Xcode memory graph.
  - Owner: needs Ilya (DioramaView), or do it in HomeView.
- **B16. Lights** (needs Ilya). Diorama has one shadowed directional and 3 point lights, each
  covering the whole room. The candle is rewritten every 3rd frame (DioramaScene.swift:81-84, :337,
  :343, :383). The City has 2 directional and 4 point lights.
  - Fix: fold the fill and window light into the IBL. Add bloom and point-light switches to
    `jobs=cost`.
- **B17. Games write `@Observable` state every frame.** A `deck.bar` tuple is assigned each frame
  (BrushStage.swift:102, LaserStage.swift:87). FeedStage's random wobble re-renders its display
  texture nearly every frame (FeedStage.swift:368-395).
  - Fix: assign only on change; wobble at 10 Hz. Owner: ours.
- **B18. Small per-frame work in the City.** A `Calendar` call (CityRoomScene.swift:107,
  Daylight.swift:77-79), `setClock` (:112) and `WindowPane.tick` (:98-104) run every frame. Fairy
  bulb transforms are written every frame (DioramaScene.swift:86-89, BoardRoomScene.swift:165-168).
  - Fix: sample the clock at 1 Hz and pulse the bulbs at 20 Hz.

UI and app:

- **B19. Coat portraits are 1200×1600 PNGs**, about 7.7 MB each once decoded.
  - The launch splash decodes one on main (CatHero.swift:22, LaunchSplash.swift:18).
  - The onboarding coat carousel decodes all six at once in a non-lazy `HStack`, about 46 MB
    (OnboardingView.swift:544, :568).
  - Fix: ship them at the drawn size, downsample off main, use a `LazyHStack`.
- **B20. Shadows traced from composite content over the live room.** These are PetSheet.swift:50
  (around glass), AppHeader.swift:41 and HeartBubble.swift:23.
  - Fix: shape shadows. Measure: `steady`.
- **B21. HomeView's root `body` reads moments, notes, care and `shop.lastPurchase`**
  (HomeView.swift:160-219, :279-280), so every pet or caption re-runs the root.
  - `CatCare.fill` writes `wallet.progress` (CatCare.swift:45-52), which invalidates CoinPill and
    every `ShopItemCard` through ShopModel's whole-`Wallet` reads (ShopModel.swift:27-42).
  - Fix: move the sync and observer modifiers into a zero-size child view, and split coins from
    progress. Measure with the SwiftUI instrument.
- **B22. ItemSheet decodes its art on main as it opens.** It uses 900 px art (ItemSheet.swift:78),
  and the Shop prefetch covers only 512 and 256 px.
  - Also missed: DailyGiftCard.swift:220, and `trimmed` at FeaturedCard.swift:91 and SetSheet.swift:62,
    which scans alpha on main.
- **B23. Widgets do work they don't need.**
  - The extension's `CoupleStore()` loads avatars it never shows (Provider.swift:34-37).
  - The moment photo is downsampled and re-encoded on every timeline (:45).
  - The app calls `reloadAllTimelines()` on every background (HomeState.swift:227-231).
  - Fix: a no-photos read, a cached 600 px JPEG, and a reload only when something changed.
- **B24. `Tips.configure` runs synchronously in `App.init`** (OurioApp.swift:19, Hints.swift:70).
  Measure before moving it: tips evaluated before configure don't show.
- **B25. Small items.**
  - `price` is computed three times per `ShopItemCard` body, each building a `ShopOffers`
    (ShopItemCard.swift:12-13, ShopModel.swift:34-36).
  - Inbox grouping is O(n²) (InboxView.swift:206-216).
  - Packages decode JSON off main only because they lack `NonisolatedNonsendingByDefault`. If they
    ever adopt it, as `apps/ios` has (project.yml:11), decoding moves to the main actor.

Checked and fine:

- The RealityView's identity is stable. `update` only swaps the root (DioramaView.swift:39-42).
- The bubble's `@Observable` write is thresholded at 2 pt (DioramaView.swift:29).
- CatDirector thinks at 4 Hz and publishes only on change.
- Box meshes are cached (Kit.swift:45-53).
- `Entity(named:)` is awaited.
- Network decoding is off main today.

### Harness gaps (B-H)

What has to exist before some of the fixes above can show their A/B on CI:

1. **H1. More cost switches.** `jobs=cost` has one switch for Ourio (`"cat shadow"`,
   OurioPerf.swift:61). Add window life, motes, furniture shadow, fur shells, point lights and bloom
   (bloom on a phone only).
2. **H2. A `notes.scroll` step** (Moments feed), and the Us tab in `selectTab`, which only knows
   shop, notes and home.
3. **H3. Steps for covers and sheets** (the drawing, the Inbox), room switches (the City) and a game.
4. **H4. A `-uitestStill` passthrough in measure.sh**, so the bokeh can be A/B'd in one build.
5. **H5. Match production's frame rate.** ScenePerf's display link asks for 120 Hz
   (ScenePerf.swift:411); production doesn't.

### Proposed PRs

One PR per bundle, each with a `perf.yml` A/B:

| PR | Contents | Owner | Measured by |
| --- | --- | --- | --- |
| P1 harness | H1–H5 | ours | the run itself: the new steps report |
| P2 launch | #2, B19, B24 (measured first) | ours | `ab` launches |
| P3 covered room and backdrop | #3, #5, B17 | ours | `steady`, the new cover step |
| P4 window | #1, plus B14's painter cache | ours; the CityRoomScene call site needs Ilya | `room=city` `steady` and `ab` |
| P5 main-thread images | #4, B22, B23 | ours | Hitches (phone or local), `ab` launches |
| P6 feed and Shop rendering | #6, #7, B20, B21, B25 | ours; look via billet-glass | `ab` `shop.scroll`, `notes.scroll` |
| P7 room and cat | #8, #9, #10, B11, B12, B13, B15, B16, B18 | needs Ilya | `cost`, `memory peakMB`; splats on a phone |

## Sources (Part A)

Apple documentation
- RealityKit: [Improving the performance of a RealityKit app](https://developer.apple.com/documentation/realitykit/improving-the-performance-of-a-realitykit-app), [Reducing CPU utilization](https://developer.apple.com/documentation/realitykit/reducing-cpu-utilization-in-your-realitykit-app), [Reducing GPU utilization](https://developer.apple.com/documentation/realitykit/reducing-gpu-utilization-in-your-realitykit-app), [Reducing the rendering cost of RealityKit content on visionOS](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos), [RealityView](https://developer.apple.com/documentation/realitykit/realityview), [RealityViewCameraContent](https://developer.apple.com/documentation/realitykit/realityviewcameracontent), [RealityViewRenderingEffects](https://developer.apple.com/documentation/realitykit/realityviewrenderingeffects), [PostProcessEffect](https://developer.apple.com/documentation/realitykit/postprocesseffect), [PostProcessEffectContext](https://developer.apple.com/documentation/realitykit/postprocesseffectcontext), [System](https://developer.apple.com/documentation/realitykit/system), [ModelSortGroupComponent](https://developer.apple.com/documentation/realitykit/modelsortgroupcomponent), [LowLevelMesh](https://developer.apple.com/documentation/realitykit/lowlevelmesh), [TextureResource.MipmapsMode](https://developer.apple.com/documentation/realitykit/textureresource/mipmapsmode)
- SwiftUI: [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views), [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer), [drawingGroup](https://developer.apple.com/documentation/swiftui/view/drawinggroup(opaque:colormode:)), [compositingGroup](https://developer.apple.com/documentation/swiftui/view/compositinggroup()), [TimelineView](https://developer.apple.com/documentation/swiftui/timelineview), [Canvas](https://developer.apple.com/documentation/swiftui/canvas), [AsyncImage](https://developer.apple.com/documentation/swiftui/asyncimage), [TipKit](https://developer.apple.com/documentation/tipkit)
- UIKit images: [byPreparingThumbnail(ofSize:)](https://developer.apple.com/documentation/uikit/uiimage/bypreparingthumbnail(ofsize:)), [prepareForDisplay](https://developer.apple.com/documentation/uikit/uiimage/preparefordisplay(completionhandler:))
- Xcode/system: [Understanding hitches in your app](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app), [Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time), [Reducing your app's memory use](https://developer.apple.com/documentation/xcode/reducing-your-app-s-memory-use), [Responding to power notifications](https://developer.apple.com/documentation/xcode/responding-to-power-notifications), [Measuring power with Power Profiler](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler), [ProcessInfo.ThermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum), [thermalStateDidChangeNotification](https://developer.apple.com/documentation/foundation/processinfo/thermalstatedidchangenotification), [CADisableMinimumFrameDurationOnPhone](https://developer.apple.com/documentation/bundleresources/information-property-list/cadisableminimumframedurationonphone), [Optimizing ProMotion refresh rates](https://developer.apple.com/documentation/quartzcore/optimizing-promotion-refresh-rates-for-iphone-13-pro-and-ipad-pro) (not fetched; title confirmed by press coverage), [Developing Metal apps that run in Simulator](https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator), [MetricKit](https://developer.apple.com/documentation/metrickit), [XCTMetric](https://developer.apple.com/documentation/xctest/xctmetric), [XCTHitchMetric](https://developer.apple.com/documentation/xctest/xcthitchmetric)
- Widgets/Live Activities: [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date), [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

WWDC and Tech Talks (numbers confirmed on developer.apple.com)
- [WWDC18 219 Image and Graphics Best Practices](https://developer.apple.com/videos/play/wwdc2018/219/) · [WWDC19 423 Optimizing App Launch](https://developer.apple.com/videos/play/wwdc2019/423/)
- [WWDC20 10077 Eliminate animation hitches with XCTest](https://developer.apple.com/videos/play/wwdc2020/10077/) · [WWDC20 10602 Harness Apple GPUs with Metal](https://developer.apple.com/videos/play/wwdc2020/10602/) · [WWDC20 10615 Build GPU binaries with Metal](https://developer.apple.com/videos/play/wwdc2020/10615/)
- [WWDC21 10022 Demystify SwiftUI](https://developer.apple.com/videos/play/wwdc2021/10022/) · [WWDC22 10102 Target and optimize GPU binaries with Metal 3](https://developer.apple.com/videos/play/wwdc2022/10102/)
- [WWDC23 10099 Meet RealityKit Trace](https://developer.apple.com/videos/play/wwdc2023/10099/) · [WWDC23 10100 Optimize app power and performance for spatial computing](https://developer.apple.com/videos/play/wwdc2023/10100/) · [WWDC23 10149 Discover Observation in SwiftUI](https://developer.apple.com/videos/play/wwdc2023/10149/) · [WWDC23 10160 Demystify SwiftUI performance](https://developer.apple.com/videos/play/wwdc2023/10160/) · [WWDC23 10185 Update Live Activities with push notifications](https://developer.apple.com/videos/play/wwdc2023/10185/) (number from WWDC Notes) · [WWDC23 10248 Analyze hangs with Instruments](https://developer.apple.com/videos/play/wwdc2023/10248/)
- [WWDC24 10103 Discover RealityKit APIs for iOS, macOS and visionOS](https://developer.apple.com/videos/play/wwdc2024/10103/) · [WWDC24 10173 Analyze heap memory](https://developer.apple.com/videos/play/wwdc2024/10173/) · [WWDC24 10217 Explore Swift performance](https://developer.apple.com/videos/play/wwdc2024/10217/)
- [WWDC25 226 Profile and optimize power usage in your app](https://developer.apple.com/videos/play/wwdc2025/226/) · [WWDC25 266 Explore concurrency in SwiftUI](https://developer.apple.com/videos/play/wwdc2025/266/) · [WWDC25 268 Embracing Swift concurrency](https://developer.apple.com/videos/play/wwdc2025/268/) · [WWDC25 287 What's new in RealityKit](https://developer.apple.com/videos/play/wwdc2025/287/) · [WWDC25 306 Optimize SwiftUI performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/306/) · [WWDC25 308 Optimize CPU performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/308/)
- [Tech Talk 10855 Explore UI animation hitches and the render loop](https://developer.apple.com/videos/play/tech-talks/10855/) · [Tech Talk 10857 Demystify and eliminate hitches in the render phase](https://developer.apple.com/videos/play/tech-talks/10857/)
- No WWDC26 sessions were found or checked.

Swift Evolution
- [SE-0466 Control default actor isolation inference](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md) · [SE-0461 Run nonisolated async functions on the caller's actor](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md)

Gaussian splatting
- [Kerbl et al., 3D Gaussian Splatting for Real-Time Radiance Field Rendering (SIGGRAPH 2023)](https://arxiv.org/abs/2308.04079) · [Fan et al., LightGaussian (NeurIPS 2024)](https://arxiv.org/abs/2311.17245) · [PlayCanvas splat performance](https://developer.playcanvas.com/user-manual/gaussian-splatting/building/performance/) · [PlayCanvas splat renderers](https://developer.playcanvas.com/user-manual/gaussian-splatting/rendering-architecture/renderers/) · [MetalSplatter](https://github.com/scier/MetalSplatter)

Forums and third party (lower confidence)
- [Forums 762074 RealityView 120 fps](https://developer.apple.com/forums/thread/762074) · [Forums 831723 MeshInstancesComponent vs merging](https://developer.apple.com/forums/thread/831723) · [Forums 842805 widget 30 MB limit](https://developer.apple.com/forums/thread/842805) · [Ghifary, 3DGS on Apple Silicon](https://ghifary.notion.site/Production-Grade-3D-Gaussian-Splatting-on-Apple-Silicon-with-Native-MPS-Kernels-30ca59d3736080febd77f45330e41f75) · [dev.to, splat relighting on iPhone](https://dev.to/john-rocky/real-time-relighting-of-gaussian-splatting-reflections-on-iphone-metal-3b26)
