# ASO research for Ourio 1.0 (2026-11-15)

Research behind [aso.md](aso.md) and [legal/app-store-listing.md](legal/app-store-listing.md): what the
competing apps do, which search terms are within reach, and what to change in the listing before and after
the first submission. Storefront: United States, English (U.S.).

## Summary

1. **Keep the name `Ourio: Couple Cat & Widgets`.** A pet-first name (`Ourio: Couple Pet & Widgets`) would
   be one word away from `ours: Couple Pet & Widget`, an app released on 2026-11-06 (table 1, row 42).
   "Cat" is what separates the two names, and "couple cat" and "cat widget" have weak competition.
2. **Change the subtitle to `Raise a pet, draw love notes` (28).** It adds *pet*, *love notes* and *raise*,
   which the current subtitle lacks. "love notes", "drawing widget", "cat widget" and "lock screen notes"
   return first results with almost no ratings; four of the first five for "long distance" have 40,000 to
   590,000.
   If long distance must stay visible, use `Pet, love notes, long distance` (30).
3. **Replace `girlfriend,boyfriend` in the keyword field.** Their searches lead to AI-girlfriend apps
   (section 2.3). Use the 20 characters for `games`, `calendar`, `questions`, which are the top autocomplete
   completions of "couples" and are real Ourio features.
4. **All 56 competitors sell in-app purchases, and 11 of them are rated 17+.** "No ads, nothing to buy,
   13+" is a difference worth one line of the description and the promotional text while it is true.
5. **Add English (U.K.) and Spanish (Mexico) keyword fields in 1.0.1** (section 6). Apple lists Spanish
   (Mexico) as a language of the U.S. storefront; that its keywords are indexed for U.S. search is a vendor
   test result, not Apple documentation.
6. **Mexico is the largest market outside the U.S. for widget and pet apps for couples** by rating counts
   (section 6). Japan and Korea belong to two local incumbents.
7. **Ask for a rating earlier than the 7-day streak** (section 4.6): the first time a partner's note arrives
   after the second day of use, then at the 7-day streak.
8. **Ship 1.0 without an App Preview video**, then test one against the screenshots (section 4.5).
9. **Apple Ads at $10 to $20 a day for three weeks** is mainly a way to learn which terms convert, and its
   keyword tool is the only free source of real search popularity (section 7).
10. Every number below comes from public Apple endpoints read on 2026-11-15. Search volume and keyword
    difficulty are **not** in this document; they need Apple Ads, AppTweak or Sensor Tower (section 9).

## Method and limits

| Data | Source | Limit |
| --- | --- | --- |
| Search results for 110 terms, top 50 each | `https://itunes.apple.com/search?term=<term>&entity=software&country=us&limit=50` | The Search API's order is not the App Store app's order; it is a proxy for who is indexed and how strong they are |
| Autocomplete suggestions for 110 terms and 24 prefixes | `https://search.itunes.apple.com/WebObjects/MZSearchHints.woa/wa/hints?clientApplication=Software&term=<term>` with the U.S. storefront header | An undocumented Apple endpoint; it may differ from the suggestions in the current App Store app. A suggestion shows that people search the phrase, not how many |
| Subtitle, chart position, in-app purchases | The app's page, `https://apps.apple.com/us/app/id<id>` | Chart position is shown only for apps in a top chart on that day |
| Ratings per country | `https://itunes.apple.com/lookup?id=<ids>&country=<cc>` | Rating counts are a proxy for installs, not installs |
| Rules | Apple's developer pages (section 10) | Where a rule comes from a vendor blog, it is marked "vendor" |

"Competition (est.)" in section 2 is computed, not measured: from how many of the returned apps have 10,000
or more ratings and from the median rating count of the first five. It is an estimate of how hard the first
page is, nothing more.

Not checked, on purpose: whether another app or trademark is called "Ourio" (the name was not sent to any
outside service).

## 1. Competitor teardown

56 apps, read on 2026-11-15. Rating and count are for the U.S. storefront. "Shots / langs / age" is the
number of iPhone screenshots, of languages, and the age rating as the lookup API returns it. Price is the
download price plus whether the page lists in-app purchases.

