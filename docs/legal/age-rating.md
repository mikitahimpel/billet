# Age rating answers (App Store Connect)

Suggested answers for App Store Connect > App Information > Age Rating, read from the code and the
terms (13+, under-13 stop in onboarding). Not entered anywhere yet; the owner confirms each row
when entering it. Apple's questionnaire changes by year: if a question below is missing or new,
answer by the same facts.

| Question | Answer | Why |
| --- | --- | --- |
| Cartoon or fantasy violence | None | The cat and room are cosy; no violence. |
| Realistic violence | None | |
| Prolonged graphic or sadistic realistic violence | None | |
| Profanity or crude humor | None | The app ships none; what users write is covered by user-generated content below. |
| Mature or suggestive themes | None | |
| Horror or fear themes | None | |
| Sexual content or nudity (cartoon, realistic, graphic) | None | The app ships none. |
| Alcohol, tobacco or drug use or references | None | |
| Medical or treatment information | None | |
| Simulated gambling | None | Coins are earned, there are no random paid rewards. |
| Real gambling | None | |
| Contests | None | |
| Unrestricted web access | No | Links open only when the user shares one to their own wishlist; there is no browser in the app. |
| User-generated content | Yes | Notes, drawings and photos between two paired people; report partner, block partner and delete account are in Settings. |
| Messaging or chat between users | Yes | Notes between exactly two paired accounts; no public feed, no search for strangers. |
| Advertising | No | No ads, no third-party SDK. |
| In-app purchases or loot boxes | None in this version | `payments` flag is off; coins are earned (`docs/release-flags.md`). |
| Health or wellness topics | No | |
| Parental controls, age assurance | No | The app asks an age range on first launch and stops for under 13. |

Expected result: 12+ or 13+ (user-generated content). Terms say 13 or older; if Apple shows 12+,
that is fine. If it shows 17+, re-read the user-generated content and messaging answers rather
than lowering others.
