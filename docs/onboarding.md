# First launch

Every cold launch opens on a cinematic; there is no switch for it.

- **Before the pair is made**, it is the first-launch scene: the camera glides in out of the dark
  over a windowsill at night, the candles light one by one, fairy lights run down both sides of
  the window, and a soft glossy heart floats over a cushion, beating gently. The title and its
  explanation sit on a dark scrim at the top of the screen, so they stay readable (AA contrast,
  checked in a test) over the lit window. The title settles in partway; the buttons come once the
  camera is at its place. A tap anywhere cuts the flight short. It flies in
  once per launch: moving on to the next step does not fly in again. Signing in (real backend)
  and pairing happen in this scene; without a 3D scene they happen over the evening background
  with the same words and controls. Labs → First launch → Replay onboarding plays it again, as a
  debug button, without touching the pair.
- **Once paired**, it is a short glide into the room (`LaunchCinematic`, `LaunchGlide`). From
  Home's first frame a warm dark covers the room while it loads; once the room is built and on
  screen it starts its opening and the cover fades: the camera glides in from a little way out
  over 1.8 s, the lights come up, and the cat looks up at the camera (`FlyInTimeline`, 1.9 s in
  all). Home's controls wait until it is over. A tap skips to the end. Coming back from the
  background is not a launch and never plays it, and a launch that opened on the heart's scene
  does not glide into the room after it. The real backend's paired screens have no room, so
  there is nothing to glide into there.
- **Reduce Motion:** nothing flies. The heart's scene fades up at its place, and the cover
  cross-fades to the room at its place.

## Pairing in the scene

Once the camera lands, the welcome offers **Invite your person** and **I have a code**. Every
step after the welcome has a glass back chevron in the top-left corner (it cancels an invite or a
join under way); there is no Back or Cancel button at the bottom. The code is typed in the app's
own face with figures of one width.

- **Invite your person:** the heart opens into two halves: it is one heart cut straight down its
  middle, so each half has one round lobe, a flat inner face and half of the point. This phone's half stays in front, and
  the other floats on its side, faint, glowing softly and breathing: it waits for the partner. The
  code is printed on a paper tag leaning on the cushion (a tap copies it), and Invite your person
  opens the share sheet with the same code. When the partner joins, their half flies to this one,
  and the two meet with a burst of warm light and a success haptic. Then the app goes on.
- **I have a code:** the partner's half is gone. Once the typed code is accepted, it flies in from
  off-screen and joins this phone's half. The joiner sees the mirror moment: their own half is on
  the right.
- **Reduce Motion:** nothing travels. Each half fades in or out where it belongs, and the burst is
  a soft swell.

The pairing APIs are unchanged. In demo mode `OnboardingPairing` follows `AppModel`'s stages. With
the real backend it follows `PairingModel`, which keeps checking a shown invite every 3 s. It also
holds the joined moment on screen after the pairing itself has finished.

- **Demo backend:** the welcome also holds Try alone. Real backend: before pairing, the scene
  holds Sign in with Apple, unchanged (`SignInControls`, on `SignInModel`).
- **Replay:** Labs → First launch → Replay onboarding plays it over everything, without touching
  the pair, with a scripted partner: a made code is joined after about 4 s, and any well-formed typed
  code is joined at once.

## Choosing the cat together

Once the pair is made in the scene (demo backend), both phones open a cosy
corner with five cats on cushions: the ginger tabby, the grey and white cat and the black cat (all
the Detailed cat with a coat), the kitten and the fluffy one.

- **Picking:** a tap picks a cat. A gold heart floats over your pick and a rose paw over your
  person's, live on both phones. Picks go as room `play` frames of kind `adopt` (`move` is
  `pick`, `hold` or `adopt`). The room relays them to the partner and keeps each phone's latest
  pick and the adoption, which it replays on connect.
- **Different picks:** the two candidates step forward and make a small bid. The one on the left
  crouches and pounces, the other headbutts the air. There is no timer; either can pick again.
- **The same pick:** each partner presses and holds the cat on their own phone until their ring
  fills (1.2 s). Holding together adopts it, and so does holding one after the other. A new pick
  empties both rings. A partner who leaves lifts their finger, but their pick stays.
- **Adopted:** the cat greets you (`happy`), the others curl up, and a name field comes up. Either
  partner can name the cat (kind `rename`: the last edit wins). The cat is kept with
  `WidgetFeaturesModel.setCat`, so Labs → Cat still shows and changes it.
- **Into the room:** "Take them home": the cat walks out and the camera swings after it, the scene
  goes dark, and the room opens with its own warm-up. With Reduce Motion it only fades.
- **The fake partner** (`FakeAdopter`) picks about 2 s after you. Just over half the time it picks
  the same cat; otherwise it picks another and comes round to yours about 9 s later. It holds
  when you hold. The Labs replay plays this too, keeping nothing.

`JointCatChoice` (Pet) is the shared machine; `AdoptionModel` runs it on a phone. The scene is
`PetScene.makeAdoptionScene`, built by `AdoptionStage`/`AdoptionLayout`/`AdoptionSceneView` in
`packages/pet-scenes/reality`.

The real backend skips this step for now and keeps the standard cat; it has no frames for it.

## Where things are

- `PetScene.makeOnboardingScene(state:onEvent:)`: the contract. `OnboardingSceneState.Moment` is
  `arriving`, `resting`, `apart(partner: waiting | away)` or `together`, with `mine` (the side) and
  `code` (the tag). The scene reports `arrived`, `heartTapped`, `joined` and `codeTapped`.
- `packages/pet-scenes/reality`: `OnboardingStage` (the scene, a `TabStage`), `OnboardingLayout`
  (where things stand, `OnboardingTimeline` for the flight, `HeartMotion` for the beat,
  `HeartHalves` for the halves, `OnboardingBurst`), `OnboardingTag` (the code's face). Bloom is
  Canvas halos over the scene, as in the other tab scenes, never `customPostProcessing`.
- `packages/ios/Sources/FeatureHome`: `CinematicOnboardingView` (title and buttons over the
  scene), `OnboardingIntro` (its state), `OnboardingPairing` (the pairing steps) and
  `OnboardingPairingView`, `RealOnboardingPairing`, `OnboardingReplay`.
- The heart: `scripts/make_heart.py` in Blender (background mode), compiled by
  `scripts/bake_heart.sh`. 111 KB.
- The sill's round things (moon, candles, flames, cushion, jar, bulbs) are lathed and its boxes
  (frame, sill, books) rounded with smooth normals, by `LowPoly.lathe` and `LowPoly.roundedBox`.