| # | App | Subtitle | Group | Primary category (chart) | Rating (count, US) | Price | Released / updated | Shots / langs / age | Words targeted | Learn from | Gap for Ourio |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | [Widgetable: Besties & Couples](https://apps.apple.com/us/app/id1641107226) | Share Whatever on BFF's Screen | Widgets | Social Networking (#29) | 4.92 (388,945) | Free + IAP | 2022-08-27 / 2026-11-13 | 10 / 15 / 12+ | besties, couples, widget; pets and "miss you" in the description | Shared pets plus widgets at 389k US ratings; 15 languages; first screenshot is two lines of benefit, not a feature | Built for friend groups as much as couples; no private home for two |
| 2 | [Locket Widget](https://apps.apple.com/us/app/id1600525061) | Best friends first | Widgets | Social Networking (#18) | 4.76 (592,103) | Free + IAP | 2021-12-30 / 2026-11-07 | 8 / 8 / 12+ | widget, best friends, photos | One idea in the name and first screenshot; brand is the keyword now | Photos only, friends; nothing to care for together |
| 3 | [noteit - bff widget](https://apps.apple.com/us/app/id1570369625) | bffs on your home screen | Widgets | Social Networking | 4.76 (99,277) | Free + IAP | 2021-06-04 / 2026-06-03 | 4 / 14 / 12+ | bff, widget; notes and drawing in the description | Three-step description (add widget, link, send); owns "note/drawing widget" results | No pet, no home; last update 2026-06 |
| 4 | [Note Widget - Love Drawing](https://apps.apple.com/us/app/id1608348687) | Love Drawing Picture & Video | Draw | Entertainment | 4.60 (12,342) | Free + IAP | 2022-02-03 / 2025-12-15 | 4 / 2 / 4+ | note, widget, love, drawing | Generic keyword name ranks for drawing-widget terms with 12k ratings | Thin listing (4 screenshots); last update 2025-12 |
| 5 | [Paint Love: Widget for Couples](https://apps.apple.com/us/app/id6463862890) | Draw Together on Lockscreen | Draw | Lifestyle | 4.48 (1,073) | Free + IAP | 2023-09-07 / 2026-09-11 | 3 / 1 / 4+ | paint, love, widget, couples, draw together, lockscreen | Subtitle states the one use case | 3 screenshots, 1k ratings: the draw-on-lock-screen niche has no strong owner |
| 6 | [Artmate: Drawing Together](https://apps.apple.com/us/app/id6744084538) | Learn to draw with friends | Draw | Graphics & Design (#28) | 4.83 (20,201) | Free + IAP | 2025-04-11 / 2026-11-13 | 8 / 5 / 4+ | drawing, together, learn to draw, friends | Ranks #28 in Graphics & Design with 20k ratings: a smaller category gives chart position | For drawing buddies, not couples |
| 7 | [Skizz - Drawing Together](https://apps.apple.com/us/app/id6505097805) | Drawing Together On Skizz | Draw | Utilities | 4.28 (2,464) | Free + IAP | 2024-07-25 / 2026-03-22 | 6 / 1 / 4+ | drawing together | Exact-phrase name ranks top-3 for lock-screen drawing terms | No update since 2026-03; small |
| 8 | [Cozy Couples: Relationship App](https://apps.apple.com/us/app/id6463766369) | Home for love & happy moments | Couples all-in-one | Lifestyle (#130) | 4.84 (47,190) | Free + IAP | 2023-10-10 / 2026-10-23 | 9 / 1 / 4+ | cozy, couples, relationship, home, love | "Build a cozy home for your relationship" is its first screenshot: the closest positioning to Ourio | 2D illustration; no "widget", "pet" or "cat" in name or subtitle |
| 9 | [Couple Joy - Relationship App](https://apps.apple.com/us/app/id1624758651) | Long Distance & Love Tracker | Couples all-in-one | Lifestyle | 4.85 (40,305) | Free + IAP | 2022-05-28 / 2026-10-05 | 7 / 1 / 17+ | couple, relationship, long distance, love tracker | Subtitle owns long distance + tracker; top-2 for most LDR terms | Rated 17+ by the API; counter-led, no shared pet or home |
| 10 | [Paired: Couples & Relationship](https://apps.apple.com/us/app/id1469609343) | Questions, Long Distance Games | Questions | Lifestyle (#138) | 4.72 (210,899) | Free + IAP | 2020-09-17 / 2026-11-13 | 8 / 3 / 17+ | couples, relationship, questions, long distance, games | Social proof in line 1-3 of the description (downloads, App of the Day) | Coaching and questions; 17+; nothing playful to look after |
| 11 | [Candle: Couples & Relationship](https://apps.apple.com/us/app/id6743355635) | Games, Photos, Questions, Date | Questions | Lifestyle | 4.76 (11,820) | Free + IAP | 2025-03-19 / 2026-11-12 | 9 / 6 / 17+ | couples, relationship, games, photos, questions, date | 11.8k ratings 20 months after release: the category still grows new apps | 17+; question game |
| 12 | [Loverzz: Couples App & Widgets](https://apps.apple.com/us/app/id6744887601) | Games, Would You Rather, Quiz | Couples all-in-one | Lifestyle | 4.62 (2,463) | Free + IAP | 2025-04-24 / 2026-11-03 | 9 / 1 / 9+ | couples app, widgets, games, would you rather, quiz | Name pattern "X: Couples App & Widgets" | The same pattern is used by at least five apps (Loverzz, Lovio, Den, Closer, LuviDuo): hard to stand out with it |
| 13 | [Lovio - Couples App & Widgets](https://apps.apple.com/us/app/id6743631737) | Games, Questions & Date Ideas | Couples all-in-one | Lifestyle | 4.64 (395) | Free + IAP | 2025-04-22 / 2026-11-12 | 7 / 5 / 9+ | couples app, widgets, games, questions, date ideas | All-in-one list in line 1 of the description | Same name pattern; 395 ratings |
| 14 | [Lovora: Couple Games & Widgets](https://apps.apple.com/us/app/id6746055334) | Games, Questions, Widgets | Couples all-in-one | Lifestyle | 4.47 (3,223) | Free + IAP | 2025-06-26 / 2026-11-02 | 8 / 1 / 12+ | couple, games, widgets, questions | Uses the singular "Couple" with "Games" | Generic; 3.2k ratings |
| 15 | [Den: Couples App & Widgets](https://apps.apple.com/us/app/id6760429911) | Long Distance Games, Quiz | Couples all-in-one | Lifestyle | 4.62 (45) | Free + IAP | 2026-05-10 / 2026-10-26 | 10 / 1 / 17+ | couples app, widgets, long distance, games, quiz | 10 screenshots | 17+; 45 ratings after 6 months |
| 16 | [LuviDuo: Couples App & Widget](https://apps.apple.com/us/app/id6762860746) | Long distance, games and a pet | Couples all-in-one | Lifestyle | 4.74 (330) | Free + IAP | 2026-06-03 / 2026-11-12 | 7 / 16 / 12+ | couples app, widget, long distance, games, pet | A named pet (a fox) inside an all-in-one couples app; 16 languages | Pet is one feature among many; 330 ratings |
| 17 | [Pookie: Couples Widgets, Games](https://apps.apple.com/us/app/id6756569878) | Relationship Quizzes + Photos | Couples all-in-one | Lifestyle | 4.64 (1,419) | Free + IAP | 2026-01-12 / 2026-10-31 | 10 / 10 / 12+ | couples, widgets, games, relationship, quizzes, photos; pet and doodles in the description | Pet + notes + doodles on the home screen: the same promise as Ourio, 1.4k ratings in 10 months | First screenshot claims "#1 App For Couples" and "1M+ Couples": a claim Ourio must not copy; 2D |
| 18 | [LoveBugs: Couple Widget, Games](https://apps.apple.com/us/app/id6755040251) | Draw on your partner's screen | Couples all-in-one | Lifestyle | 4.48 (105) | Free + IAP | 2025-12-18 / 2026-11-12 | 9 / 1 / 9+ | couple, widget, games, draw, partner, screen | "Draw on your partner's screen" as the subtitle; description opens with the doodle-to-widget loop | 105 ratings; no pet |
| 19 | [UsTwo - Couples & Partners App](https://apps.apple.com/us/app/id6759428131) | games widgets quiz draw share | Couples all-in-one | Lifestyle | 4.61 (855) | Free + IAP | 2026-02-24 / 2026-10-12 | 8 / 1 / 12+ | couples, partners, games, widgets, quiz, draw, share | Lists pet, canvas, questions in line 1 | Keyword-list subtitle reads as spam; 855 ratings |
| 20 | [Tethered: Long Distance Games](https://apps.apple.com/us/app/id6754725037) | Couples, Widgets, Draw, LDR | LDR | Lifestyle | 4.51 (1,074) | Free + IAP | 2025-12-05 / 2026-11-02 | 8 / 1 / 17+ | long distance, games, couples, widgets, draw, LDR | Subtitle packs four search words | 17+; includes a partner location map |
| 21 | [Bloom Together: Couples App](https://apps.apple.com/us/app/id6760342946) | Long Distance, Widgets & Games | Couples all-in-one | Lifestyle | 4.81 (432) | Free + IAP | 2026-04-09 / 2026-10-30 | 10 / 1 / 17+ | couples app, long distance, widgets, games | Opens the description against "chats and counters" | 17+ |
| 22 | [Love8 - App for Couples](https://apps.apple.com/us/app/id6448163027) | Stay close, grow your love | Couples all-in-one | Utilities (#63) | 4.61 (8,027) | Free + IAP | 2023-05-08 / 2026-11-13 | 10 / 14 / 17+ | love, app for couples | #63 in Utilities with 8k ratings: a less crowded primary category charts sooner; 14 languages | 17+; location and status sharing |
| 23 | [Between, Couples Love Tracker](https://apps.apple.com/us/app/id458035189) | Daily Relationship Tracker | Tracker | Social Networking | 4.80 (21,272) | Free + IAP | 2011-11-21 / 2026-11-05 | 5 / 6 / 4+ | couples, love tracker, daily relationship tracker | 269k ratings in Korea, 58k in Japan: the incumbent there | Chat and memories; old design; 5 screenshots |
| 24 | [SumOne: For Relationships](https://apps.apple.com/us/app/id1469506430) | Daily question game for couple | Questions | Lifestyle | 4.88 (18,573) | Free + IAP | 2019-12-20 / 2026-11-14 | 8 / 9 / 4+ | relationships, daily question, couple | Question a day; 132k ratings in Korea, 84k in Japan | No widget-first loop |
| 25 | [My Love - Relationship Counter](https://apps.apple.com/us/app/id409609608) | (none) | Tracker | Lifestyle (#29) | 4.82 (1,083,090) | Free + IAP | 2010-12-19 / 2023-05-08 | 1 / 2 / 4+ | love, relationship counter | 1.08M US ratings from one job: days together | Not updated since 2023-05; no subtitle found on the page |
| 26 | [The Couple (Days in Love)](https://apps.apple.com/us/app/id1116889464) | Couple Photos · Widget · D-Day | Tracker | Lifestyle | 4.78 (2,516) | Free + IAP | 2016-07-19 / 2026-10-19 | 10 / 7 / 4+ | couple, days in love, photos, widget, D-Day | Widget + D-Day wording for Asian markets | Counter only |
| 27 | [Couple Widget : Love Countdown](https://apps.apple.com/us/app/id1127692604) | Days Together Beautiful Widget | Tracker | Lifestyle | 4.59 (3,885) | Free + IAP | 2016-06-27 / 2026-09-17 | 7 / 12 / 12+ | couple widget, love countdown, days together | Exact-match name ranks #1 for "couple widget" in the Search API | Counter only; 3.9k ratings |
| 28 | [inlove - D-Day for Couples](https://apps.apple.com/us/app/id1189834496) | days in love counter & widget | Tracker | Lifestyle | 4.65 (5,645) | Free + IAP | 2017-12-04 / 2024-09-13 | 5 / 5 / 4+ | D-Day, couples, days in love, counter, widget | Lowercase keyword subtitle | No update since 2024-09 |
| 29 | [Lovewick: Relationship Tracker](https://apps.apple.com/us/app/id1516199115) | + Couple Questions, Date Ideas | Tracker | Lifestyle | 4.77 (1,934) | Free + IAP | 2020-10-14 / 2026-06-30 | 8 / 1 / 17+ | relationship tracker, couple questions, date ideas | Subtitle continues the name with "+" | 17+; 1.9k ratings |
| 30 | [Cupla: Couples Shared Calendar](https://apps.apple.com/us/app/id1557764033) | Plan Dates, Tasks & Reminders | Calendar | Lifestyle | 4.69 (2,343) | Free + IAP | 2021-08-25 / 2026-11-10 | 7 / 6 / 12+ | couples, shared calendar, dates, tasks, reminders | Owns "couples calendar" | Planning tool only |
| 31 | [Evergreen: Relationship Growth](https://apps.apple.com/us/app/id1573360122) | Couples Quiz, Games, & Advice | Questions | Health & Fitness | 4.82 (54,817) | Free + IAP | 2021-07-14 / 2026-09-05 | 9 / 1 / 17+ | relationship, couples, quiz, games, advice | Health & Fitness as primary | 17+; coaching |
| 32 | [Agapé: Feel Close When Apart](https://apps.apple.com/us/app/id1507907556) | Friends, Family, Couples | Questions | Health & Fitness | 4.80 (26,266) | Free + IAP | 2020-10-06 / 2026-04-05 | 7 / 1 / 17+ | close, apart, friends, family, couples | Name is a benefit, not a feature | 17+; one question a day |
| 33 | [Friends – Pengu, Bao & Mellow](https://apps.apple.com/us/app/id6462927800) | Meet Pengu, Mellow, Bao & more | Shared pet | Social Networking | 4.85 (238,186) | Free + IAP | 2023-09-30 / 2026-10-29 | 7 / 1 / 4+ | friends, named pets | Named characters in the title; 238k ratings in three years | AI companion for friend groups, not a pair |
| 34 | [Adoraboo - Raise Boos Together](https://apps.apple.com/us/app/id6478853088) | Your Boo, My Boo, Adoraboo! | Shared pet | Social Networking | 4.93 (35,417) | Free + IAP | 2024-04-17 / 2026-04-28 | 7 / 9 / 12+ | raise, together | 4.93 average on 35k ratings | Friends and neighbours; no update since 2026-04 |
| 35 | [Pokipet - Raise virtual pets](https://apps.apple.com/us/app/id6443760470) | Raise a pet with your friends | Shared pet | Games | 4.63 (12,840) | Free + IAP | 2023-05-14 / 2025-07-16 | 4 / 1 / 4+ | raise, virtual pets, friends | "Raise a pet with your friends" subtitle; a virtual cat or dog | Group pet; no update since 2025-07; 4 screenshots |
| 36 | [SUSH Virtual Pet Grow & Evolve](https://apps.apple.com/us/app/id1622502023) | Raise care love companion pet | Shared pet | Social Networking | 4.80 (42,644) | Free + IAP | 2022-05-29 / 2026-11-04 | 8 / 2 / 4+ | virtual pet, grow, evolve, raise, care, love, companion | Seven keywords in name + subtitle | Reads as a keyword list |
| 37 | [Kuku: Raise a Pet Together](https://apps.apple.com/us/app/id6741770611) | Daily rituals & quizzes | Shared pet | Social Networking | 4.58 (169) | Free + IAP | 2025-08-19 / 2026-11-08 | 6 / 1 / 12+ | raise a pet together, rituals, quizzes | Exact phrase "Raise a Pet Together" in the name; "how it works" starts with adding the widget | Friends accountability, 169 ratings |
| 38 | [FurTwo - Couples Virtual Pet](https://apps.apple.com/us/app/id6759111831) | Games, pet care & couple love | Shared pet | Lifestyle | 4.42 (88) | Free + IAP | 2026-02-25 / 2026-10-13 | 8 / 1 / 4+ | couples, virtual pet, games, pet care | Couples + virtual pet in the name | 88 ratings in 9 months |
| 39 | [Petiverse: Couple Pet Widget](https://apps.apple.com/us/app/id6753694438) | Raise virtual friends | Shared pet | Lifestyle | 3.00 (1) | Free + IAP | 2026-01-15 / 2026-01-20 | 5 / 2 / 4+ | couple pet widget, raise, virtual | Exact phrase "Couple Pet Widget" | 1 rating; no update since 2026-01 |
| 40 | [PetTomo: Shared Pet & Diary](https://apps.apple.com/us/app/id6757725650) | Raise, Feed & Bond Together | Shared pet | Social Networking | 5.00 (1) | Free + IAP | 2026-03-04 / 2026-11-01 | 5 / 4 / 4+ | shared pet, diary, raise, feed, bond, together | Verb subtitle | 1 rating |
| 41 | [IslandMates: Couple Pet](https://apps.apple.com/us/app/id6761184037) | Raise one story together | Shared pet | Lifestyle | none (0) | Free + IAP | 2026-05-12 / 2026-10-30 | 7 / 7 / 4+ | couple pet, raise, together | "One pet, one island, two people" opening line | 0 ratings |
| 42 | [ours: Couple Pet & Widget](https://apps.apple.com/us/app/id6829304811) | Relationship & Love Questions | Shared pet | Lifestyle | none (0) | Free + IAP | 2026-11-06 / 2026-11-08 | 7 / 2 / 4+ | couple pet, widget, relationship, love questions | Released 2026-11-06 as "ours: Couple Pet & Widget" | Name is one word away from "Ourio: Couple Pet & Widgets": the reason to keep "Cat" in Ourio's name |
| 43 | [DuoPet - A shared pet](https://apps.apple.com/us/app/id6827346401) | Care for a pet together | Shared pet | Games | none (0) | Free + IAP | 2026-11-06 / 2026-11-14 | 8 / 2 / 4+ | shared pet, care, together | Plain promise | Games category; 0 ratings |
| 44 | [Everlee: Couples Pet](https://apps.apple.com/us/app/id6782620245) | Long distance relationship app | Shared pet | Entertainment | 4.64 (11) | Free + IAP | 2026-07-15 / 2026-11-09 | 9 / 1 / 4+ | couples pet, long distance relationship | Pet name + LDR subtitle | 11 ratings |
| 45 | [Bixi - Raise a Pet Together](https://apps.apple.com/us/app/id6795158782) | A little pet, raised by two | Shared pet | Lifestyle | none (0) | Free + IAP | 2026-08-02 / 2026-10-27 | 4 / 1 / 12+ | raise a pet together | "A little pet, raised by two" | 0 ratings; 4 screenshots |
| 46 | [Pet Garden: Couple Pet Care](https://apps.apple.com/us/app/id6759716582) | Cozy shared pet & widget | Shared pet | Entertainment | 5.00 (1) | Free + IAP | 2026-04-03 / 2026-10-18 | 8 / 7 / 4+ | pet garden, couple pet care, cozy, shared pet, widget | Subtitle "Cozy shared pet & widget" is Ourio's own keyword set | 1 rating |
| 47 | [Finch: Self-Care Pet](https://apps.apple.com/us/app/id1528595748) | Daily Journal & Habit Tracker | Pet (solo) | Health & Fitness (#14) | 4.95 (776,001) | Free + IAP | 2021-05-12 / 2026-11-12 | 8 / 1 / 4+ | self-care pet, journal, habit tracker | #14 in Health & Fitness, 776k ratings: a pet as the reason to come back daily | Solo; not a competitor for couples terms |
| 48 | [Pixel Pals Widget Pet Game](https://apps.apple.com/us/app/id6443919232) | Cute dynamic standby animals | Pet (solo) | Graphics & Design (#108) | 4.57 (37,355) | Free + IAP | 2022-10-24 / 2026-11-13 | 3 / 1 / 4+ | pixel, widget pet, game, standby | Owns "widget pet" with 37k ratings | Solo decoration |
| 49 | [Loveit: Long Distance Couples](https://apps.apple.com/us/app/id1609366842) | Relationship noteit & locket | LDR | Entertainment | 4.46 (3,888) | Free + IAP | 2022-02-16 / 2026-10-19 | 6 / 1 / 4+ | long distance, couples, relationship | Shows what not to do | Subtitle names two competitor apps, which guideline 2.3.7 forbids |
| 50 | [Duoloft: Long Distance Couples](https://apps.apple.com/us/app/id6784116886) | 3D Room, Games, Widget & Pet | LDR | Lifestyle | 4.71 (41) | Free + IAP | 2026-07-08 / 2026-11-10 | 8 / 1 / 12+ | long distance, couples, 3D room, games, widget, pet | The only other 3D shared room found: first screenshot "A private room for two", room spans screenshots 1-2 | 41 ratings since 2026-07; framed for long distance only |
| 51 | [Cupie: LDR Games for Couples](https://apps.apple.com/us/app/id6774291368) | Long Distance Relationship App | LDR | Entertainment | 4.81 (927) | Free + IAP | 2026-06-04 / 2026-11-05 | 10 / 1 / 17+ | LDR, games, couples, long distance relationship app | 927 ratings in 5 months on a video-call idea | 17+; needs a call |
| 52 | [Lovebox - Long Distance Love](https://apps.apple.com/us/app/id1154499750) | Love knows no distance | LDR | Social Networking | 4.74 (3,894) | Free + IAP | 2016-12-07 / 2026-11-11 | 5 / 1 / 4+ | long distance, love | Widget for a hardware product | Tied to a device |
| 53 | [Bond Touch](https://apps.apple.com/us/app/id1291952832) | Tech for happier relationships | LDR | Social Networking | 4.65 (17,741) | Free + IAP | 2017-10-27 / 2026-11-09 | 10 / 6 / 4+ | (brand only) | Hardware brand search | Tied to a bracelet |
| 54 | [Lovemoe: Distance & Love Notes](https://apps.apple.com/us/app/id6756133884) | couple tracker, games & widget | LDR | Lifestyle | 5.00 (1) | Free + IAP | 2025-12-09 / 2026-11-14 | 8 / 31 / 12+ | distance, love notes, couple tracker, games, widget | "A cozy little room for the two of you" in line 1; 31 languages | 1 rating |
| 55 | [Adorable Home](https://apps.apple.com/us/app/id1486637414) | House Design & Pride Love Game | Cozy | Games (#107 in Trivia) | 4.66 (122,966) | Free + IAP | 2020-01-09 / 2026-11-03 | 10 / 12 / 12+ | adorable, home, house design, love | A couple, a cat and a home to decorate reached 123k ratings as a game | Single-player; no partner |
| 56 | [Cats&Soup: Relaxing Cozy Games](https://apps.apple.com/us/app/id1581431235) | Cute kitty home in forest ASMR | Cozy | Games | 4.88 (339,756) | Free + IAP | 2021-10-12 / 2026-11-05 | 8 / 15 / 4+ | cats, soup, relaxing, cozy games, kitty, home | 340k ratings: cats + cozy is a proven look | Idle game |

What the table shows:

- **Everyone sells something.** All 56 are free to download and all 56 pages list in-app purchases.
- **Eleven of the 56 are rated 17+**, among them Paired, Couple Joy, Candle and Love8. A 13+ app without
  "spicy" content has room next to them.
- **The name pattern `X: Couples App & Widgets` is used up** (rows 12, 13, 15, 16 and, outside the
  table, Closer). Ourio's `Couple Cat` is not used by any app found.
- **Shared-pet apps for couples are new and small.** Ten apps released since 2025-08 put a shared pet in the
  name (rows 37 to 46); none has more than 200 ratings. The large shared-pet apps (rows 1, 33, 34) are
  built for friend groups.
- **A shared 3D room exists once**: Duoloft (row 50), 41 ratings, framed for long distance only.
- **"Cozy home" is Cozy Couples' first screenshot** (row 8, 47,190 ratings), in 2D and without a widget,
  pet or cat in its name or subtitle.
- **Two listings break guideline 2.3.7**: a subtitle naming two competitor apps (row 49) and "#1 App For
  Couples" claims on first screenshots (rows 9 and 17). Ourio does neither.
- **Old leaders are not maintained**: My Love (1.08M ratings, last update 2023-05), noteit (99k, 2026-06),
  Pokipet (12.8k, 2025-07).

## 2. Keyword map

110 terms. Columns: how many of the returned apps have at least 10,000 and at least 1,000 ratings; the median
rating count of the first five; the first five with their rating counts; how many returned apps have every
word of the term in their name; whether the term is itself an autocomplete suggestion ("exact") and how many
suggestions the endpoint returned; the estimate described above; and fit for Ourio from 1 (not our feature)
to 5 (the core of the app). **Volume and difficulty are not measured here.**

**Couple widgets**

| Term | Results with >=10k / >=1k ratings | Median ratings, top 5 | Top 5 (ratings) | Name matches | Autocomplete | Competition (est.) | Fit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| couple widget | 12 / 24 of 49 | 99,277 | Couple Widget (3,885); Couple Joy (40,305); Widgetable (388,945); noteit (99,277); Locket Widget (592,103) | 26 | exact + 10 hints | High | 5 |
| couples widget | 13 / 20 of 47 | 47,207 | Couple Joy (40,324); noteit (99,284); Widgetable (388,982); Couple Widget (3,887); Cozy Couples (47,207) | 14 | exact + 10 hints | High | 5 |
| widget for couples | 13 / 26 of 43 | 99,284 | noteit (99,284); Widgetable (388,982); Couple Joy (40,324); Flowment (0); Locket Widget (592,293) | 4 | exact + 6 hints | High | 5 |
| love widget | 11 / 24 of 47 | 3,887 | Couple Widget (3,887); Love Widget (39); Couple Joy (40,324); Locket Widget (592,293); My Love (2,037) | 15 | exact + 10 hints | Medium | 4 |
| partner widget | 7 / 16 of 50 | 12,342 | noteit (99,284); Couple Joy (40,324); Note Widget (12,342); Paint Love (1,073); Love Notes Widget by P (1) | 0 | exact + 1 hints | Medium | 4 |
| girlfriend widget | 5 / 17 of 41 | 12,342 | LoveCounter (6,616); Note Widget (12,342); Photo Widget. (31,709); noteit (99,284); Couple Widget (3,887) | 0 | exact + 1 hints | Low | 2 |
| boyfriend widget | 7 / 20 of 45 | 6,616 | noteit (99,284); LoveSketch (0); LoveCounter (6,616); Note Widget (12,342); Couple Widget (3,887) | 0 | none | Medium | 2 |
| bf widget | 7 / 24 of 47 | 561 | Couple Widget (3,887); InstantWidget (2); Widget / Countdown to (4,355); COMO Widgets (561); Widget skins 17 (66) | 0 | none | Low | 2 |
| couple photo widget | 6 / 12 of 48 | 10 | Couple Photo Widget (10); HeartTap (10); WidgetPal (6,906); Stuckie (0); Together (2) | 6 | 5 hints | Low | 2 |
| photo widget couple | 8 / 13 of 48 | 10 | WidgetPal (6,906); Couple Photo Widget (10); HeartTap (10); Photo Widget. (31,709); Stuckie (0) | 5 | none | Low | 2 |
| widget friends | 16 / 19 of 42 | 99,284 | Widgetable (388,982); Locket Widget (592,293); noteit (99,284); Wallgang (0); WidgetPal (6,906) | 12 | exact + 1 hints | High | 2 |
| lock screen widget | 12 / 30 of 48 | 28,049 | LockWidget (28,049); Lock Screen Widgets‎‎‏ (113); iScreen (155,410); Widgetsmith (780,656); Lock Screen 27 (7,813) | 10 | 10 hints | High | 2 |
| lock screen notes | 4 / 10 of 48 | 109 | LockScreenNotes (1,742); LockWidget (28,049); LockNote (8); Lock Screen Notes (109); NaNote (1) | 21 | exact + 10 hints | Low | 4 |
| couple home | 11 / 24 of 48 | 47,207 | Cozy Couples (47,207); Adorable Home (122,966); Love Days Counter (409); Couple Home (0); Paired (210,919) | 4 | exact + 3 hints | High | 4 |

**Couples app (generic)**

| Term | Results with >=10k / >=1k ratings | Median ratings, top 5 | Top 5 (ratings) | Name matches | Autocomplete | Competition (est.) | Fit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| couple app | 15 / 28 of 48 | 47,207 | Cozy Couples (47,207); My Love (1,083,771); Widgetable (388,982); Love8 (8,043); Couple Joy (40,324) | 16 | 10 hints | High | 4 |
| couples app | 19 / 32 of 47 | 210,919 | Cozy Couples (47,207); Paired (210,919); My Love (1,083,771); Couple Joy (40,324); Widgetable (388,982) | 13 | exact + 10 hints | High | 4 |
| relationship app | 11 / 22 of 47 | 47,207 | My Love (1,083,771); Paired (210,919); Cozy Couples (47,207); Couple Joy (40,324); Booboo (14) | 20 | exact + 10 hints | High | 3 |
| love app | 20 / 43 of 48 | 8,043 | My Love (1,083,771); Couple Widget (3,887); Love8 (8,043); LoveCounter (6,616); Been Love Memory -Love (9,784) | 5 | 10 hints | High | 3 |
| partner app | 10 / 21 of 48 | 915 | Courial (915); JaaGa (0); Partner App (0); My Love (1,083,771); Couple Joy (40,324) | 16 | 10 hints | Low | 2 |
| together app | 4 / 20 of 49 | 39 | Together (1,642); Together (39); My Love (1,083,771); Together (22); Together Events (0) | 7 | 10 hints | Low | 3 |
| app for two | 34 / 37 of 42 | 28,421 | 2 For 2 (13,260); 123 Toddler games for (28,421); Authenticator app (5,869); Coloring Games for Kid (228,149); Preschool Games For Ki (29,833) | 2 | 2 hints | High | 3 |
| boyfriend girlfriend app | 7 / 15 of 39 | 14,872 | Kiss in Public (30,142); Girlfriend Plus (233); MeChat (98,127); How Much Does My Crush (14,872); Heartbreak Girl (303) | 0 | none | Medium | 1 |
| bf gf | 2 / 7 of 32 | 376 | Couple Days (2); Feels (4); AI Chat Girlfriend (1,297); AI Girlfriend (1,639); Ruby Chat (376) | 0 | none | Low | 1 |
| cute couple | 9 / 23 of 46 | 47,207 | Cozy Couples (47,207); Couple Life 3D (94,714); Kiss in Public (30,142); Widgetable (388,982); Couple Run! (6,692) | 7 | 9 hints | High | 3 |
| couple diary | 10 / 24 of 48 | 2,516 | Couple Tree (1,908); SumOne (18,574); Couple Diary (53); Waffle (11,069); The Couple (Days in Lo (2,516) | 9 | exact + 10 hints | Medium | 2 |
| marriage app | 14 / 27 of 47 | 49,273 | Lasting (24,991); toNikah (0); Paired (210,919); Salams (49,273); Muzz (55,220) | 8 | exact + 10 hints | High | 1 |
| husband wife | 4 / 8 of 35 | 6 | Husband Wife Simulatio (1); Prayers For Your Husba (351); Wife Fall In Love With (6); ReGain (13,405); Better Dad = Happy Wif (1) | 2 | 1 hints | Low | 1 |
| sweetheart | 0 / 2 of 21 | 2 | Sweetheart (0); Sweethearts (1); AI Sweetheart (2); Sweet Hearts Match 3 (1,116); Love Story (66) | 10 | 10 hints | Low | 1 |
| miss you | 24 / 27 of 43 | 13,496 | Meesho (13,496); HoloMissYou (14); Flipkart (111,170); Miss you (1); Widgetable (388,982) | 7 | exact + 10 hints | High | 2 |
| locket | 22 / 25 of 41 | 5,825,187 | Locket Widget (592,293); Snapchat (6,102,433); Pinterest (5,825,187); Instagram (29,715,844); BeReal (1,163,437) | 10 | exact + 10 hints | High | 1 |

**Long distance**

| Term | Results with >=10k / >=1k ratings | Median ratings, top 5 | Top 5 (ratings) | Name matches | Autocomplete | Competition (est.) | Fit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| long distance | 14 / 26 of 48 | 47,207 | Couple Joy (40,324); Locket Widget (592,293); Widgetable (388,982); Cozy Couples (47,207); Duoloft (41) | 18 | exact + 10 hints | High | 4 |
| long distance relationship | 15 / 31 of 49 | 47,207 | Cozy Couples (47,207); Couple Joy (40,324); Loveit (3,889); Paired (210,919); Locket Widget (592,293) | 1 | exact + 7 hints | High | 4 |
| long distance couple | 12 / 30 of 50 | 11,829 | Cozy Couples (47,207); Couple Joy (40,324); Candle (11,829); Loveit (3,889); Together (1) | 7 | 10 hints | Medium | 4 |
| long distance widget | 10 / 21 of 49 | 99,284 | Couple Joy (40,324); Widgetable (388,982); Locket Widget (592,293); noteit (99,284); Lovely (0) | 1 | exact + 2 hints | High | 5 |
| long distance games | 13 / 24 of 50 | 64,665 | Wavelength (64,665); Draw it (565,663); Plato (288,751); Duoloft (41); Would You Rather? Adul (20,196) | 1 | exact + 2 hints | High | 3 |
| long distance countdown | 10 / 29 of 49 | 25,122 | Couple Joy (40,324); Countdown (192,071); TimeCount (25,122); Countdown  ‎ (11,439); Pip & Pebble (3) | 0 | exact + 1 hints | High | 2 |
| ldr | 8 / 17 of 48 | 8,043 | Long Distance Relation (28); Couple Joy (40,324); Cozy Couples (47,207); Loverzz (2,463); Love8 (8,043) | 8 | 10 hints | Medium | 3 |

**Shared pet / cat**

| Term | Results with >=10k / >=1k ratings | Median ratings, top 5 | Top 5 (ratings) | Name matches | Autocomplete | Competition (est.) | Fit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| couple pet | 9 / 21 of 46 | 12,840 | Widgetable (388,982); Pookie (1,421); Friends – Pengu, Bao & (238,186); Pokipet (12,840); Everlee (11) | 8 | exact + 6 hints | Medium | 5 |
| couple widget pet | 12 / 25 of 46 | 4,545 | Widgetable (388,982); Pookie (1,421); Cute pet (4,545); Pixel Pets (5,093); Petiverse (1) | 2 | exact + 1 hints | Medium | 5 |
| shared pet | 3 / 11 of 48 | 12 | Widgetable (388,982); Friends – Pengu, Bao & (238,186); Team Pet (8); Floof (12); Collie (1) | 17 | exact + 10 hints | Low | 4 |
| pet together | 8 / 18 of 47 | 35,417 | Widgetable (388,982); Pokipet (12,840); Adoraboo (35,417); Friends – Pengu, Bao & (238,186); Bixi (0) | 4 | exact + 6 hints | High | 5 |
| raise a pet together | 6 / 15 of 45 | 35,417 | Widgetable (388,982); Pokipet (12,840); Friends – Pengu, Bao & (238,186); Adoraboo (35,417); Potater (717) | 2 | exact + 3 hints | Medium | 5 |
| virtual pet couple | 10 / 25 of 45 | 4,022 | SUSH Virtual Pet Grow (42,644); Pokipet (12,840); FurTwo (88); Pet Buddies (2,614); Pet City 2 (4,022) | 1 | none | Medium | 5 |
| virtual pet with friends | 15 / 28 of 46 | 44,141 | Pokipet (12,840); Friends – Pengu, Bao & (238,186); Widgetable (388,982); Pet Pal Paw (44,141); My Boo (18,849) | 0 | exact + 1 hints | High | 2 |
| duo pet | 7 / 20 of 45 | 0 | Duo-Pet (0); DuoPet (0); PetDuo-Cat Translator (65); DuoPet Universe (0); Grow Animals (44,705) | 2 | 2 hints | Low | 4 |
| couple cat | 9 / 25 of 47 | 19,299 | Chubby Couple Cat Anim (6); Meowtel (4,680); lovely cat dream party (37,888); Cat Game (172,043); Cat Simulator (19,299) | 3 | 1 hints | Medium | 5 |
| cat widget | 7 / 27 of 45 | 7 | Meow Widget (0); Cute pet (4,545); Cat Widget (10); Kittie (7); widget cat (0) | 8 | exact + 9 hints | Low | 4 |
| virtual cat | 16 / 29 of 45 | 65 | Ad-free Virtual Cat (65); My Cat – Virtual Pet G (109,010); Meow Time Together (0); CatsWalk (0); Little Kitten (2,066) | 13 | exact + 10 hints | Medium | 3 |
| raise a cat | 22 / 39 of 46 | 19,299 | Pokipet (12,840); Cat Rescue Story (4,670); Cat Simulator (19,299); My Cat – Virtual Pet G (109,010); Cat Game (172,043) | 0 | 1 hints | High | 3 |
| virtual pet | 15 / 26 of 47 | 18,849 | Pokipet (12,840); My Tamagotchi Forever (28,436); My Boo (18,849); Widgetable (388,982); RetroPet (6) | 27 | exact + 10 hints | High | 3 |
| widget pet | 11 / 22 of 46 | 5,093 | Widgetable (388,982); Pixel Pals Widget Pet (37,355); Pixel Pets (5,093); Pixel Pet Widget (3,187); Cute pet (4,545) | 21 | exact + 10 hints | Medium | 4 |
| pet widget | 11 / 22 of 45 | 5,093 | Widgetable (388,982); Pixel Pals Widget Pet (37,355); Pixel Pets (5,093); Cute pet (4,545); Pixel Pet Widget (3,187) | 17 | 10 hints | Medium | 4 |
| cute pet widget | 7 / 21 of 45 | 4,545 | Cute pet (4,545); Pixel Pets (5,093); Mochi Pets (228); Pixel Pals Widget Pet (37,355); Care Pet Game (1,227) | 4 | 1 hints | Medium | 3 |
| cozy pet | 10 / 16 of 41 | 4 | Cozy Pets (1,803); Guinea Pig Garden (10); Pet Game (0); Cozy Pets (0); Petie (4) | 15 | 10 hints | Low | 3 |
| pixel pet | 5 / 19 of 47 | 5,093 | Pixel Pals Widget Pet (37,355); Pixel Pet Widget (3,187); Pixel Petz (9,998); Pixel Pets (5,093); Sprout Pocket (0) | 27 | 10 hints | Low | 1 |
| kawaii pet | 8 / 21 of 47 | 133 | Pocket Kawaii (133); Mooshi (17,164); Livly Island (2,935); Chibi Koala -Kawaii Pe (2); Kawaii Pets & Friends (0) | 5 | 2 hints | Low | 2 |
| tamagotchi | 17 / 24 of 39 | 228 | My Tamagotchi Forever (28,436); Tamagotchi Adventure K (11,985); Mochi Pets (228); Remagotchi (72); GotchaTama (24) | 4 | exact + 10 hints | Medium | 1 |
| kitten game | 15 / 30 of 43 | 325 | Games for Cats (164); Kittens Game (325); Game for Cats (5); Cat Game (172,043); Cat Simulator 3D (18,547) | 8 | 7 hints | Medium | 2 |
| cat game | 29 / 37 of 46 | 283,093 | Cat Game (172,043); I Am Cat (283,093); Games for Cats Cat Toy (1,623); Meowdoku! (436,435); My Talking Tom 2 (858,698) | 18 | 10 hints | High | 2 |
| pet game | 28 / 38 of 48 | 10,081 | Pet Shop Story™ (4,708); Fluvsies (10,081); Dog Town (48,124); Pet World (4,035); My Boo (18,849) | 15 | 10 hints | High | 2 |

**Draw together / doodles**

| Term | Results with >=10k / >=1k ratings | Median ratings, top 5 | Top 5 (ratings) | Name matches | Autocomplete | Competition (est.) | Fit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| draw together | 15 / 30 of 45 | 10,008 | Artmate (20,201); Neon Draw & Draw Toget (971); ArtWorkout (261,220); DrawTogether! (95); Draw With Buddies Mult (10,008) | 12 | exact + 10 hints | High | 4 |
| couple drawing | 11 / 21 of 47 | 1,073 | noteit (99,284); Paint Love (1,073); Osoba (5); Note Widget (12,342); DrawTogether! (95) | 7 | exact + 5 hints | Low | 5 |
| drawing widget | 8 / 18 of 43 | 2 | noteit (99,284); Note Widget (12,342); Drawing Widget (2); DrawingChank Couple Wi (0); postcat (2) | 8 | exact + 7 hints | Low | 5 |
| doodle widget | 9 / 18 of 45 | 524 | noteit (99,284); Note Widget (12,342); Squibble (2); Sticky Notes Widgets (524); Whiteboard (465) | 3 | exact + 5 hints | Low | 5 |
| shared drawing | 11 / 26 of 45 | 2,478 | UsTwo (855); Skizz (2,464); InColor (2,478); Color Pop (772,136); Artmate (20,201) | 1 | 1 hints | Medium | 4 |
| draw on lock screen | 6 / 21 of 45 | 230 | Lockscreen Drawing Tog (71); Skizz (2,464); DuoArt (230); Lock Screen Draw (12); Drawing Together on Lo (365) | 0 | exact + 1 hints | Low | 4 |
| lock screen drawing | 6 / 20 of 46 | 230 | Lockscreen Drawing Tog (71); Skizz (2,464); DuoArt (230); Zumee (367); Lock Screen Draw (12) | 0 | 1 hints | Low | 4 |
| draw for partner | 9 / 24 of 44 | 20,201 | Artmate (20,201); Paint Love (1,073); Draw Creatures (61,768); Draw With Buddies Mult (10,008); Draw it (565,663) | 0 | none | High | 5 |

**Love notes**

| Term | Results with >=10k / >=1k ratings | Median ratings, top 5 | Top 5 (ratings) | Name matches | Autocomplete | Competition (est.) | Fit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| love notes | 4 / 14 of 47 | 6 | Love Notes Widget by P (1); Love Notes (6); noteit (99,284); Love Messages and Quot (8,639); Love Notes (1) | 16 | exact + 10 hints | Low | 5 |
| love notes widget | 8 / 23 of 47 | 1 | noteit (99,284); Love Notes Widget by P (1); Love Notes Widget -For (0); Note Widget (12,342); Love Notes (1) | 4 | exact + 5 hints | Low | 5 |
| love note widget | 6 / 18 of 48 | 6,615 | noteit (99,284); Love Notes Widget by P (1); Love Notes Widget -For (0); Note Widget (12,342); Sticky Notes Widget (6,615) | 6 | none | Low | 5 |
| note widget | 8 / 17 of 49 | 29,720 | Note Widget (12,342); Sticky Widgets (29,720); To Do List MinimaList (49,254); Notepad (6,705); noteit (99,284) | 28 | exact + 10 hints | High | 3 |
| notes for couples | 7 / 14 of 46 | 22 | noteit (99,284); Shared Notes (17); drawn (2); Together (22); Google Keep (29,033) | 5 | 5 hints | Low | 5 |
| couple notes | 7 / 14 of 46 | 17 | noteit (99,284); Dearlie (0); Shared Notes (17); Couple Joy (40,324); Sticky Love (0) | 11 | exact + 4 hints | Low | 5 |
| shared notes widget | 6 / 18 of 48 | 29,033 | Google Keep (29,033); noteit (99,284); Sticky Notes & Color W (6,663); Shared Note Widgets (1); Microsoft OneNote (1,072,854) | 1 | exact + 1 hints | Medium | 3 |

**Relationship tracker / days together**

| Term | Results with >=10k / >=1k ratings | Median ratings, top 5 | Top 5 (ratings) | Name matches | Autocomplete | Competition (est.) | Fit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| relationship tracker | 10 / 19 of 47 | 2,169 | My Love (1,083,771); Relationship Tracker ‎ (1,695); Couple Joy (40,324); Couples' Relationship (64); Anniversary Tracker (2,169) | 22 | exact + 10 hints | Medium | 2 |
| relationship counter | 7 / 21 of 50 | 26,269 | My Love (1,083,771); Couple Joy (40,324); Relationship Tracker ‎ (1,695); Love Counter (1,853); DayCount (26,269) | 9 | exact + 10 hints | High | 2 |
| days together | 6 / 19 of 47 | 509 | My Love (1,083,771); Days Together (10); Couple Joy (40,324); Day Together (509); LoveDays – Days Togeth (1) | 13 | exact + 10 hints | Low | 3 |
| days together counter | 3 / 16 of 46 | 6 | Love Counter — Days To (4); My Love (10,706); inlove (5,645); Love Counter; Days Tog (6); Together (0) | 7 | 2 hints | Low | 2 |
| days in love | 6 / 18 of 42 | 2,516 | My Love (1,083,771); The Couple (Days in Lo (2,516); Days Together (0); inlove (5,645); Love Counter – Time in (1,003) | 6 | exact + 5 hints | Low | 2 |
| love counter | 6 / 20 of 48 | 6,616 | My Love (1,083,771); Love Counter – Time in (1,003); LoveCounter (6,616); My Love・Relationship T (2,325); Couple Joy (40,324) | 21 | exact + 10 hints | Low | 2 |
| been together | 5 / 18 of 43 | 3,887 | Been Together(Ad) (906); My Love (1,083,771); Been Love Memory -Love (9,784); Been Together - (9); Couple Widget (3,887) | 8 | exact + 10 hints | Low | 2 |
| love tracker | 7 / 22 of 47 | 6,616 | My Love (1,083,771); My Love・Relationship T (2,325); LoveCounter (6,616); Love Counter – Time in (1,003); Couple Joy (40,324) | 19 | exact + 10 hints | Medium | 2 |
| couple tracker | 11 / 27 of 48 | 2,516 | My Love (1,083,771); Phone Tracker (9); Relationship Tracker ‎ (1,695); Couple Joy (40,324); The Couple (Days in Lo (2,516) | 6 | exact + 10 hints | Medium | 2 |
| love streak | 4 / 11 of 47 | 5,645 | DayCount (26,269); LoveCounter (6,616); inlove (5,645); My Love (2,037); Coupl (0) | 1 | 10 hints | Low | 4 |
| couple streak | 10 / 30 of 50 | 21,273 | StillTogether (2); PairStreak (33); Paired (210,919); Couple Life 3D (94,714); Between, Couples Love (21,273) | 1 | 1 hints | High | 4 |

**Anniversary / countdown**

| Term | Results with >=10k / >=1k ratings | Median ratings, top 5 | Top 5 (ratings) | Name matches | Autocomplete | Competition (est.) | Fit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| anniversary | 4 / 16 of 46 | 906 | Anniversary Tracker (2,169); My Love (1,083,771); Been Together(Ad) (906); Been Love Anniversary (7); Anniversary Wishes & C (750) | 27 | exact + 10 hints | Low | 1 |
| anniversary countdown | 10 / 27 of 47 | 10,706 | My Love (1,083,771); Countdown (192,071); Anniversary Tracker (2,169); My Love (10,706); Anniversary-Countdown (0) | 8 | exact + 10 hints | Medium | 1 |
| anniversary tracker | 7 / 19 of 49 | 2,169 | My Love (1,083,771); Anniversary Tracker (2,169); DayCount (26,269); Been Together(Ad) (906); Relationship Tracker ‎ (1,695) | 7 | exact + 10 hints | Medium | 1 |
| couple countdown | 7 / 25 of 49 | 40,324 | My Love (1,083,771); Couple Joy (40,324); Countdown (192,071); The Couple (Days in Lo (2,516); Couple Widget (3,887) | 7 | exact + 3 hints | High | 2 |
| love countdown | 6 / 28 of 46 | 10,706 | My Love (1,083,771); Couple Widget (3,887); LoveCounter (6,616); Couple Joy (40,324); My Love (10,706) | 6 | exact + 5 hints | Low | 2 |

**Cozy / room**

| Term | Results with >=10k / >=1k ratings | Median ratings, top 5 | Top 5 (ratings) | Name matches | Autocomplete | Competition (est.) | Fit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| cozy game | 20 / 35 of 48 | 60,612 | Good Coffee, Great Cof (38,890); A Little to the Left (5,985); My Sticker Room (60,612); Adorable Home (122,966); Cats&Soup (339,756) | 7 | 10 hints | High | 3 |
| cozy room | 10 / 17 of 48 | 7,310 | Cozy Room (522); My Sticker Room (60,612); Dreamy Room (308,772); My Perfect Home (7,310); Cozy Room (79) | 18 | exact + 10 hints | Medium | 3 |
| cozy home | 15 / 26 of 45 | 17,736 | Cozy Home (17,736); COZY HOME (78); Cozy Couples (47,207); Adorable Home (122,966); Tidy Home (409) | 13 | exact + 10 hints | High | 4 |
| couple room | 7 / 22 of 48 | 1,875 | Coupleroom (18); Sex Positions & Questi (19); Loverzz (2,463); Lovify (1,875); Hot Sex Game for Coupl (8,704) | 1 | exact + 2 hints | Low | 4 |
| room decorate | 16 / 36 of 49 | 48,461 | Dreamy Room (308,772); Rooms (7,760); Decor Life (232,156); Fantasy Room (48,461); Surprise Dolls Room De (0) | 0 | 10 hints | High | 2 |
| decorate room | 25 / 37 of 50 | 160,954 | Home AI (160,954); Redecor (271,607); Decor Life (232,156); My Sticker Room (60,612); Home Planner AI：Room D (46,627) | 0 | exact + 4 hints | High | 2 |
| decorate room together | 9 / 22 of 47 | 14,174 | Play Together (73,657); Roomaker (10); Decor Matters (14,174); Girly room decoration (10,527); Fantasy Room (48,461) | 0 | none | Medium | 4 |
| home decor game | 28 / 42 of 48 | 271,607 | Redecor (271,607); Design Home™ (517,824); My Perfect Home (7,310); Decor Life (232,156); Property Brothers Home (521,640) | 3 | 6 hints | High | 1 |
| shared home | 11 / 17 of 45 | 0 | Backporch (1); Homio (0); Roomli (0); HelperFlow (0); Kindred Home Swapping (1,800) | 17 | 10 hints | Low | 1 |

**Games, lists, calendar**

| Term | Results with >=10k / >=1k ratings | Median ratings, top 5 | Top 5 (ratings) | Name matches | Autocomplete | Competition (est.) | Fit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| couple game | 10 / 25 of 49 | 15,372 | Couples Games & Challe (23,324); Couple Game (5,659); Couple Game (15,372); 21 Questions (9,385); Would You Rather? Adul (20,196) | 33 | 10 hints | Medium | 3 |
| couple games | 13 / 24 of 47 | 20,196 | Couples Games & Challe (23,324); Would You Rather? Adul (20,196); Couples Games (7,131); 21 Questions (9,385); How Well Do You Know M (25,265) | 15 | exact + 10 hints | High | 3 |
| couples game | 8 / 24 of 49 | 15,372 | Couples Games & Challe (23,324); Couples Games (7,131); Couples Games, Questio (574); How Well Do You Know M (25,265); Couple Game (15,372) | 27 | 10 hints | Medium | 3 |
| couple questions | 9 / 20 of 42 | 1,582 | 21 Questions (9,385); Couple Games Questions (4,565); Flamingo Cards (1,582); Couple Questions Games (308); Questions for Couples (84) | 17 | exact + 10 hints | Low | 3 |
| shared calendar couple | 10 / 16 of 49 | 2,343 | Cupla (2,343); Pairly (0); TimeTree (93,695); Cozi Family Organizer (403,197); Couple Calendar – Shar (5) | 4 | none | Medium | 3 |
| couple calendar | 12 / 25 of 44 | 51,840 | My Love (1,083,771); TimeTree (93,695); Cupla (2,343); Couple Calendar – Shar (5); Howbout (51,840) | 12 | exact + 10 hints | High | 3 |
| couple lists | 8 / 21 of 50 | 10 | Withly – Couple Bucket (10); TwoDo (34); Cozi Family Organizer (403,197); TwoDo (3); Our Bucket List (0) | 0 | none | Low | 3 |
| couple wishlist | 4 / 14 of 49 | 0 | GiftBox (0); 100wish – Couple wish (0); Our Wish -Couple Dream (0); Wishlists (2,846); Riamo (5) | 2 | none | Low | 3 |
| wishlist couple | 3 / 11 of 49 | 0 | Lovit (0); 100wish – Couple wish (0); GiftBox (0); Wishlists (2,846); Our Wish -Couple Dream (0) | 2 | none | Low | 3 |
| date ideas | 1 / 2 of 47 | 0 | DateWay — Date Ideas (0); Date Ideas (0); Date Jar (2); Date Ideas (3); 100 Love Date Ideas (0) | 31 | exact + 10 hints | Low | 1 |

### 2.1 Autocomplete by prefix

What the suggestion endpoint returns for a bare prefix, in its order. Vendors treat the order as a
popularity signal; Apple does not document it.

| Prefix | Suggestions |
| --- | --- |
| couple | couple joy, couples games, couple360, couples app, couple widget, couple2, couples calendar, couples questions, couple question game, couples drinking games |
| couples | couples games, couples app, couples question game, couples calendar, couple joy, couples drinking games, couples widget, couples questions, couples games free, couples games for two |
| long dis | long distance couple apps, long distance bracelet, long distance, long distance games, long distance countdown, long distance dating, long distance widget, long distance friends, long distance relationship, long distance relationship games |
| relationship | relationship tracker, relationship counter, relationship questions, relationship games for couples, relationship widget, relationship, relationship games, relationship advice, relationship ai, relationship tracker widget |
| raise | raise365, raise right, raise, raise me, raise a pet together, raise a pet, ... |
| lock screen | lock screen widgets, lock screen notes, lock screen drawing, lock screen wallpapers, lock screen calendar, ... |
| shared | shared calender app, shared calendar, shared family calendar free, shared notes, shared calendar friends, shared grocery list, shared countdown, ... |
| girlfriend | ai girlfriend, girlfriend gpt, girlfriend chat, girlfriend simulator, girlfriend games, ... |
| boyfriend | boyfriend chat, boyfriend and girlfriend games, boyfriend simulator, ... |
| cozy | cozy couples, cozy games, cozy cozy, the cozy florist, ... |
| pet, cat, love, widget, virtual, partner, note, doodle, days | brands and unrelated apps (petsmart, cat vpn, love8, widgetsmith, virtual keypad, ...): the single word is too broad to aim at |

### 2.2 Where a new app can show up

Terms with fit 4 or 5, an autocomplete suggestion, and a first five that is mostly unrated:

| Term | First five (ratings) | Needs these words |
| --- | --- | --- |
| love notes, love notes widget | 1; 6; 99,284; 8,639; 1 | love, notes, widget |
| drawing widget, couple drawing widget | 99,284; 12,342; 2; 0; 2 | drawing, widget, couple |
| cat widget | 0; 4,545; 10; 7; 0 | cat, widget |
| lock screen notes | 1,742; 28,049; 8; 109; 1 | lock, screen, notes |
| lock screen drawing | 71; 2,464; 230; 367; 12 | lock, screen, drawing |
| couple notes, notes for couples | 99,284; 0; 17; 40,324; 0 | couple, notes |
| couple pet, couple widget pet | 388,982; 1,421; 238,186; 12,840; 11 | couple, pet, widget |
| couple cat | 6; 4,680; 37,888; 172,043; 19,299 (cat games, not couples apps; 3 name matches) | couple, cat |
| couple streak | 2; 33; 210,919; 94,714; 21,273 | couple, streak |

Terms with clear demand that a new app will not win soon: couple widget, couples app, long distance, long
distance relationship, virtual pet, cozy game, draw together, couple games. Their first five have a median of
10,000 to 210,000 ratings. Apple says the same in general terms: popular terms "are highly competitive –
especially if you are a newer or smaller app" ([A1]).

### 2.3 Terms to drop

- `girlfriend`, `boyfriend`: the suggestions are "ai girlfriend", "girlfriend gpt", "boyfriend chat",
  "boyfriend simulator"; "boyfriend girlfriend app" returns story and AI-companion apps and has no
  suggestion; "girlfriend widget" exists as a suggestion but its first results are counters and noteit.
  Low fit, wrong neighbours for a 13+ app.
- `partner`: the suggestions are credit unions and delivery-partner apps; only "partner widget" fits.
- `kitten`: "kitten game" returns cat-toy and simulator games.
- "anniversary", "date ideas", "tamagotchi" (a trademark), "locket", "noteit", "widgetable" (competitor
  names): not for the keyword field ([A1], [A6]).

## 3. Name, subtitle and keyword sets

Counted with code (Python `len`); no word appears twice across the three fields of a set, plural and
singular counted as the same word; no competitor name or trademark; every word is a feature of version 1.0.

| Set | Name | Subtitle | Keywords |
| --- | --- | --- | --- |
| Current | `Ourio: Couple Cat & Widgets` (27) | `Notes, drawing & long distance` (30) | `relationship,love,pet,virtual,shared,together,partner,girlfriend,boyfriend,lock,screen,kitten,cozy` (98) |
| **1 (recommended)** | `Ourio: Couple Cat & Widgets` (27) | `Raise a pet, draw love notes` (28) | `long,distance,relationship,games,calendar,questions,together,shared,drawing,lock,screen,doodle,cozy` (99) |
| 1b (long distance visible) | `Ourio: Couple Cat & Widgets` (27) | `Pet, love notes, long distance` (30) | `relationship,drawing,games,calendar,questions,together,shared,virtual,lock,screen,doodle,cozy,raise` (99) |
| 2 (plural, widget first) | `Ourio: Couples Widget & Cat` (27) | `Long distance love notes & pet` (30) | `relationship,drawing,games,calendar,questions,together,shared,virtual,lock,screen,doodle,cozy,raise` (99) |
| 3 (descriptive name) | `Ourio: Shared Cat for Couples` (29) | `Widgets, love notes & drawing` (29) | `pet,long,distance,relationship,games,calendar,questions,together,virtual,lock,screen,doodle,cozy` (96) |

In set 1 the subtitle has "draw" and the keyword field "drawing": they are different words, not a plural
pair, and "drawing widget" and "lock screen drawing" need the second form. Whether Apple treats them as one
is not documented.

### 3.1 Recommendation: set 1

- **Name stays.** Evidence for each alternative:
  - *Pet instead of Cat*: "couple pet" has six suggestions and "couple cat" one, so "pet" is the more
    searched word. But `Ourio: Couple Pet & Widgets` against `ours: Couple Pet & Widget` (row 42) invites
    confusion and a 4.1(c) or 2.3.7 question in review ([A6]), and three more apps use "Couple Pet" in the
    name (rows 39, 41, 46). Put "pet" in the subtitle instead; the name keeps "cat", where "cat widget" and
    "couple cat" are nearly empty.
  - *Couples instead of Couple*: Apple says plurals "are considered duplicates" in the keyword field ([A1]),
    which implies one form covers both. The Search API still returned different lists: 10 of the first 20
    results are shared between "couple widget" and "couples widget", 12 of 20 between "couple app" and
    "couples app". Among 157 apps in the first 15 results of the core terms, 39 names use "couples" and 23
    "couple". Suggestions use the plural for games, app, calendar and questions, and the singular for
    widget. Ourio's name is about the widget and the pet, where the singular is the phrase people type
    ("couple widget", "couple pet"). Keep the singular; check both forms in the Apple Ads keyword tool
    (section 7) before 1.1.
  - *Widget instead of Widgets*: same rule; "Widgets" reads naturally and costs one character that nothing
    else needs.
- **Subtitle changes.** The current one spends 13 characters on "long distance", a phrase whose first page
  Ourio cannot reach at launch, and has no "pet", "love" next to "notes", or "raise". Set 1's subtitle is
  also a sentence a person can read, which is what Apple asks of a subtitle ([A2]).
- **Keyword field changes.** `long,distance` move here and stay indexed. `games`, `calendar`, `questions`
  are the first completions of "couples" and are features (Draw & guess, Who knows who, the shared
  calendar). `drawing`, `doodle`, `lock`, `screen` serve the low-competition drawing and notes terms.
  `girlfriend,boyfriend,partner,kitten,virtual` go (section 2.3; "virtual pet" has 15 apps over 10,000
  ratings).
- **Why not set 2 or 3**: set 2 puts "long distance" in the subtitle and drops the readable sentence; set 3
  spends the name on "Shared ... for" and loses the exact "couple cat" and "couple widget" phrases.

Vendor claims this rests on, none of them Apple documentation: the name weighs more than the subtitle, the
subtitle more than the keyword field, and words combine across the three fields ([V1], [V7]).

### 3.2 Brand risk of a long name

- The name under the icon on the Home Screen is the bundle display name, not the store name, so "Ourio"
  stays the brand on the phone.
- Guideline 2.3.7 forbids packing metadata with "irrelevant phrases just to game the system" ([A6]).
  `Couple Cat & Widgets` describes the app; the risk is low. Do not append more words later.
- Apple's own advice is a name that is "simple, memorable" and avoids "generic terms" ([A2]). A long
  descriptive name is a trade for search weight; vendors recommend it for brands nobody searches yet ([V7]).
  Once "Ourio" has brand searches, shortening the name is a one-version change.
- Vendors report that search results cut names at about 25 to 28 characters ([V7]); at 27 the name is on
  the edge. "Ourio: Couple Cat" survives any cut.
- The name can change only with a new version; a wrong choice costs one review cycle.
- Not verified: whether another app or mark is named "Ourio".

## 4. Conversion

### 4.1 First lines of the description

Apple: "The first sentence of your description is the most important — this is what users can read without
having to tap to read more" ([A2]). Three openings (the rest of the description stays as in
app-store-listing.md):

1. `Ourio is a private home for two: one cozy 3D room, one cat you raise together, and notes you draw that
   land on each other's widgets. Whatever one of you does, the other sees on their own iPhone.` (194)
2. `Draw a note. It appears on your partner's Home Screen or Lock Screen widget. Ourio is a couples app with
   a shared cat and a home you decorate together, made for two people, near or long distance.` (195)
3. `One cat, two people. Feed her, brush her and play with her from two iPhones, decorate the rooms she lives
   in, and send each other hand-drawn love notes that show up on your widgets.` (181)

Recommended: 1. Add one line near the top while it is true: "No ads and nothing to buy." Every competitor
in table 1 has in-app purchases.

### 4.2 Promotional text

Not indexed for search ([A1]); change it whenever there is news.

1. `Share one cozy home and a cat with the person you love. Pet her, draw a note, and it lands on their
   widget. Private, for exactly two, near or far.` (146)
2. `Long distance or the same sofa: raise one cat together, send hand-drawn love notes to each other's
   widgets and keep your streak going. No ads.` (142)
3. `New here? Pair with one invite code, name your cat and send your first drawing. It shows up on your
   partner's Home Screen or Lock Screen widget.` (144)

### 4.3 Screenshot captions

The two docs disagree on the order: aso.md lists cat, drawing, decorating, games, shop, streak;
app-store-listing.md lists Living room, Bedroom, a game, Moments, Shop, Us. Use the aso.md order: the first
three are what search results show when there is no preview ([A2]), and the drawing-to-widget screen must be
among them because "Widgets" is in the name.

| # | Screen | Set A (benefit) | Set B (search words) |
| --- | --- | --- | --- |
| 1 | Living room with the cat | A cat you raise together | Your couple pet lives here |
| 2 | Drawing, and the partner's widget | Draw a note, it's on their widget | Love notes on their Lock Screen widget |
| 3 | Decorating | Decorate your home for two | A cozy room you decorate together |
| 4 | A care game | Play with your cat | Little games, long distance or not |
| 5 | Shop | Earn coins, pick new decor | A shop that runs on earned coins |
| 6 | Us: streak, calendar, lists | Keep your streak going | Streak, calendar and lists for two |

Recommended: set A for 1, 3, 4 and 6; set B for 2 and 5. Caption 5 must say the coins are earned, so the
shop does not read as a store.

Whether Apple reads caption text for search is disputed: several vendors say it has since June 2025; one
test of 64 phrases found one that ranked without metadata to explain it ([V5]). Write captions for people.

### 4.4 First screenshot and icon

Seen on the first screenshots of Widgetable, Cozy Couples, Pookie, Duoloft, noteit and Couple Joy:

- A two-line caption of three to seven words above one device or one scene; nothing else.
- The caption is a benefit ("Keep connected, stay closer", "Build a cozy home for your relationship",
  "A private room for two", "add bffs to your home screen"), not a feature name.
- Duoloft lets its room run across screenshots 1 and 2 as one picture. Ourio's room can do the same and is
  the one asset no large competitor has.
- Pookie and Couple Joy lead with "#1 App for Couples" and a rating. Do not: it is an unverifiable claim
  under 2.3.7 ([A6]).

For Ourio: screenshot 1 is the room at full width with the cat in the middle and both partners' presence
visible; the caption is five words. Screenshot 2 shows cause and effect in one frame: the drawing on one
side, the partner's widget on the other.

Icons seen: character apps fill the icon with one face (Widgetable, Pookie, Finch, Friends, Adoraboo);
couples tools use a heart or a house (Couple Joy, Cozy Couples, Duoloft). For Ourio: the cat's face, large,
no text, no heart. Apple: "simple and recognizable", "avoid adding unnecessary visual details" ([A2]).

### 4.5 App Preview video

Not for 1.0; test it after.

- A preview autoplays muted in search results and replaces the screenshots there ([A2], [A8]). A 3D room
  with a moving cat is the kind of content that gains from motion.
- The evidence that video lifts conversion is vendor material, and a vendor points out that in Apple's own example of a product
  page test the page without video won ([V6]).
- Rules: up to 30 seconds, only footage captured in the app, no hands or devices filmed ([A8]).
- Plan: a 15 to 20 second capture (cat reacts to petting, a drawing is sent, the widget updates, a lamp is
  placed) as the first product page test once there is traffic.

### 4.6 Rating prompt

Apple: at most three prompts in 365 days; ask "only after people have demonstrated engagement", never on
first launch or in onboarding, not in the middle of a task, and "at least a week or two between requests"
([A3], [A4]). Custom prompts are disallowed; use the system one ([A6]).

aso.md says once, after a 7-day streak. That is safe but late: only people who keep a streak for a week ever
see it, and ratings show in search results and "can influence how your app ranks" ([A1]). Proposed:

1. First request: the first time a note or drawing from the partner arrives while the app is open, on the
   third day of use or later, after the user closes the note.
2. Second: at the 7-day streak, if at least 14 days have passed.
3. Third: at the 30-day streak or the first anniversary shown in the app.

Never after an error, during pairing, or in a game. Do not gate the prompt behind an "enjoying Ourio?"
question that sends unhappy users elsewhere: the guidelines name "filtered" feedback among the ways of
manipulating reviews ([A6]).

### 4.7 Review responses

Apple: reply in a "friendly tone", "concise", without "marketing language"; prioritise "the lowest star
ratings or those mentioning technical issues"; the reviewer is notified and can update the review ([A3]).

- Answer every review in the first 30 days, one- to three-star reviews within 24 hours.
- State what was fixed and in which version; when a fix ships, edit the reply.
- Pairing problems: give `support@ourio.app`; never ask for an invite code or any personal detail in public.
- No templates, no thanks-for-five-stars boilerplate, no promises of dates.

## 5. Category

Where the competitors sit (157 apps in the first 15 results of 18 core terms):

| Primary category | All | With 1,000+ ratings |
| --- | --- | --- |
| Lifestyle | 78 | 24 |
| Entertainment | 23 | 10 |
| Games | 20 | 12 |
| Social Networking | 17 | 8 |
| Utilities | 6 | 2 |
| Health & Fitness | 5 | 4 |

Chart positions shown on product pages on 2026-11-15 (top free, iPhone, U.S.):

| App | Ratings | Chart |
| --- | --- | --- |
| Locket Widget | 592,103 | #18 Social Networking |
| Widgetable | 388,945 | #29 Social Networking |
| My Love | 1,083,090 | #29 Lifestyle |
| Cozy Couples | 47,190 | #130 Lifestyle |
| Paired | 210,899 | #138 Lifestyle |
| Love8 | 8,027 | #63 Utilities |
| Artmate | 20,201 | #28 Graphics & Design |
| Finch | 776,001 | #14 Health & Fitness |

- **Primary: Lifestyle (keep).** It is where couples apps are, and Apple says to choose by purpose, by where
  users look, and by where similar apps are ([A5]). The primary category decides the chart and the tab.
- **Social Networking** fits Apple's wording ("interpersonal connections ... photo & video sharing") and holds
  the widget leaders, but its chart needs Locket-scale downloads, and the app has no feed. Not as primary.
- **Games** as primary would move Ourio to the Games tab and its charts and into a costlier ad category
  than Lifestyle (section 7). The app is a relationship tool with games in it. No.
- **Utilities or Graphics & Design** chart with far fewer ratings (Love8, Artmate), but Apple rejects
  categories that do not fit ([A2]). No.
- **Secondary: Entertainment (keep).** The secondary category is indexed for search but gives no chart
  ([A1], [A5]). One side effect: an app with Entertainment or Games as either category falls under that
  Screen Time allowance category ([A5]), which matters for 13 to 17 year olds with limits. Social
  Networking as secondary avoids that and matches the widget leaders; it is a defensible swap, without
  evidence that it changes search.

## 6. Localization

Ratings of 13 competitors per storefront (Widgetable, Locket, noteit, Paired, Between, Couple Joy, Cozy
Couples, My Love, SumOne, Friends, Love8, Candle, Adoraboo), and of the five widget-and-pet apps closest to
Ourio (Widgetable, noteit, Couple Joy, Friends, Adoraboo):

| Storefront | All 13 | Widget and pet (5) | Largest there |
| --- | --- | --- | --- |
| United States | 2,796,102 | 802,193 | My Love, Locket, Widgetable |
| Mexico | 258,011 | 216,476 | noteit (109,505), Widgetable (63,230) |
| United Kingdom | 247,786 | 96,232 | My Love, Friends |
| Brazil | 97,009 | 79,678 | Widgetable (45,786), noteit |
| Germany | 428,930 | 69,986 | My Love (331,976) |
| France | 90,205 | 52,603 | Locket, Widgetable |
| Canada | 112,248 | 46,463 | My Love, Locket, Widgetable |
| Spain | 53,549 | 43,885 | Widgetable, noteit, Couple Joy |
| Turkey | 51,974 | 41,664 | Widgetable, noteit |
| Italy | 41,632 | 31,883 | Widgetable |
| Vietnam | 444,092 | 30,312 | Locket (402,392) |
| Australia | 72,150 | 27,677 | My Love, Locket, Widgetable |
| Japan | 154,508 | 4,502 | SumOne (84,406), Between (57,942) |
| South Korea | 413,865 | 3,359 | Between (269,226), SumOne (131,971) |

Reading: Spanish-speaking Latin America is the second market for this kind of app; Brazil, the U.K., Germany
and France follow. Japan and Korea are large for couples apps but belong to Between and SumOne, and the
Western widget apps have almost no ratings there: they need a translated app and a different pitch, not a
translated listing.

The app is English only, so a translated listing promises a language the app does not speak. Order:

| Step | Locale | What | Why |
| --- | --- | --- | --- |
| 1.0.1 | English (U.K.) | Same name and subtitle; a different keyword field, for example `cosy,room,decorate,home,virtual,days,counter,tracker,streak,wishlist,lists,ldr,cute,kawaii,photo` (96) | Apple lists English (U.K.) as an additional language in Germany and Brazil, among others ([A7]); AppTweak's table adds France, Spain, Korea and Mexico and reports the keywords indexed there ([V2]). "cosy" is the British spelling. Words combine with the name and subtitle of the same locale |
| 1.0.1 | English (Australia), English (Canada) | Same texts as U.K. | Default language of those storefronts ([A7] for Canada, [V2] for Australia) |
| 1.0.1 | Spanish (Mexico) | English name and subtitle; keyword field with the next-best English words not used in en-US | Apple lists Spanish (Mexico) as an additional language of the U.S. storefront ([A7]); AppTweak's tests found its keywords indexed in U.S. search ([V2]). 100 more characters for the U.S. |
| When the app has Spanish | Spanish (Mexico), Spanish (Spain) | Real Spanish name, subtitle, keywords, screenshots | Mexico is the default-language storefront and the largest market found; the U.S. trick ends here |
| Later, with the app translated | Portuguese (Brazil), German, French | Full localization | Next by rating counts |
| Not now | Japanese, Korean | | Incumbents, different product expectations |

**The Spanish (Mexico) claim, checked.** Apple's localization reference lists, for the United States,
"English (US)" as default and "Arabic, Chinese (Simplified), Chinese (Traditional), French, Korean,
Portuguese (Brazil), Russian, Spanish (Mexico), Vietnamese" as additional supported languages ([A7]). That
page is about which language a customer sees. That keywords of those locales are *indexed* for U.S. search
comes from AppTweak and Phiture tests with made-up keywords, first run for a 2022 book, on a page last
updated 2025-11-21 ([V2]). The same source says words do **not** combine across locales: "widget" in en-US
and "novios" in es-MX do not make "widget novios". So each locale's field should hold whole phrases.
Verify after 1.0.1 by searching the U.S. store for a word that exists only in the es-MX field.

Keywords are indexed per locale, so translate ideas, not words; a second English locale is the place for
the words that did not fit, not for repeats.

## 7. Apple Ads and measurement

### 7.1 Apple Ads starter plan

Apple Ads Advanced: cost per tap, a daily budget per campaign, keyword control ([A9]). Apple's recommended
structure is four campaigns: brand, category, competitor, discovery; exact match in the first three, broad
match and Search Match only in discovery, with the other campaigns' keywords as negatives there ([A10]).

| Campaign | Exact-match keywords | Daily budget (est.) |
| --- | --- | --- |
| Brand | ourio, ourio app | $1 to $2 |
| Category: pet and cat | couple pet, couple widget pet, raise a pet together, shared pet, pet widget, cat widget, couple cat, virtual pet with friends | $3 to $6 |
| Category: notes and drawing | love notes, love notes widget, couple notes, drawing widget, couple drawing widget, lock screen notes, lock screen drawing, doodle widget | $3 to $6 |
| Category: couples | couple widget, couples widget, widget for couples, couples app, long distance widget, long distance couple apps, long distance relationship, relationship widget, couples games long distance | $3 to $6 |
| Competitor (optional, week 2) | names of the apps in table 1 rows 1, 3, 8, 9, 17 | $0 to $3 |
| Discovery | Search Match on; broad: couple, widget, pet, cat, long distance; all the above as exact negatives | $2 to $3 |

Competitor names belong in an ads campaign only ([A10]); never in the listing ([A1], [A6]).

Budget: $10 to $20 a day for 21 days, $210 to $420. Benchmarks for scale, all vendor data: U.S. Lifestyle
median cost per tap $1.18 and cost per install $2.62 in 2025; Entertainment $2.42 and $4.99; Social
Networking $0.90 and $1.45; Games $2.03 and $4.63 ([V3]). At the Lifestyle median that budget buys roughly
80 to 160 installs; this is an estimate, and a couples app needs two installs to make one pair.

Version 1.0 earns nothing, so this is spending to learn:

- **Search popularity** in the Apple Ads keyword tool for every term in section 2: the only free first-party
  volume signal ([A11]). This alone justifies opening the account before 1.1.
- Per keyword: impressions, tap-through rate, conversion rate, cost per install. A keyword with a high
  tap-through and conversion rate belongs in the name or subtitle of 1.1.
- Search Match terms report: words nobody here thought of.
- In the app's own analytics (first-party, already there): share of ad installs that pair, and day-7
  retention of pairs.
- Stop rules: pause a keyword after 30 taps without an install; cap bids at twice the Lifestyle median.

### 7.2 Organic measurement

App Store Connect Analytics, weekly:

- Impressions, product page views, conversion rate and first-time downloads, by
  source: App Store Search, App Store Browse, Web Referrer, App Referrer.
- Search share of downloads: the measure of whether the metadata works.
- Conversion rate against Apple's peer-group benchmark.
- Retention day 1, 7, 28; crashes; ratings by territory.
- A campaign link (`ct=` parameter) on every outside link: the landing page, each social post.

Not available from Apple: rank per keyword. Check the terms of section 2.2 by hand in the App Store
weekly, or pay for a tracker later.

Product Page Optimization: one test at a time, up to three treatments, up to 90 days, icon, screenshots and
previews only; an alternative icon must already be in the app binary ([A12]). Name and subtitle cannot be
tested this way. Order:

1. First screenshot: the room with the cat against the drawing-to-widget pair.
2. Caption style: set A against set B (section 4.3).
3. App Preview video against no video.
4. Icon: needs the alternates in a build, so plan it into 1.1.

A test needs traffic; with a few hundred impressions a week it will not reach confidence in 90 days. Run
test 1 only once Search and Browse impressions pass a few thousand a week (an estimate; vendors give
similar floors, [V6]).

Custom product pages (up to 70, their own screenshots and promotional text, reviewed without a new version)
can be assigned keywords and then appear in organic search for them ([A13]). Make two after launch: "long
distance" (leading with the widget and the streak) and "cat" (leading with the room and the games).

App Store Tags (U.S. only): Apple generates tags from the en-US metadata; they show in search results and on
the page, and can be deselected in App Information ([A14]). Check them the day the app is approved.

In-App Events appear in search results and on the page ([A15]): a limited-time decor set or a seasonal
room qualifies; daily rewards do not.

## 8. First 30 days

Before submitting:

- [ ] Subtitle and keyword field of set 1 (or 1b).
- [ ] Description opening 1; a "no ads, nothing to buy" line.
- [ ] Screenshot order of aso.md; captions of section 4.3; caption 5 says the coins are earned.
- [ ] Check that no caption or text promises account recovery through Apple, a drawing as wallpaper, or a
      purchase (aso.md, "Honesty limits").

Day 0 to 2:

- [ ] Review App Store Tags; deselect any that do not fit.
- [ ] Search the store for "ourio" and for the name; note the position and who else appears.
- [ ] Campaign links on the landing page and every post.
- [ ] Open an Apple Ads account; read search popularity for the section 2 terms; start the brand campaign.

Week 1:

- [ ] Reply to every review; fix what one-star reviews name.
- [ ] Record by hand the rank for the terms of section 2.2 and for couple widget, couples app, long
      distance.
- [ ] Start the category and discovery campaigns.
- [ ] Ship the rating prompt of section 4.6 if it is not in 1.0.

Week 2:

- [ ] Read Analytics by source; compare conversion with the peer benchmark.
- [ ] Add winning Search Match terms as exact keywords; add negatives.
- [ ] Prepare 1.0.1 metadata: en-GB, en-AU, en-CA, es-MX keyword fields.

Week 3:

- [ ] Submit 1.0.1; after approval, test the es-MX indexing claim with a word unique to that field.
- [ ] First product page test if impressions allow.
- [ ] Two custom product pages with keywords.

Week 4:

- [ ] Decide the 1.1 name, subtitle and keywords from ad and rank data; "couple" or "couples" from search
      popularity.
- [ ] Record the App Preview video for the next test.
- [ ] Plan the first In-App Event.
- [ ] Update the promotional text.

## 9. Risks and what could not be verified

- **No search volume.** Every "competition" and "fit" value is an estimate from result strength and
  suggestions. AppTweak, Sensor Tower or the Apple Ads keyword tool is needed for volume and difficulty.
- **Search API is not App Store search.** Order and membership can differ from what a phone shows,
  especially with personalisation and ads.
- **The suggestion endpoint is undocumented** and may not match the App Store app.
- **Field weights and cross-field combination** (name over subtitle over keywords) are vendor claims.
- **Singular and plural**: Apple's keyword guidance treats them as duplicates; the Search API returned
  different lists. Unresolved.
- **"draw" and "drawing"**: whether Apple matches one to the other is unknown.
- **Screenshot captions as a ranking input**: disputed between vendors; no Apple statement found.
- **A ranking boost for new apps**: old vendor claim; a 2026 vendor study of 34 apps found none ([V8]).
  Do not plan around it.
- **es-MX and other secondary locales indexed in the U.S.**: Apple documents the languages, vendors the
  indexing.
- **App Preview lift**: no independent data.
- **Ad benchmarks** are medians over other advertisers; Ourio's costs will differ.
- **Chart positions** are one day's snapshot and depend on downloads, not ratings.
- **Rating counts per country** stand in for market size; they favour old apps.
- **"Ourio" name clash or trademark**: not checked.
- **Age ratings** in table 1 are the lookup API's values (4+, 9+, 12+, 17+), not the 2025 rating scale.
- **Competitor features** are read from names, subtitles, first screenshots and the opening of descriptions,
  not from using the apps.
- **The description in app-store-listing.md** says there is no sign-up and the account is anonymous; Sign
  in with Apple now exists in the Profile. Check that paragraph before submitting.

## 10. Sources

Apple documentation:

- [A1] App Store search: https://developer.apple.com/app-store/search/
- [A2] Creating your product page: https://developer.apple.com/app-store/product-page/
- [A3] Ratings, reviews, and responses: https://developer.apple.com/app-store/ratings-and-reviews/
- [A4] Human Interface Guidelines, Ratings and reviews:
  https://developer.apple.com/design/human-interface-guidelines/ratings-and-reviews
- [A5] Choosing a category: https://developer.apple.com/app-store/categories/
- [A6] App Review Guidelines (2.3.1, 2.3.7, 3.2.2, 4.1, 5.6):
  https://developer.apple.com/app-store/review/guidelines/
- [A7] App Store localizations:
  https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations/
- [A8] App previews: https://developer.apple.com/app-store/app-previews/
- [A9] Compare Apple Ads solutions:
  https://ads.apple.com/app-store/help/apple-ads-basic/0001-compare-apple-ads-solutions
- [A10] Apple Ads campaign structure: https://ads.apple.com/app-store/best-practices/campaign-structure
- [A11] Apple Ads keywords: https://ads.apple.com/app-store/best-practices/keywords
- [A12] Product page optimization: https://developer.apple.com/app-store/product-page-optimization/
- [A13] Custom product pages: https://developer.apple.com/app-store/custom-product-pages/
- [A14] Manage app tags:
  https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-tags
- [A15] In-App Events: https://developer.apple.com/app-store/in-app-events/

Apple public data: the Search, lookup and suggestion endpoints and product pages named under "Method"; each
app in table 1 links to its page.

Vendor blogs (opinion or their own tests, not Apple documentation):

- [V1] AppTweak, the iOS keyword field:
  https://www.apptweak.com/en/aso-blog/how-to-optimize-your-ios-keyword-field
- [V2] AppTweak, primary and secondary languages per storefront (tests with Phiture):
  https://www.apptweak.com/en/aso-blog/how-to-benefit-from-cross-localization-on-the-app-store
- [V3] AppTweak, Apple Ads benchmarks 2026: https://www.apptweak.com/en/aso-blog/apple-ads-benchmarks
- [V4] AppTweak, singular and plural keywords:
  https://www.apptweak.com/en/aso-blog/do-singular-or-plural-keywords-rank-differently-in-aso
  and MobileAction: https://www.mobileaction.co/blog/singular-or-plural-keywords-aso/
- [V5] Screenshot text indexing, for and against:
  https://appscreenshotstudio.com/blog/how-apple-ocr-indexes-app-store-screenshot-text-2026 and
  https://appdrift.co/blog/app-store-screenshot-text-indexing
- [V6] App Preview video and conversion:
  https://appscreenshotstudio.com/blog/app-preview-videos-vs-screenshots-2026-conversion-data and
  https://trysonar.app/blog/app-preview-video-conversion-impact
- [V7] AppTweak, keywords or brand in the app name:
  https://www.apptweak.com/en/aso-blog/optimizing-your-app-title-keywords-vs-brand-name
- [V8] Sonar, new-app boost study: https://trysonar.app/blog/app-store-new-app-boost
- [V9] MobileAction, cross-localization: https://www.mobileaction.co/blog/app-store-cross-localization/
