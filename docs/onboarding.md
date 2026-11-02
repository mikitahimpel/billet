# First launch

With Labs → First launch → **Cinematic onboarding** on (the default), the first launch is a
3D scene: the camera glides in out of the dark over a windowsill at night, the candles light one
by one, fairy lights run along the window, and a soft glossy heart floats over a cushion, beating
gently. The title settles in partway; the buttons come once the camera is at its place. A tap
anywhere cuts the flight short, and it plays once per phone (`onboarding.introSeen`). With
Reduce Motion the scene fades up at its place instead of flying.

Off, the app shows the plain welcome and code screens it always did.

## Pairing in the scene

Once the camera lands, the welcome offers **Invite your person** and **I have a code**.

- **Invite your person:** the heart opens into two halves. This phone's half stays in front, and
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
  holds Sign in with Apple, unchanged (`SignInControls` wraps the same model as
  `OnboardingView`).
- **Replay:** Labs → First launch → Replay onboarding plays it over everything, without touching
  the pair, with a scripted partner: a made code is joined after about 4 s, and any well-formed typed
  code is joined at once.

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
  `scripts/bake_heart.sh`. 144 KB.
