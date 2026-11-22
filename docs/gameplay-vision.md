# Gameplay vision

Status: **working notes** (stage 1 of 5). The final proposal replaces these notes.

## Working notes

### Stage 1: audit (in progress)

Real usage numbers: **not read yet**. `scripts/admin-read.sh` fails before any request: Proton Pass
has no item `cloudflare-agents` in vault `Ourio` (`.env.pass.agents`). Reported to the manager.
Everything below is from the code and docs only.

**Loops found so far**

| Loop | Rhythm | Needs both? | Evidence |
| --- | --- | --- | --- |
| Care for the cat (pet, feed, water, laser, brush) | several times a day; needs fall with time constants of 6 h (full), 14 h (loved), 10 h (playful) | no | `LifeConfig.swift`, `MiniGame.swift` |
| Note, drawing, photo to the partner's widget | free | one sends, one receives | `docs/widgets.md`, `NoteSent` |
| Love streak | daily, lights when both acted | yes | `docs/love-streak.md` |
| Who knows who | daily, 5 questions, hidden until both answer | yes | `docs/who-knows-who.md`; deck is 150 questions = 30 days |
| Draw and guess | free, async, one open riddle each | yes | `docs/draw-guess.md` |
| Daily gift | daily, 1 or 2 coins | no | `docs/economy.md` |
| Shop: deals daily, featured set weekly (3 sets in turn) | daily and weekly | no | `shop.ts` `featuredSets` |
| Decorate the room | free | no | `RoomItem*` events |
| Pick tonight, wishlists, lists, calendar, places | occasional utility | some | `FeatureUs` |

**First observations**

- The earn side is capped at about 13 coins a day and the whole room catalogue is 12 pieces, 2 of
  them free (`shop.ts`): 2,175 coins for the other ten, 510 for the six paid inks, 375 for stamps
  and seals. About 3,060 coins, or roughly 8 months at the cap. So the long-term goal is a slow
  cosmetic checklist, and the economy doc says outright that "nothing is worth playing for the
  coins". Coins cannot carry retention, and are not meant to.
- The care level (`CatCare.fill`) is a bar in a per-phone wallet file: 3% per pet, no cap, nothing
  unlocks at any level. It is a number without a meaning.
- The four mini-games are solo and scored 0 to 100 with "no losing" (`GameResult`). To check:
  whether anything changes between the first play and the twentieth.
- The cat's inner life is rich (statechart brain, temperament, upbringing, memory of favourite
  spots, a diary of her day: `Pet/Brain`) but most of it is invisible to the pair. To check: what
  ships outside Labs.
- Not measurable today: a mini-game by id and score from the client beyond `CatPlayed`, Who knows
  who and draw-guess rounds (no client events; the room has them), moments, moods, reactions,
  session length, both partners present at once.

### Stage 2: research notes

"Read" sources were opened; "snippet" ones were seen only in search results. Estimates are marked.

**Pet, cozy and social-farm games**

