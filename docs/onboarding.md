# First launch

## Ourio

Ourio's first launch is `FeatureOnboarding`: `OnboardingFlow` holds the pages, `OnboardingView`
draws them. The questions come from the server (`GET /v1/onboarding`) or the bundled
`Onboarding.json`, and answers queue in `AnswerQueue` for `POST /v1/onboarding/answers`.

- **Inviter:** welcome → the server's questions → together since → the cat's coat and name →
  the invite → notifications → the widget how-to → home.
- **Joiner:** "I have an invite code" on the welcome, or an invite link, opens the code page
  first (PasteButton; typed codes are tidied to the code's alphabet). Once paired the questions
  follow; the invite is the inviter's, so it is left out. Each phone asks for together since,
  since the date is kept only on the phone. A link opened after onboarding, while unpaired,
  opens Home's pairing sheet with the code.
- **Under 13:** the `age-under-13` option stops onboarding on "See you in a few years". The answer
  is never sent, and the server refuses it from any build (`refusedOptions`); `AgeGateStopped`
  is counted.
- **Together since** stays on the phone, in `CoupleStore`.
- **Notifications:** the primer asks for permission only after its button is tapped, then the
  push tokens are registered as for drawings (`DrawingSync`).
- **The widget how-to** shows when the goals include `widgets` or `stay-close`.
- **Without a server** there is no code page, invite or notifications primer.
- **Invite links:** `https://<server>/i/<code>`. The Worker serves the
  `apple-app-site-association` file for `/i/*` (`app-links.ts`), the app has the matching
  associated domain, and `DeepLink.invite` also reads `ourio://invite/<code>`.
- **A closed app** opens again on the page it was on, with the questions and picks it had. A
  pairing that finished while it was closed moves the code page on.
