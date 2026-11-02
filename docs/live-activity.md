# Live Activity: the cat is on its way

The app starts the activity itself when a note sets off for the wall and ends it when the note is
hung (`CatTripController`). The content is `CatTrip.Content` in `WidgetBridge`: a phase, the start,
the expected arrival and whether a heart was asked for. The progress bar is a timer interval
between the two dates, so it moves without any update.

## What ActivityKit push needs later

The app change is small: request the activity with `pushType: .token` in
`CatTripController.Backend.activityKit`, observe `pushTokenUpdates`, and send each token to the room.
Nothing is sent today.

The backend must add, none of which exists yet:

- **Storage for tokens.** A per-device activity push token, plus the device's push-to-start token
  (iOS 17.2+), kept next to the existing APNs device token and dropped on logout.
- **An APNs client for Live Activities.** Topic `<bundle id>.push-type.liveactivity`,
  `apns-push-type: liveactivity`, and `apns-priority` 10 for the start and the end. The current
  client sends alerts only.
- **Start from the server.** When a note is stored for a partner whose phone is not running the app,
  send a push-to-start payload (`event: "start"`, `attributes-type: "CatTripAttributes"`,
  `attributes: { catName }`, `content-state` in the shape of `CatTrip.Content`).
- **End from the server.** There is no server signal for "hung", because hanging happens in the
  scene. Either send `event: "end"` after the same expected duration, or add a `hung` frame the app
  sends and the server relays.
- **Heart.** The heart button queues locally. Delivering it while the app is closed needs a way for
  an intent to reach the room (an authenticated HTTP endpoint instead of the socket).
- **Dates as numbers.** Payload dates are seconds since 1970; `CatTrip.Content` decodes with the
  default `Date` strategy, so the payload keys must match, or the app switches both sides to one
  explicit strategy.
