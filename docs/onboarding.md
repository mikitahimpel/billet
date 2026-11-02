# First launch

With Labs → First launch → **Cinematic onboarding** on (the default), the first launch is a
3D scene: the camera glides in out of the dark over a windowsill at night, the candles light one
by one, fairy lights run along the window, and a soft glossy heart floats over a cushion, beating
gently. The title settles in partway; the buttons come once the camera is at its place. A tap
anywhere cuts the flight short, and it plays once per phone (`onboarding.introSeen`). With
Reduce Motion the scene fades up at its place instead of flying.

Off, the app shows the plain welcome and code screens it always did.

- **Demo backend:** the scene holds Create pair, Enter code and Try alone. Real backend: the scene
  holds Sign in with Apple, unchanged (`SignInControls` wraps the same model as
  `OnboardingView`).
- **Replay:** Labs → First launch → Replay onboarding plays it over everything, without touching
  the pair.

## Where things are

- `PetScene.makeOnboardingScene(state:onEvent:)`: the contract. `OnboardingSceneState.Moment` is
  `arriving` or `resting`; the scene reports `arrived` and `heartTapped`.
- `packages/pet-scenes/reality`: `OnboardingStage` (the scene, a `TabStage`), `OnboardingLayout`
  (where things stand, `OnboardingTimeline` for the flight, `HeartMotion` for the beat). Bloom is
  Canvas halos over the scene, as in the other tab scenes, never `customPostProcessing`.
- `packages/ios/Sources/FeatureHome`: `CinematicOnboardingView` (title and buttons over the
  scene), `OnboardingIntro` (its state), `OnboardingReplay`.
- The heart: `scripts/make_heart.py` in Blender (background mode), compiled by
  `scripts/bake_heart.sh`. 144 KB.
