# First launch

## Ourio

Ourio's first launch is `FeatureOnboarding`: `OnboardingFlow` holds the pages, `OnboardingView`
draws them. The questions come from the server (`GET /v1/onboarding`) or the bundled
`Onboarding.json`, and answers queue in `AnswerQueue` for `POST /v1/onboarding/answers`.

- **Inviter:** welcome → the server's questions → together since → the cat's coat and name →
  the invite → notifications → the widget how-to → home.
- **Joiner:** "I have an invite code" on the welcome, or an invite link, opens the code page
  first (PasteButton; typed codes are tidied to the code's alphabet, and a pasted message gives up
  its code or link). Once paired the questions follow; the invite and the cat are the inviter's,
  so the coat and name pages are left out too. Each phone asks for together since, since the
  date is kept only on the phone.
- **One cat:** the inviter's phone adopts the pair's cat (`PUT /v1/cat`) once it learns of the
  pair; the joiner's phone waits for her (the room's `CatSaved` frame starts a sync) and takes her
  name, coat and pronouns. After `CatLife.joinerWaits` with no cat in the room it adopts its own.
- **The inviter learns of the pair** from `GET /v1/pair`: the invite page asks every 3 s, and so
  does the app on any screen while an invite is out; at launch and on each return to the app an
  unpaired account asks once, so a pair made while the app was closed is not missed
  (`ServerSession.watchPair`).
- **Partner names** stay on each phone; the server has none yet. A paired partner with no name on
  this phone reads "Partner" and has a person glyph instead of an initial. A link opened after onboarding, while unpaired,
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
- **Sign in with Apple** is not part of onboarding: the account is anonymous, and linking an Apple ID is
  optional, in Settings > Account (`AppleAccountSection`, under Settings' Account row). Recovering an account from the welcome is not built
  yet ([release-checklist.md](release-checklist.md) S1).
