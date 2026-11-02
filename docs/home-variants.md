# Home variants

Settings → Labs → Home picks how the first screen meets the room. The choice is kept in the App
Group as `home-variant.json` (`WidgetFeaturesModel.homeVariant`), so it survives relaunches.
Classic is the default. Every variant works with Nooki, Sunset Lamp and Window Seat.

| Variant      | What it does                                                                                                                                                                                        |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Classic      | Home as it was: the header chips, the room card and the cards below it.                                                                                                                             |
| Immersive    | The room fills the screen, under the status bar and behind the tab bar. One gold pen draws; a handle at the foot pulls up a panel with the streak, renovate, closet, shop and every card. |
| Cinematic    | Immersive, plus an opening once per launch: the camera flies in, the lights come up, the cat wakes and looks at the camera, then the note grows in. A tap skips it; Reduce Motion shows its end. |
| Living window| Immersive, plus a room that answers touch: a finger on the room is watched by the cat, holding it gives a treat, and the camera leans with the phone. Controls fade in after 3 s untouched.   |
| Night and day| Immersive, lit by the local hour (morning, day, golden hour, night with the lamp on). When the partner shares a time zone, the window (Nooki) or the sky behind the room shows their hour. |

Home falls back to Classic at accessibility type sizes and while the room is being renovated.

## Pieces

- `Pet/HomeVariant.swift`: the variants and their titles.
- `Pet/DayLight.swift`: the light of an hour, from the clock only (no location).
- `PetScene/PetSceneDirection.swift`: `FlyInTimeline`, the opening's timings shared by host and
  scene, and the environment values a host sets on a scene (`petSceneFlyIn`, `petSceneGaze`,
  `petSceneOrbits`, `petSceneFollowsTilt`, `petSceneShowsControls`, `petSceneFillsView`,
  `petSceneDayLight`, `petSceneOpeningEnded`, `petSceneCatCue`).
- `PetSceneReality/SceneDirection.swift`: the flight state and the room lighting per hour, used by
  both `NookiDiorama` and `GenzRoom`.
- `FeatureHome/FullBleedHome.swift`: the full-bleed layout, gestures, opening and panel.

## Hooks for the cat

The cat's own animation is not built here. Two moments are cues, sent by whatever schedules the
cat and played by the scene with the cat's clips:

- `CatCue.wakeUp`: opens its eyes and gets up for a few seconds.
- `CatCue.lookAtCamera`: turns to face the camera.

`HomeView` owns a `CatDirector`; anything with access to it calls `director.send(.wakeUp)`, and
the newest request reaches the scene as `petSceneCatCue`. The opening sends the same cues on its
own timeline (`FlyInTimeline.wake`, `FlyInTimeline.look`).

## Limits

- The Simulator has no motion sensor, so tilt in Living window is only seen on a device.
- The Nooki cat turns its whole body to look: no clip turns the head alone.
- Night and day follows the real clock; the night look is only seen at night or in tests.
- The opening waits for the room to load, so on a cold start it begins about 3 s after launch.
