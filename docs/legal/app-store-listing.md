# App Store listing (App Store Connect)

Everything App Store Connect asks for the first submission of Ourio 1.0.0, ready to paste. Written
2026-11-15 from the code on `main`, the landing at https://ourio.app and the other files in this
folder. Lengths are counted in characters (Apple's limits in brackets). **TODO-OWNER** marks a field
only the owner can fill; the checklist at the end gives a recommended answer for each.

The app's interface is English only (no `.xcstrings`, no `ru.lproj`). The Russian listing below is
therefore a translation of the store page only, and its description says that the app is in English.
Add Russian as a localization in App Store Connect only if that is wanted; English (U.S.) is the
primary language either way.

## App Information

| Field | Value |
| --- | --- |
| Name [30] | `Ourio: Couple Cat & Widgets` (27; see [../aso.md](../aso.md)) |
| Bundle ID | `com.ourio.app` |
| SKU | TODO-OWNER (any private string, e.g. `ourio-ios-1`) |
| Apple ID | `6832707480` (from the owner's brief; confirm in App Information > General > Apple ID) |
| Primary language | English (U.S.) |
| Primary category | **Lifestyle** |
| Secondary category | **Entertainment** |
| Content rights | **Yes, it contains third-party content, and we have the rights.** The To watch list and Pick tonight show film and show titles and posters from TMDB under its API terms; Settings > About credits TMDB ("This product uses the TMDB API but is not endorsed or certified by TMDB") and JustWatch. |
| Age rating | Answers in [age-rating.md](age-rating.md); expected result 13+ (the app stops under 13, the terms say 13+). |
| Privacy Policy URL | `https://ourio.app/privacy/` |
| Privacy Choices URL | leave empty (no opt-out page; deletion is in the app) |
| License agreement | Apple's standard EULA. Our terms are at `https://ourio.app/terms/` and in the app; there is no need for a custom EULA. |

Name: a longer name such as `Ourio: Couples App & Cat` (24) would add search words, but the brief
and the landing use `Ourio`; keep the plain name and let the subtitle and keywords carry the search
terms.

**Category, why:** couples apps (shared widgets, notes, lists, love counters) sit in Lifestyle,
which is where people browse for them; Ourio is a relationship tool first. Entertainment as the
secondary fits the virtual cat, the room you decorate and the small games without the obligations of
the Games category (Game Center expectations, games charts, game-specific review of the in-app
economy). Social Networking was the other candidate: it is for meeting or following many people,
and Ourio has exactly one partner and no feed, so it would misdescribe the app.

## Version 1.0.0: English (U.S.)

**Subtitle** [30]: `Raise a pet, draw love notes` (28)

**Promotional text** [170]:

```
Share one cozy room and a cat named Mochi with the person you love. Pet her, send a drawing or a note, and it shows up on their iPhone.
```

(135)

**Description** [4000]:

```
Ourio is a private app for two people. You share one cozy home and a cat named Mochi, and everything one of you does, the other sees on their own iPhone.

YOUR CAT, TOGETHER
Mochi lives in two rooms, a living room and a bedroom. Pet her, feed her, fill her water bowl, brush her or play with a laser dot. Looking after her earns coins for the two of you.

MAKE THE ROOM YOURS
Spend the coins you earn in the shop on furniture, plants and lights. Every piece you place appears in your partner's room as well. Coins are earned in the app; there is nothing to buy with money.

NOTES, DRAWINGS AND MOMENTS
Draw with your finger or write a note and send it. It lands on your partner's Home Screen or Lock Screen widget with a notification. Send photos to Moments and hang your favourites on Mochi's wall.

THINGS TO DO AS A PAIR
- Pick tonight: swipe through films and shows, and see the ones you both want.
- Shared lists: groceries, films to watch and places you want to go, on both phones.
- Wishlists and a shared calendar of your days.
- A daily streak for the days you both show up.
- Who knows who: a daily round of questions about one of you.
- Draw & guess: one of you draws a word, the other guesses it.

WIDGETS
Home Screen and Lock Screen widgets for the room, Mochi, your partner's latest note and drawing, your days together and more, plus Control Center buttons to pet or feed Mochi.

PRIVATE BY DESIGN
There is no sign-up form and no password: the app makes an anonymous account and keeps its key in your iCloud Keychain, and you can link Sign in with Apple in Settings to keep your account. A pair is exactly two people. There is no public feed, no ads and no third-party tracking, and we never use your drawings or photos to train AI. You can report or block your partner, unpair, or delete your account in Settings at any time.

Ourio needs two iPhones on iOS 18 or later, one for each of you. You pair with a one-time invite code. For ages 13 and up.

Terms: https://ourio.app/terms/
Privacy: https://ourio.app/privacy/
```

(1,964)

Every line above was checked against the app: two rooms (`RoomKind`, "Living room" and "Bedroom"),
four care games (`-perf.game feed|water|laser|brush`), the shop on earned coins with `payments`
off, Moments and the wall (`setPolaroids`), Pick tonight, the lists (groceries, watch, travel),
wishlists, the calendar, the streak, Who knows who, Draw & guess, the widgets (`OurioWidgets`), the
controls (Pet, Feed, Send a Hug, New Note), report, block, unpair and delete in
`PartnerAndAccountSections.swift`. Left out on purpose: getting an account back on a new phone with
Sign in with Apple (not built, checklist S1), live strokes on the Lock Screen (a widget shows the
finished drawing), any number of widgets (the count changes), any purchase.

**Keywords** [100]:

```
long,distance,relationship,games,calendar,questions,together,shared,drawing,lock,screen,doodle,cozy
```

(99). No spaces after commas (they count), no word from the name or the subtitle repeated where it
helps nothing ("cat" stays: it is the subtitle's only noun and searches for "cat" alone are common;
drop it first if a better word comes up), no competitor names.

**What's New in This Version** [4000]: App Store Connect does not show it for the first version.
If the field appears, use:

```
The first version of Ourio: a shared cat, two rooms to decorate, notes, drawings, Moments, games and widgets for the two of you.
```

**Support URL**: `https://ourio.app/support/` (live, 200 on 2026-11-15; email `support@ourio.app`).

**Marketing URL**: `https://ourio.app/`

**Copyright**: `© 2026 <PROVIDER LEGAL NAME>` (TODO-OWNER: the same name as the Apple Developer
account's seller name).

**Version**: `1.0.0` (`MARKETING_VERSION`, `apps/ios/project.yml`). Release: **Manually release
this version** (so the landing's `appStoreId` and the App Store link go live the same day).

## Version 1.0.0: Russian

Same URLs, copyright and categories.

**Subtitle** [30]: `Общая кошка для вас двоих` (25)

**Promotional text** [170]:

```
Одна уютная комната и кошка Мочи на двоих. Погладьте её, отправьте рисунок или записку, и это появится на iPhone вашего партнёра.
```

(129)

**Description** [4000]:

```
Ourio — приватное приложение для двоих. У вас общий уютный дом и кошка по имени Мочи, и всё, что делает один из вас, другой видит на своём iPhone.

ВАША КОШКА, ВМЕСТЕ
Мочи живёт в двух комнатах: гостиной и спальне. Гладьте её, кормите, наливайте воду, расчёсывайте или играйте с лазерной точкой. За заботу о ней вы вдвоём получаете монеты.

КОМНАТА ПО-ВАШЕМУ
Тратьте заработанные монеты в магазине на мебель, растения и свет. Каждая вещь, которую вы ставите, появляется и в комнате партнёра. Монеты зарабатываются в приложении; за деньги ничего купить нельзя.

ЗАПИСКИ, РИСУНКИ И МОМЕНТЫ
Нарисуйте что-нибудь пальцем или напишите записку и отправьте. Она появится в виджете на экране «Домой» или на экране блокировки партнёра вместе с уведомлением. Отправляйте фото в «Моменты» и вешайте любимые на стену Мочи.

ЧЕМ ЗАНЯТЬСЯ ВДВОЁМ
- Pick tonight: листайте фильмы и сериалы и смотрите, какие хотите оба.
- Общие списки: покупки, фильмы и места, куда хочется поехать, на обоих телефонах.
- Списки желаний и общий календарь ваших дней.
- Серия дней, когда вы оба заходите.
- Who knows who: ежедневные вопросы об одном из вас.
- Draw & guess: один рисует слово, другой угадывает.

ВИДЖЕТЫ
Виджеты для экрана «Домой» и экрана блокировки: комната, Мочи, последняя записка и рисунок партнёра, ваши дни вместе и другие, а также кнопки в Пункте управления, чтобы погладить или покормить Мочи.

ПРИВАТНОСТЬ
Нет регистрации и пароля: приложение создаёт анонимный аккаунт и хранит его ключ в Связке ключей iCloud. Пара — это ровно два человека. Нет публичной ленты, рекламы и стороннего отслеживания, и мы никогда не обучаем ИИ на ваших рисунках и фото. В настройках можно пожаловаться на партнёра, заблокировать его, разорвать пару или удалить аккаунт.

Нужны два iPhone с iOS 18 или новее, по одному у каждого. Пара создаётся по одноразовому коду приглашения. Для пользователей от 13 лет.

Приложение пока на английском языке.

Условия: https://ourio.app/terms/
Конфиденциальность: https://ourio.app/privacy/
```

(1,999; the landing's terms and privacy pages are English.)

**Keywords** [100]:

```
пара,отношения,парень,девушка,на расстоянии,виджет,питомец,кошка,кот,любовь,записки,свидание
```

(92)

**What's New** (if shown):

```
Первая версия Ourio: общая кошка, две комнаты для обустройства, записки, рисунки, моменты, игры и виджеты для вас двоих.
```

## Age rating

Enter the answers in [age-rating.md](age-rating.md) row by row. Expected: **13+**. If Apple's form
offers "Age assurance" or "Parental controls", answer No (the app asks an age range and stops under
13; there is no verification). If the result is 16+ or 18+, re-read the user-generated content and
messaging rows instead of lowering others.

## App Privacy (paste-ready)

From [app-privacy-labels.md](app-privacy-labels.md). App Store Connect > App Privacy > Get Started.

1. "Do you or your third-party partners collect data from this app?" **Yes, we collect data.**
2. Tick these data types, and nothing else:

| Category | Data type | Tick |
| --- | --- | --- |
| Contact Info | Name | Yes |
| Contact Info | Email Address, Phone Number, Physical Address, Other Contact Info | No |
| Health and Fitness | all | No |
| Financial Info | all | No |
| Location | Precise, Coarse | No |
| Sensitive Info | Sensitive Info | No |
| Contacts | Contacts | No |
| User Content | Photos or Videos | Yes |
| User Content | Other User Content | Yes |
| User Content | Emails or Text Messages, Audio Data, Gameplay Content, Customer Support | No |
| Browsing History | Browsing History | No |
| Search History | Search History | No |
| Identifiers | User ID | Yes |
| Identifiers | Device ID | Yes |
| Purchases | Purchase History | No (`payments` off) |
| Usage Data | Product Interaction | Yes |
| Usage Data | Advertising Data, Other Usage Data | No |
| Diagnostics | Crash Data, Performance Data, Other Diagnostic Data | No |
| Surroundings, Body | all | No |
| Other Data | Other Data Types | Yes |

3. For each ticked type, the three questions:

| Data type | Purposes (tick only) | Linked to the user's identity? | Used for tracking? |
| --- | --- | --- | --- |
| Name | App Functionality | Yes | No |
| Photos or Videos | App Functionality | Yes | No |
| Other User Content | App Functionality | Yes | No |
| User ID | App Functionality | Yes | No |
| Device ID | App Functionality | Yes | No |
| Product Interaction | Analytics | Yes | No |
| Other Data Types | App Functionality | Yes | No |

4. Publish. The preview should read: **Data Linked to You**: Contact Info, User Content,
   Identifiers, Usage Data, Other Data. **Data Used to Track You**: none.

"Notes" (text notes between the pair) are Other User Content, not "Emails or Text Messages": that
type is for mail and SMS the app reads. If Apple's reviewer asks, the answer is that notes are
user content sent to one partner.

## Export compliance

`ITSAppUsesNonExemptEncryption` is `NO` (`apps/ios/project.yml`), so App Store Connect does not ask
per build. If it asks anyway: "Does your app use encryption?" **Yes**; "Does it qualify for any of
the exemptions?" **Yes: only standard encryption (HTTPS/TLS through Apple's networking and the
Keychain), no proprietary or non-standard algorithms.** No documentation upload, no CCATS. The app
has no custom crypto: invite codes and sessions are hashed on the server, not in the app.

## App Review Information

| Field | Value |
| --- | --- |
| Sign-in required | **No** (the app signs in on its own; no user name or password exists) |
| Contact first name | TODO-OWNER |
| Contact last name | TODO-OWNER |
| Contact phone | TODO-OWNER (with country code; Apple calls it only if review is blocked) |
| Contact email | TODO-OWNER (recommended `support@ourio.app`, must be read during review) |
| Notes | the template below |
| Attachment | none needed; optionally a short screen recording of pairing with the code |

**Notes** (paste, then replace the two placeholders with what the admin's App Review page shows;
the code is shown there once, so never put it in the repo, a chat or a log; steps:
[app-review-runbook.md](../app-review-runbook.md)):

```
Ourio is a private app for two people, so it needs a partner. We have prepared one for you.
No account or password is needed: the app signs in on its own.

1. Open the app. On the first screen tap "I have an invite code".
2. Enter this code: <REVIEW CODE> (valid until <DATE>). If the app asks a few questions first, any answer works (choose an age of 13 or older).
3. You are now paired with our review partner and see a shared room with the cat. Within a few seconds the partner sends three notes.
4. Tap the draw button, draw something and send it; the partner replies in a few seconds. You can also add a photo in Moments, pet the cat on the Home screen, open the shop and decorate the room with coins earned in the app.

There are no payments in this version: nothing in the app can be bought with money.
Real pairing works with a 10-character invite code from the Us tab; the code above goes into the same field and is longer.

User safety: Settings > Partner has "Report partner", "Block partner" and "Unpair". Reports are logged and we read them. Settings > Delete account deletes the account and everything it sent, and unpairs the partner. If the account is linked to Sign in with Apple, deletion also revokes the Apple token.

Content in the app is only what the two paired people send each other: there is no public feed and no way to find or message strangers. The app is for ages 13 and older.

Film and show titles and posters come from the TMDB API (credited in Settings).

Contact: support@ourio.app
```

Before pasting, check the build against the notes: "I have an invite code" on the welcome
screen (`FeatureOnboarding`), the Settings labels (`PartnerAndAccountSections.swift`), the Us tab,
`payments` off (checklist S5), and that the review code was test-claimed and the pair wiped
(runbook steps 3 and 4).

## Screenshots

Made by `tools/appstore-shots` (PR #927, which replaces #886): 6.9-inch `1320x2868` and 6.5-inch `1284x2778`, PNG, no
alpha, into `~/Developer/billet-shots/appstore/<locale>/<size>/`. Upload the 6.9-inch set to
"iPhone 6.9" Display"; the 6.5-inch set is optional (Apple scales the 6.9-inch one) but sharper.
Order: Living room, Bedroom, a game, Moments, Shop, Us. They show the `-landingDemo` fixture (Alex
and Sam), not real users. No iPad set: the app is iPhone only.

## Landing claims the app does not make good

Read on 2026-11-15 from `apps/landing/src` on `main`.

| Claim | Where | What is true | Fix |
| --- | --- | --- | --- |
| Linking Sign in with Apple brings the account back on a new phone without iCloud Keychain | `help.astro` (Moving to a new iPhone), `faq.ts` (two answers), `terms.astro`, `privacy.astro` | Not built: the app signs in with the Keychain key on every launch (checklist S1) | PR #926 |
| Same claim: "unless you linked your Apple ID in Settings › Account on the old one" | `support.astro` (new phone) | As above | Left to #844, which rewrites `support.astro`: drop the "unless…" clause |
| "Whatever one of you does, the other sees on their lock screen" | `index.astro` (steps) | Petting, feeding and decor sync to the partner's app and widgets; only notes and drawings notify or reach the Lock Screen | #844 owns `index.astro`: say "on their phone" |
| "It shows up on your partner's Lock Screen and home widget, stroke by stroke, while you draw" | `index.astro` (Draw) | Strokes are live only when both have the canvas open (`features.ts` says so); the widget shows the sent drawing | #844 owns `index.astro`: drop "stroke by stroke, while you draw" from the widget sentence |
| "two games and six widgets" | `index.astro`, `faq.ts` ("Yes, six…") | `OurioWidgets` has more than six kinds (Home Screen and Lock Screen) | Not an overclaim; say "widgets" without a count when the text is next edited |
| "Ourio has no in-app purchases" | `privacy.astro`, `faq.ts` | True for 1.0.0 (`payments` off) | Revisit when coins are sold |
| "a person will answer", "we read every report" | `support.astro`, `help.astro` | A process, not code | True only while someone reads `support@ourio.app` and the report alert |

The privacy policy and terms on the landing are what users read. The drafts
[privacy-policy.md](privacy-policy.md) and [terms.md](terms.md) still call the app "Billet" and hold
placeholders; the account wording there is corrected the same way as the landing in this PR.

## Open legal questions (owner checklist)

Each is needed before or at submission; the recommended default is what to enter if there is no
reason to choose otherwise.

- [ ] **1. Provider legal name.** Recommended: exactly the Apple Developer account's legal name
      (an individual's full name for a personal account, the company name for an organization),
      because App Store Connect shows that as the seller. Goes in the copyright, the terms
      ("Who we are"), the privacy policy ("Provider") and the EU trader details.
- [ ] **2. Postal address.** Recommended: the address on the Apple Developer account. For an
      individual who does not want a home address public, a business address or a registered
      service address is fine, but it must accept mail; the EU trader status (question 9) shows it.
- [ ] **3. Country.** Recommended: the country of that address and of the developer account.
- [ ] **4. Governing law and courts.** Recommended: "These terms are governed by the laws of
      <COUNTRY>. Courts of <CITY, COUNTRY> have jurisdiction, but if you are a consumer you may also
      bring a claim in the courts of where you live, and nothing here takes away the protection of
      the law of your country." Fill `<GOVERNING LAW AND COURTS>` in `terms.md` and the landing's
      `terms.astro` with it.
- [ ] **5. Support email.** Recommended: `support@ourio.app` (already the landing's `supportEmail`
      in `apps/landing/src/site.ts`). Send one test mail to it before submitting: App Review and
      users write there, and it is the review contact email.
- [ ] **6. Retention periods.** Stated today: server logs 7 days, usage events 3 months, Pick
      tonight swipes 24 hours, notes and accounts as long as the pair or account exists. Open, with
      recommended wording: reports "kept for one year after we last act on them, then deleted";
      deleted accounts "removed at once; copies in our database backups are gone within 30 days"
      (Cloudflare D1's point-in-time restore keeps up to 30 days); invite codes "expire after 24
      hours, the hash is kept until the account is deleted".
- [ ] **7. Release date** for "Last updated" and the release itself. Recommended: "Manually release
      this version", release on the day review passes, and set "Last updated" of privacy and terms
      to the date their text last changed (2026-11-15 after PR #926), not the release day.
- [ ] **8. App Store Connect Apple ID `6832707480`.** Confirm it in App Information > General >
      Apple ID. At launch set `appStoreId` to it and `appStoreUrl` to
      `https://apps.apple.com/app/id6832707480` in `apps/landing/src/config.ts`, then deploy the
      landing (`docs/landing.md`); until then the buttons say "Coming soon".
- [ ] **9. EU Digital Services Act trader status** (App Store Connect > Business, or the prompt on
      the first submission). Recommended: **trader** if the app is meant to earn money later (coins
      for sale are planned); then Apple shows the name, address, phone and email of questions 1, 2
      and 5 on the EU product page. Choosing "not a trader" is allowed only while the app is not
      part of a business; it would have to change when payments start. Without an answer the app
      cannot be distributed in the EU.
