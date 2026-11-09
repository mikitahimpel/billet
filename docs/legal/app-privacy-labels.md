# App Privacy answers (App Store Connect)

The answers for App Store Connect > App Privacy, kept in step with
[privacy-policy.md](privacy-policy.md) and the manifests in `apps/ios/*/PrivacyInfo.xcprivacy`.
Change all three together whenever the usage counts (`docs/analytics.md`) or the data the app
stores change.

**Tracking: No.** Nothing is linked with other companies' data, nothing goes to data brokers or
ad networks, no third-party SDK, no App Tracking Transparency prompt.

Every type below is **linked to the user** (it is stored per account) and **not used for tracking**.

| Data type | Purpose | What it is |
| --- | --- | --- |
| Contact Info > Name | App Functionality | The name you give in onboarding and the name your partner calls you. Typed by the user, not taken from Apple. |
| Identifiers > User ID | App Functionality | The account behind the anonymous key (and the app-specific Sign in with Apple identifier when linked), and the session. |
| Identifiers > Device ID | App Functionality | A random device ID, never the advertising identifier. |
| User Content > Photos or Videos | App Functionality | Photos and drawing images sent in notes and Moments. |
| User Content > Other User Content | App Functionality | Drawing strokes, Pick tonight swipes, Who knows who answers, wishes. |
| Usage Data > Product Interaction | Analytics | The usage counts and events in `docs/analytics.md`. |
| Other Data Types | App Functionality | Onboarding answers (age range, goals), push token, app and iOS version. |

**Not collected:** email address, phone number, location, contacts, browsing or search history,
purchases (coins are earned in the app; buying them is off in the first release, so revisit
**Purchases** when `payments` is turned on), financial info, health, sensitive info, crash data
(Apple's own reports only; the app adds no diagnostics SDK).

## Manifests

`apps/ios/Nooki/PrivacyInfo.xcprivacy` declares the types above and these required-reason APIs:
UserDefaults (`CA92.1` the app's own settings, `1C8F.1` the App Group it shares with its
extensions) and system boot time (`35F9.1`, elapsed-time measurement in the drawing canvas).
`OurioWidgets`, `OurioNotifications` and `OurioShare` collect nothing of their own and declare
UserDefaults `1C8F.1` for the App Group. All four set `NSPrivacyTracking` to false with no tracking
domains. Check the list when adding an SDK or an API Apple lists as required-reason.

## Open points for the owner

- Name is declared collected because onboarding stores it with the account; `docs/privacy.md` used
  to say contact info is not collected. Say so in the policy (the draft does) or stop storing it.
- In-app account deletion is not in the app yet (`deleteAccount` exists in the client and server
  only). The App Store requires it for an app with accounts.
