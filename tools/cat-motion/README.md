# cat-motion

Plays a fixed set of the cat's moves on the Mac and records them, to see and measure how she moves
without a phone or a person.

It compiles the app's own cat files (`Sources/CatMotion/Cat` links to `CatWalker`, `CatGait`,
`CatRig`, `CatBehavior` and `CatPace` in `apps/ios/Nooki/Scene`), reads her splats, skins and rigs
from `apps/ios/Nooki/Resources`, skins them with the app's `SkinSplats.metal`, and draws the result
with a small Gaussian splat renderer of its own (`Shaders/Splat.metal`), since RealityKit draws
splats only from iOS 27.

```sh
tools/cat-motion/run.sh <label> [scenario ...]   # all scenarios without names
tools/cat-motion/compare.sh <before> <after>     # stacked movies and the numbers of both
tools/cat-motion/run.sh report <label> ...       # the numbers again from the samples a run left
tools/cat-motion/run.sh fit ["<start>" [held index ...]]   # search for the swap posture
tools/cat-motion/run.sh poses "<15 numbers>" ... # candidates' standing body beside the seated one
```

`fit` searches the standing rig's postures for the one whose outline lies closest on the seated
splat's from six sides (`Fit.swift`); `CatWalker.Posture.sit` and `swapLean` come from it, with the
pitch held upright, since the closest outline overall is a flat crouch that does not read as sitting.

Each scenario leaves `<scenario>.mp4` (room view left, side view following her right, 60 fps),
`<scenario>.json` (a sample per frame) and `<scenario>.txt` (the numbers) in
`~/Library/Caches/cat-motion/<label>/`. Scenarios are in `Scenarios.swift`.

Scenarios with a `layout` play in the Home room as the player arranged it (`DecorLayout`): she goes round its
pieces by the room's own floor plan, the picture has each piece's floor space as a box, and the report says how
deep her body got into one.

## The numbers

- **Inside a piece**: in a furnished scenario, how deep points round her standing body (nose, cheeks, shoulders,
  flanks, rump) are inside a piece's floor space while she is on the floor, and for how long. Her own bed and a
  basket she reaches into count too, so read it piece by piece.
- **Stance paw slide**: how far paws that are on the floor travel along it, in room units / 1000.
- **Dead still inside a move**: time she is frozen while the walker still has steps queued.
- **Full stops within an errand**: times she stops and sets off again before she is done.
- **Turning done while walking**: share of all turning that happens while she travels.
- **Swap**: share of the side silhouette that changes in the frame one splat replaces another,
  beside what changes in the frames around it.
- **Pose change**: for a change of posture in place, how far apart in time her parts pass half way
  (0 ms is one synchronous morph), and the largest overshoot.

## What it cannot show

RealityKit's own splat shading, the room's light and shadows, the phone's frame pacing and skin-rate
limits, and the mesh the Simulator and older phones draw. Her idle habits draw from the system's
random numbers, so two runs differ a little in the head, ears and tail at rest.
