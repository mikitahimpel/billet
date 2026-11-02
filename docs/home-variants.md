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

## Fake partner

With the fake partner, the full-bleed variants keep the room clear: a small amber dot sits beside
the handle, and the pulled-up panel says what it means ("Fake partner: scripted replies, on this
phone only"). Classic keeps its caption.

## Trying the hours

With Night and day chosen, Labs → Home shows **Pretend hour** (the clock, 07:00, 13:00, 19:00,
23:00). It moves the date by whole hours (`DayLight.pretending`), so the partner's sky moves with
it. Saved as `pretend-hour.json` beside the variant.

The diorama goes darker at night than the shared look, so its lamp and lantern light the room.
The styled rooms are made for the evening, so daylight only adds to their own light. The
partner's lit sky glows down from the top of the backdrop.

## Hooks for the cat

Two moments are cues, sent by whatever schedules the cat and played with the cat's clips through
`CatBehaviour.cue(_:at:)`, so every model in Labs → Cat plays them with what it has:

- `CatCue.wakeUp`: stretches (or yawns, or perks) and stays up a while.
- `CatCue.lookAtCamera`: rests where the head may turn and holds the viewer's eye for
  `CatBehaviour.viewerLook` seconds; a cat still waking looks once it is done. Any finger the head
  was following is let go.

`HomeView` owns a `CatDirector`; anything with access to it calls `director.send(.wakeUp)`, and
the newest request reaches the scene as `petSceneCatCue`. The opening sends the same cues on its
own timeline: wake at `FlyInTimeline.wake` (0.9 s), look at `FlyInTimeline.look` (3 s), so a
three-second stretch is done before the note grows in at 3.9 s. Living window's finger turns the
head through the rig, not the body.

## Limits

- The Simulator has no motion sensor, so tilt in Living window is only seen on a device.
- The opening waits for the room to load, so on a cold start it begins about 3 s after launch.

## Switching rooms

The diorama has one RealityView and the two styled rooms share another. Each is made the first
time its room is shown and then kept, hidden while the other is on screen, so a switch back is
instant. Sunset Lamp and Window Seat take turns in the same RealityView: a RealityView made while
another one exists only draws its first frame, so a second styled room in a view of its own stayed
dark (lamp off, no note, cat asleep, camera stuck mid-flight) or empty. Rooms step from the
display (`FrameClock`) rather than from RealityKit's update events, which come from every scene
in the app and so would step a room twice a frame while both views are kept.

On the Simulator, a switch shows the room within about 0.1 s for a styled room seen for the first
time, 0.6 s for the diorama the first time, and at once after that.
