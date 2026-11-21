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