- **Absence can be the mechanic.** Neko Atsume: put things out, close the app, come back to visitors,
  gifts and mementos; 26 of 86 cats are rare and tied to items; an album to fill
  ([Wikipedia](https://en.wikipedia.org/wiki/Neko_Atsume), read). Reviewers say it goes dull in the end.
- **Finch** ties one daily bar to the day's rhythm: energy from tasks, the bird leaves on an
  adventure of about 6 hours, and comes back in the evening with a story. Sensor Tower estimates
  quoted by Deconstructor of Fun: D1 54%, D7 37% (Duolingo 51% / 35%), about 10M monthly users
  ([DoF](https://www.deconstructoroffun.com/blog/x0hd2ssr80y5n7gv0w967pg7hwd7tl), read; estimates,
  not company figures). Streaks count any open and can be repaired or paused (snippet). Friends
  send one-tap "Good Vibes", no chat (snippet).
- **Punishment backfired.** Tamagotchi pets died of neglect; schools banned the toy and later
  versions softened death and added pause
  ([Mental Floss](https://www.mentalfloss.com/fun/toys/tamagotchi-facts), read).
- **Coziness** is "the fantasy of safety, abundance, and softness"; needy pets, mandatory upkeep,
  nagging notifications and extrinsic rewards work against it ("almost any form of extrinsic reward
  generates a pressing transactional short-term need")
  ([Project Horseshoe 2017](https://www.projecthorseshoe.com/reports/featured/ph17r3.htm), read).
- **Animal Crossing**: a real-time clock, things finish "tomorrow", "always new discoveries"; a long
  absence costs some weeds and a wistful villager, nothing more
  ([Game Developer](https://www.gamedeveloper.com/design/an-inviting-mini-world-how-nintendo-made-i-animal-crossing-i-),
  [Kotaku](https://kotaku.com/what-happens-when-you-abandon-your-animal-crossing-new-1844574997), read).
  Pocket Camp felt "seen" in a week at launch, then piled on timers, notifications and loot boxes
  and read as "stressful"
  ([DoF](https://www.deconstructoroffun.com/blog/2017/11/29/animal-crossing-pocket-camp-can-an-old-dog-learn-new-tricks),
  [Kotaku](https://kotaku.com/animal-crossing-pocket-camp-is-still-a-stressful-mess-1830743891), read).
- **Reciprocity outlasts content.** Hay Day's Derby (weekly co-op tasks) is "one of the reasons
  players have continued playing Hay Day for years"; a social feature "occupies you for way longer
  than a simple content update"
  ([PocketGamer.biz](https://www.pocketgamer.biz/supercell-looking-back-10-years-of-hay-day-part-one/),
  [mobilegamer.biz](https://mobilegamer.biz/what-supercells-hay-day-team-learned-from-ten-years-of-updates/), read).
- **Random rewards and minors.** Paid random items must disclose odds (App Review 3.1.1, read); the
  FTC's 2025 Genshin Impact order bars loot-box sales to under-16s without parental consent
  (snippet). Rare visitors earned by play are outside these rules.
- **Not found:** session length for any title; retention for any pet game but the Finch estimate;
  any data on two-person games.

**Habits, streaks, dyads.** Tags: [A] RCT, meta-analysis or reported A/B test; [B] observational
or company data; [C] practitioner or journalism.

- **Easier streaks retain better.** Duolingo: one lesson keeps the streak, +3.3% D14 retention [A,
  self-reported] ([blog](https://blog.duolingo.com/improving-the-streak)); a second streak freeze
  +0.38% daily actives; a broken streak is "quite demotivating"
  ([blog](https://blog.duolingo.com/how-duolingo-streak-builds-habit)).
- **A broken streak lowers later engagement**, most when people blame themselves, less when it can
  be repaired [A, lab] ([Silverman and Barasch](https://doi.org/10.1093/jcr/ucac029)). Goals with
  "emergency reserves" are pursued longer [A]
  ([Sharif and Shu](https://anderson-review.ucla.edu/emergency-reserves/)). A missed day does not
  hurt habit formation; median 66 days to a habit [B]
  ([Lally et al.](https://www.ucl.ac.uk/news/2009/aug/how-long-does-it-take-form-habit)).
- **Shared streaks.** Duolingo: learners with a Friend Streak are 22% more likely to finish the
  daily lesson, correlational [B] ([blog](https://blog.duolingo.com/product-lessons-friend-streak/)).
  Friends Quests are weekly, cooperative, with an opt-out; no result published. **No study found
  on blame when one person's miss breaks a pair's streak.**
- **Rewards crowd out.** Rewards contingent on doing a thing undermine intrinsic motivation, d
  about -0.3 to -0.4 over 128 experiments [A]
  ([Deci, Koestner and Ryan](https://pubmed.ncbi.nlm.nih.gov/10589297/)). Paying coins per
  affectionate act is the wrong lever.
- **Progress.** Pre-stamped loyalty cards: 34% against 19% finish [A, field]
  ([Nunes and Drèze](https://ideas.repec.org/a/oup/jconrs/v32y2006i4p504-512.html)); effort rises
  near a goal. Peak-end rule holds over 174 effect sizes [A].
- **Notifications.** A template seen recently works worse, so copy rotates: +0.5% DAU, +2% new-user
  retention [A] ([Yancey and Settles](https://research.duolingo.com/papers/yancey.kdd20.pdf)).
  Duolingo kept volume fixed on purpose ("protect the channel") [C]
  ([Mazal](https://www.lennysnewsletter.com/p/how-duolingo-reignited-user-growth)). Widget users
  retained "far better", no size given [B] ([blog](https://blog.duolingo.com/widget-feature)).
- **What helps a couple.** A novel, arousing 7-minute joint task raised relationship quality more
  than a mundane one [A, lab] ([Aron et al.](https://pubmed.ncbi.nlm.nih.gov/10707334/)); sharing
  good news helps when the partner answers with enthusiasm [B]
  ([Gable et al.](https://pubmed.ncbi.nlm.nih.gov/15301629/)); everyday gratitude predicts
  next-day connection [B]; escalating mutual questions build closeness [A, lab, strangers]; a
  ritual helps only when both see it as one [B]
  ([Garcia-Rada et al.](https://journals.uchicago.edu/doi/10.1086/702761)). None tested in an app.
- **Minors and regulators.** State suits against Snap name streaks
  ([Pennsylvania AG](https://www.attorneygeneral.gov/?p=11047)). The EU's DSA minors guidelines
  (2025, non-binding) ask that streaks and push be off by default for minors, per law-firm
  summaries ([Hunton](https://www.hunton.com/privacy-and-information-security-law/european-commission-issues-guidelines-on-the-protection-of-minors));
  not read verbatim. Measured harm from streaks in teens is small and cross-sectional [B]
  ([Belgian survey](https://doi.org/10.1016/j.teler.2023.100087)). App Review: bought currency may
  not expire; no promotional push without opt-in (3.1.1, 4.5.4, read).
- **Benchmarks.** Adjust cross-vertical D1/D7/D30 about 26% / 13% / 7%
  ([Adjust](https://www.adjust.com/blog/what-makes-a-good-retention-rate/)); GameAnalytics 2024
  game medians 22.9% / 4.2% / 0.85% (D28).

**Couples and close-friend widget apps.** No product here publishes a D1/D7/D30 curve. Review
themes are from the reviews store pages show, so illustrative, not counted.

- **SumOne** (Korea): one question a day at a time the couple picks; a pet that grows and hatches
  from answered questions; soft currency for seasonal room decor. DAU about 550k (early 2023) to
  1.3M (Aug 2024) on about 3M MAU, so DAU/MAU near 43% (our arithmetic)
  ([MoneyToday](https://www.unicornfactory.co.kr/article/2024080909415022427)). Complaints: ads
  after each answer, slow currency, weak questions after 200 entries
  ([App Store](https://apps.apple.com/us/app/sumone-for-relationships/id1469506430)).
- **Candle**: "1-minute daily rituals" from a rotating deck (question, quiz, photo prompt, game);
  answers unlock after the partner responds; a shared pet whose mood shows the hours left on the
  streak. 150k couples and DAU/MAU about 50% six months after launch; long-run retention unproven
  ([TechCrunch](https://techcrunch.com/2025/09/24/these-yc-founders-pivoted-5-times-before-building-a-social-app-that-nabbed-300k-users-and-over-1m-arr-in-6-months)).
  Sells "Streak Reignite" at $2.99; rated 18+.
- **Paired, Agapé**: a daily question, the partner's answer hidden until you answer. Paired's
  commissioned study: relationship quality up after three months, more with more use
  ([Open University](https://university.open.ac.uk/research-projects/enduring-love/paired)).
  Complaints: price, answers locked behind the paywall, reworded questions, "I don't see his dad
  participating".
- **Pengu** (co-parented pet, 15M users claimed): reviews complain of pings every couple of hours,
  a pet "on the Verge of death", and "if they aren't doing what your pet needs it puts it all on
  you" ([App Store](https://apps.apple.com/us/app/pengu-raise-virtual-ai-pets/id6462927800),
  [TechCrunch](https://techcrunch.com/2025/09/10/born-maker-of-virtual-pet-pengu-raises-15m-to-launch-a-new-wave-of-social-ai-companions/)).
- **Widgetable**: co-parented pets; care gated by ads, pets that run away, guilt letters; "the
  co-parent doesn't even take care of them so that's more work for me"
  ([reviews](https://justuseapp.com/en/app/1641107226/widgetable-lock-screen-widget/reviews)).
- **NoteIt**: a drawing on the partner's widget, a gallery that grows, streaks added later. Top
  complaint: streak alerts and "streak lost" messages nag; users want streaks switchable off
  ([App Store](https://apps.apple.com/us/app/noteit-drawing-app/id1570369625)).
- **Locket**: "Rollcall", a weekly Sunday photo dump driven by a Live Activity; "well over 25%" of
  actives post one each week. Founder: "the biggest challenge to growth in the long run is
  actually keeping the product fresh and exciting"
  ([TechCrunch](https://techcrunch.com/2025/11/03/lockets-social-app-is-picking-up-steam-with-gen-alpha)).
- **BeReal**: a reveal gate with nothing that accumulates; about 15M daily users in Oct 2022, about
  6M by spring 2023 ([Wikipedia](https://en.wikipedia.org/wiki/BeReal)).
- **Snapstreaks in teens**: of the 63% of 10 to 17 year olds who follow them, 85% feel closer to
  people they care about, 45% feel pressured to use the app daily, 35% anxious, 16% have paid to
  keep one (advocacy-funded poll,
  [Heat Initiative](https://heatinitiative.org/wp-content/uploads/2026/05/SnapchatPolling_HeatInitiative_2026.pdf)).

What the category shares: a 1 to 5 minute daily joint ritual with a reciprocal reveal; a shared
living thing that grows from joint activity; a dyadic streak; the home screen; a private archive
that accumulates. What it has not solved: **the quiet partner** (the active one carries the pet, or
the reveal never opens), content exhaustion, and punitive pressure (dying pets, paid repair).

### Stage 1: audit, server side

- **Every production push is a reaction to the partner** (`apns-payloads.ts`, `apns-lanes.ts`): a
  note, a reaction, streak turn and streak lit, a Pick tonight match, Who knows who "your turn",
  a riddle sent and ended. Nothing is scheduled: no cron (`alchemy.run.ts`), no "cat misses you",
  no recap, no win-back. Moods, lists, gifts and the cat journal reach open sockets only. No quiet
  hours or daily cap on pushes. So a pair where neither opens the app hears nothing from Ourio.
- **The room already has one alarm per pair** (`pair-room-durable-object.ts` `scheduleAlarm`),
  shared by deliveries and the demo bot: a scheduled per-pair event is a third time in it. The
  room's day is the cat's UTC offset (`guess.ts` `roomOffsetOf`).
- **A "drawing of the day" prototype exists** in the dev-only `DemoRoom` (`daily-drawing.ts`): a
  prompt, the partner's drawing held back until you draw yours, an evening reminder from 19:00
  with quiet hours 22:00 to 08:00, once a day. Never shipped to pairs.
- **Coins have no room for a new daily reward.** `coin-pacing.test.ts` requires the second-dearest
  piece (380) to take at least 28 full days: 380 / 13 = 29.2 today, 380 / 14 = 27.1. One more
  capped coin a day fails it. Once-per-thing rewards (`EarnEvent` with no source) are outside the
  daily maximum.
- **Gameplay is invisible to the admin.** `pair_events` has `CatPlayed` with a game id and no
  score; nothing for Who knows who, draw-guess, moments, moods, reactions, lists, a lit streak
  day, session length or both partners present. The room's SQLite has all of it (`cat_entry`,
  `guess_rounds`, `riddles`, `mood`, `reaction`) but no admin route reads a room. The only proxy is
  the economy report's `earn.games` and `earn.other`.
- **Experiment metrics are fixed**: `d7BothActive` and `widgetAdded` (secondary), `notesPerDay` and
  `opensPerDay` (guardrails), all over a pair's first week (`admin-experiment-metrics.ts`). The
  primary is the sentence in the entry's description.
- **Age band is not stored for targeting.** Onboarding keeps the age bucket per account, but
  `ageBand` in flag targeting is never filled, so no feature can be held from 13 to 17 by flag yet.
- **Who knows who is the pattern to copy** for anything daily and two-sided: a round keyed by the
  room day, a pure `decide`, hidden answers on the server, coins once per ref, a push when one
  side finishes (`pair-room/src/guess.ts`).

### Stage 1: audit, the cat, Home and the games

- **What a person can do in the room is small.** Tap the cat (a 2.5 s lean and a heart,
  `CatDirector.petted`), tap the ball or basket, double-tap a spot to send her there, turn and zoom
  the room, open the cat sheet for Feed, Play, Pet, Water, Brush, Treat. Each is seconds.
- **The richer cat play is written and unused.** No app code calls `CatPlay` (wand, ball, yarn, the
  tricks sit, wave, spin and high-five, the reaction to "your partner petted her"),
  `CatTouchRouter`, `CatPetting` (rolling over under a long stroke), `CatNudge` (the "she is
  hungry" nudge), `JointCatChoice` (choosing the cat together, both holding) or `LivePartnerView`
  ("your partner is here"): each is referenced only in its own file and tests. The brain computes
  learned tricks (`CatBrainFrame.tricks`) and nothing plays them. `CatUpbringing.habits` ("Loves
  morning pets", "Brings you toys", "Knows high-five") has no screen.
- **The level is a number.** Per phone, never synced (`Wallet.mirror` skips it), +3% a pet, +10% a
  treat, games add nothing, no cap, nothing unlocks. It is on two widgets and the cat sheet.
- **The four games do not change.** Feed: pour to a target of 25 to 60 g. Water: pour to a line.
  Laser: five pounces, score always 100. Brush: stroke with the fur, score always 100. No
  difficulty, best score, history or partner in any of them; the score is never shown. The 20th
  play is the 1st.
- **Neglect is gentle already.** Needs stop at 0.2; she sulks and ignores the first touch; after 3
  quiet days she is aloof and comes round with care. Nothing owned is lost. The only thing that
  breaks is the streak.
- **The partner is nearly invisible in the room.** When they arrive the cat glances at the door for
  3 s; when they pet her on their phone, nothing shows here. After 3 hours away one line shows for
  6 s ("Leo fed Mochi yesterday at 8:15 PM"). `LifeState.missing` (she misses the partner who
  cares less) is computed and never shown.
- **Mood and Hug send no push.** A hug from the widget sets a "missing you" mood that uploads when
  the sender next opens the app; the partner sees it only by looking.
- **What rotates:** the featured set (3, weekly), 4 daily deals from 9 items, the daily gift (1 or 2
  coins), the Who knows who round. Everything on Home is the same every day except what the cat
  chooses to do.
- **Local notifications:** the 20:00 streak reminder and date reminders. Its title is "Mochi misses
  you tonight" with "before midnight to keep your N-day streak": loss-framed, and on by default.

### Stage 1: audit, notes, Moments, Us, Shop, widgets

- **Nothing suggests what to send.** The note composer's only prompt is "Write a note…"; the draw
  canvas shows a clock. `DailyPrompt` (14 questions, 14 doodle prompts) is in `WidgetBridge` and no
  screen of the shipped composer shows it. A note has no reply and no reaction (reactions are for
  the partner's photos only, `decide.ts`); the partner widget's "Tap to reply" opens the Inbox.
- **Nothing comes back.** Moments is a feed and a six-slot wall. No "on this day", album, timeline
  or recap. Days-together milestones (100, 200, 365…) are calendar rows; nothing marks the day.
- **Dates are single-phone.** Date swipes, matches, plans and ratings, and calendar events, are in
  the phone's `UsStore`; only Pick tonight swipes reach the server
  (`/v1/pick-tonight/swipes`). Paired, "has N left to swipe" counts this phone's data.
- **The games' stake is a line of text.** Who knows who's "Loser plans Friday's date" opens Dates
  and nothing else; the room keeps weekly points (`guess_weeks`) that nothing uses.
- **Two displays promise more coins than the server pays.** Who knows who shows 10 a round and 2 a
  hit (`WhoKnowsModel.roundCoins`, `hitCoins`); the server pays 2 and 1 (`coins.ts`). Collection
  cards show 150 and 100 (`Shop.swift`); the server pays 40 and 25 (`shop.ts`). Bugs to fix
  whatever else is decided.
- **The catalogue is small against the art that exists.** 26 one-time unlocks for about 3,225 coins
  (10 pieces 2,175; 6 inks 450; 10 stamps and seals 600), about 8 months at the cap of 13 a day.
  `Resources/Shop` bundles 55 models; 12 are sold.
- **Written, unreachable:** a shop gift to the partner (`buy(_:asGift:)`, "arrive wrapped and the
  partner unwraps them"), the shop wishlist, ten Labs ideas with no code behind them (`onThisDay`,
  `sealedNote`, `sundayPost`, `advent`, `wrappedDelivery`…), walls and floors (`RoomStyle`).
- **The partner leaving is silent.** `partnerLeft` is stored by `ServerSession` and no view reads
  it; the person lands on "Waiting for your partner".
- **Solo before pairing:** notes queue, Moments and lists work, the shop has no wallet, both games
  say "Pair up to play". The demo partner is dev only.
- **Widgets act late.** Pet, Feed and Hug from a widget run when the app next opens.
