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

## The drawing Live Activity and the push lanes (#10)

PairRoom hands every accepted note to its push lanes (`apns-lanes.ts`) when the Worker has an
APNs key (`APNS_KEY`, `APNS_KEY_ID`; dev only so far):

| Lane | Token kind | `apns-push-type` | Topic | Priority |
|---|---|---|---|---|
| `WidgetPush` | `widget` | `widgets` | `com.ourio.app.push-type.widgets` | 5 |
| `AlertPush` | `alert` | `alert` | `com.ourio.app` | 10 |
| `LiveActivityPush` | `liveactivity` (push-to-start) | `liveactivity` | `com.ourio.app.push-type.liveactivity` | 10 |

- The Live Activity lane is off unless the deploy sets `LIVE_ACTIVITY_PUSH=on`. That switch
  stands in for the go/no-go #13 never recorded.
- Each try goes to every device of the partner that has a token of the lane's kind.
- A token refused with `DeviceTokenNotForTopic` is sent once more under the first App Store app's
  bundle, `com.mikitahimpel.billet` (same suffixes), so builds installed from it keep getting
  pushes. Removing `legacyBundleId` in `apns-client.ts` ends that once the owner retires the app.
- A token that APNs calls dead (410, `BadDeviceToken`, `Unregistered`, a wrong environment, or a
  topic neither bundle matches) is deleted from `push_tokens`.
- The ledger outcome is:
  - `Delivered` once any device took the push.
  - `Retry` for throttling, APNs errors, the network, or an expired provider token. The provider
    token is signed once and reused for 50 minutes; after an expired or invalid answer it is
    signed again.
  - `Abandon` when there is no one to send to, or nothing will ever be accepted.
- The alert and widget bodies carry the note's `PushPayload` under `billet`, beside `aps`. The
  alert sets `mutable-content` so the NotificationService extension can save the drawing for
  the widgets first.
- The Live Activity push is a push-to-start: `event: "start"`, `attributes-type:
  "DrawingAttributes"`, `attributes: { noteId }`, and `content-state` as the `LiveActivity`
  payload (compact strokes and paper).
- Every push stays under 4 KB with the largest drawing `InkEncoder` makes (3 KB).
- Only physical iPhones can verify any of it: the Simulator gets no APNs tokens, and widget
  push tokens are not issued there.
