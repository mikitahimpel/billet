# Gameplay vision

How to make Ourio a place a couple wants to be in every day. A proposal, 2026-11-22: nothing here is
built. Sources and the code read for it are in [Evidence](#evidence).

**The short version.** Ourio has many features and no shared daily ritual. Each partner tends the
cat alone, the other is nearly invisible in the room, nothing two people made accumulates anywhere
but the coin balance, and the one loop with real pull (a hidden answer that opens when both have
played) sits three taps deep in the Us tab. Three changes would alter how the app feels:

1. **Today's envelope**: one small thing a day that both do and that opens only when both have,
   brought by the cat, on Home.
2. **The room remembers you two**: what the partner did is acted out in the room, and a hug arrives.
3. **A kinder streak**: a count that never resets, a week with rest days, no blame.

The first slice is 1 in its smallest form plus the hug from 2, behind a remote flag
([section 4](#4-first-slice-two-weeks)).

**Limit of this document.** No real usage numbers were read. The admin agent API has no service
token yet (Proton Pass has no `cloudflare-agents` item in vault `Ourio`), so every statement about
today's app is from the code. [Section 6](#6-the-numbers-to-read-first) lists the reads that
confirm or overturn it, and which decision each one moves.

## 1. The app today, as loops

### What exists

| Loop | Rhythm | Needs both partners | Where |
| --- | --- | --- | --- |
| Care for the cat: pet, feed, water, laser, brush, treat | several times a day (needs fall over 6 to 14 hours, `LifeConfig`) | no | Home |
| Note, drawing or photo to the partner's widget | free | one sends, one receives | "+", widgets |
| Love streak | daily, lit when both acted | yes | Us, widgets |
| Who knows who | daily, 5 questions, answers hidden until both finish | yes | Us > Games |
| Draw and guess | free, one open riddle each | yes | Us > Games |
| Pick tonight | free, a match when both swipe | yes | Us > Lists > To watch |
| Daily gift, daily deals, weekly featured set | daily, weekly | no | Shop |
| Decorate | free | no | Home |
| Dates, wishlists, lists, calendar, places | occasional utility | some | Us |

### Where it is thin

**Daily.**

- **Home is the same every day.** A person can tap the cat (a 2.5 s lean and a heart), tap the ball,
  send the cat to a spot, and open the care sheet. Each is seconds. Nothing on Home says "today".
- **The four games never change.** Feed and water are "pour to a mark"; laser and brush always
  score 100 (`Laser.swift`, `Brush.swift`). No difficulty, best result, history or partner. The
  score is never shown. The twentieth play is the first.
- **Nothing suggests what to send.** The composer's only prompt is "Write a note…". A note has no
  reply and no reaction (reactions are for the partner's photos only). The partner widget's "Tap to
  reply" opens the Inbox.
- **The partner is nearly invisible.** When they come in, the cat glances at the door for 3 s
  (`CatDirector.partnerArrived`). When they pet the cat on their phone, nothing shows on this one.
  After three hours away, one line shows for 6 s ("Leo fed Mochi yesterday at 8:15 PM").
- **A hug does not arrive.** The widget's Hug sets a "missing you" mood that uploads when the sender
  next opens the app; no push is sent for moods at all.
- **The app never speaks first.** Every production push is a reaction to the partner (a note, a
  reaction, the streak, a match, a game turn: `apns-payloads.ts`). Nothing is scheduled. A pair
  where neither opens the app hears nothing.

**Weekly.**

- The only weekly thing is the shop's featured set, three sets in turn. Who knows who's weekly
  stake, "Loser plans Friday's date", is a line of text; the room keeps weekly points
  (`guess_weeks`) that nothing uses.
- No recap, no "our week", nothing that closes a week or opens the next.

**Long term.**

- **The level means nothing.** `Lv.` is kept per phone, never synced (`Wallet.mirror` skips it),
  rises 3% a pet with no cap, and unlocks nothing.
- **Progress is a shopping list.** 26 one-time unlocks for about 3,225 coins (10 room pieces, 6
  inks, 10 stamps and seals), about 8 months at the cap of 13 coins a day. `economy.md` says
  "nothing is worth playing for the coins", and that is by design. So coins cannot be the reason
  to come back, and nothing else accumulates.
- **Nothing comes back.** Moments is a feed and a six-slot wall: no "on this day", no album, no
  recap. Days-together milestones (100, 365…) are calendar rows; nothing marks the day.
- **Who knows who runs out.** 150 questions at 5 a day is 30 days, then the deck repeats.
- **The only thing a pair can lose is the streak**, and its reminder is framed as a loss: "Mochi
  misses you tonight… before midnight to keep your N-day streak", on by default.

**Written and unused.** The largest surprise of the audit: much of the play that would fill these
gaps exists in `packages/ios/pet` with tests and no caller in the app.

| Code | What it does | State |
| --- | --- | --- |
| `CatPlay` | toys (wand, ball, yarn), tricks (sit, wave, spin, high-five), a reaction when the partner pets or treats the cat | no caller |
| `CatPetting`, `CatTouchRouter` | stroke zones, rolling over under a long stroke | no caller |
| `CatUpbringing.habits`, `CatBrainFrame.tricks` | "Loves morning pets", "Brings you toys", "Knows high-five"; learned tricks | computed, never shown or played |
| `LifeState.missing` | the cat misses the partner who gives less care | computed, never shown |
| `JointCatChoice` | choosing the cat together, both holding a ring | no caller |
| `CatNudge` | a "hungry" nudge, twice a day at most, quiet hours | never scheduled |
| `LivePartnerView` | "your partner is here" | no caller |
| `DailyPrompt` | 14 questions and 14 doodle prompts | not shown in the shipped composer |
| `daily-drawing.ts` (dev `DemoRoom`) | a drawing of the day, the partner's held back until you draw | dev stage only |
| `buy(_:asGift:)` | a shop piece that arrives wrapped for the partner | no screen |
| `Resources/Shop` | 55 bundled models | 12 are sold |

**Two bugs found on the way** (fix whatever else is decided; each shows more coins than the server
pays):

- Who knows who shows 10 a round and 2 a hit (`WhoKnowsModel.roundCoins`, `hitCoins`); the server
  pays 2 and 1 (`coins.ts`).
- Collection cards show 150 and 100 (`FeatureShop/Shop.swift`); the server pays 40 and 25
  (`shop.ts`).

**What cannot be measured today.** `pair_events` has no event for a Who knows who or draw-guess
round, a moment, a mood, a reaction, a lit streak day, session length or both partners present.
`CatPlayed` carries a game id and no score. The room's SQLite holds all of it and no admin route
reads a room. Any gameplay work starts by adding a few events ([section 4](#4-first-slice-two-weeks)).

## 2. The fantasy and the promise

**Ourio is a small home that belongs to two people and a cat, and the cat carries things between
them.** The promise: *when I open Ourio, something of you is here.* Not a feed and not a pet to
keep alive. A room where the other person has been, shown by the one who lives in it. The cat is
the messenger and the witness: the cat brings what the partner left, remembers what the two did,
and grows up shaped by both.

**What the two do every day** (one to three minutes each, in no fixed order):

1. **Open today's envelope.** One small thing the cat holds for both: five questions about one of
   you, a doodle on a prompt, a photo of something. Do your half. It opens when the other has done
   theirs.
2. **Find what the other left.** The cat shows it: the note on the wall, the spot they sent the cat
   to, the hug being carried over.
3. **Leave something.** A pet, a hug, a note. Seconds.

Everything else (the shop, decorating, lists, dates) is the home around this, used when wanted.

Why this and not "more game": the products that hold couples daily share a 1 to 5 minute joint
ritual with a reciprocal reveal (Candle and SumOne both sit near 43 to 50% DAU/MAU), and the
relationship research points the same way: an answerable bid, a novel thing done together,
escalating mutual questions ([Evidence](#evidence)). The products that people leave do so over a
partner who went quiet, repeated content and punishment. Ourio already has the parts; they are not
arranged into a day.

## 3. The ideas

Twenty-one candidates were scored; seven survive. Impact and cost are judgments (impact 1 to 5 on
"both partners still here in week 4"; cost in weeks for one engineer with the existing code);
evidence is how well the mechanism is supported outside Ourio.

| # | Idea | Impact | Cost | Evidence | Measurable now | Main risk |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Today's envelope | 5 | 2 to 3 (v1), 6 for all formats | strong as a pattern, causal effect unproven | after 3 new events | the quiet partner |
| 2 | The room remembers you two | 4 | 2 | moderate | hug yes; the rest by proxy | notification volume |
| 3 | A kinder streak | 3 | 1 to 2 | strong (A/B, lab) | yes | a short-term dip in opens |
| 4 | Our cat's book | 4 (months 2+) | 5 to 6, plus art | moderate | after 2 events | content cost, chore feel |
| 5 | The Sunday letter | 3 | 3 | moderate | yes | a scheduled push |
| 6 | Seasons in the room | 2 to 3 | 2 a season, art exists | moderate | yes (shop events) | scarcity pressure |
| 7 | Games for two hands | 3 | 6+ | lab only | after 1 event | cost, realtime |

Cut, with the reason: paid or wagered streak repair (banned by principle), a pet that can die or
run away (the same), a league or board between couples (comparison between relationships), a
friends layer or visits to other pairs' rooms (changes what the product is), gacha mementos for
coins (random paid rewards, minors), an energy or timer system (chore), chat (already owned by
every messenger), an AI that talks as the cat (cost, trust, minors), location sharing (privacy
promise), a daily quests list (a to-do list is not a home), a second pet (splits the bond), more Us
utilities (the tab is already the widest), a level-up coin shower (the pacing test has no room), a
"nudge your partner" button (nagging by proxy).

### 1. Today's envelope

**The loop.** Each room day the cat holds one envelope for the pair. Each partner does their half
in about a minute. When both have, it opens for both at once, with the cat watching. What opened is
kept in the book (idea 4). Tomorrow there is another, of another kind.

- **Formats, rotated by the room so both phones agree:** *Know me* (today's Who knows who round, as
  built); *Draw it* (a prompt, each draws, both drawings shown side by side: the dev
  `daily-drawing.ts` rules); *Show me* (a photo prompt: "your view right now"); *This or that* (three
  quick picks each, see where you match); later *Sealed* (a note that opens on a date the pair
  picks).
- **Where it is.** On Home, in the scene, not in a tab: the cat sits with the envelope, as the cat
  already carries a note to the wall (`CarryNote`). One line in the scene's label glass says the
  state: "Today: draw a cloud that looks like someone" / "Your half is in. Waiting for Leo" /
  "Open it together". No new header control. Tapping opens one `BilletSheet`, one primary action.
- **The quiet partner.** An envelope does not die at midnight. It waits two more days ("Yesterday's
  is still here"), then goes into the book half-filled, with the active partner's half kept. The
  active partner always gets the cat's reaction and their own page. Nobody is shown as the one who
  did not answer; the only push is the existing "your partner did their half" one, once.
- **Solo, before pairing.** The same envelope with the cat as the other half (a paw print for an
  answer), so the first day has a ritual, and pairing upgrades it.

**Why it grips.** A reciprocal reveal turns "open the app" into "see what they said". It is a bid
the partner can visibly answer, a new small thing done together each day, and questions that deepen
over time: the three daily behaviours the relationship literature supports. Rotation answers the
category's main complaint (repeated questions) and Locket's founder's ("keeping the product fresh").
The archive answers BeReal's fate: a reveal with nothing that accumulates did not hold.

**Needs.**

- *Server:* a `today` descriptor in the room (day, format, each member's state), following
  `guess.ts`: a round keyed by the room day, a pure `decide`, the other half hidden by the server
  until both are in. Know me reuses `GuessRoom`; Draw it ports `daily-drawing.ts` into `PairRoom`.
  One push kind reused ("your partner did their half").
- *App:* one `FeatureToday` module with a `Machine` (`waiting`, `mine(format)`, `theirs`, `ready`,
  `opened`); a `RoomHost` input for "the cat holds the envelope" and a `RoomEvent` for the tap, so
  the room stays sealed; one sheet per format, mostly existing screens (`WhoKnowsScreen`, the draw
  canvas).
- *Content:* 150 more Know me questions and 60 prompts per other format before the second month;
  the deck is the running cost of this idea.
- *Art:* the envelope prop and one cat pose.

**Measure.** New events `TodayOpened`, `TodayDone` and server-recorded `TodayRevealed`, each with
the format id as detail. Funnel `PairClaimed → TodayDone → TodayRevealed` per pair, split by the
`today` experiment. Primary: both partners active on day 7 (`d7BothActive`). Guardrails:
`notesPerDay`, `opensPerDay`.

**Risks.**

- *Obligation.* A daily thing for two can become a duty one partner polices. Hence no expiry at
  midnight, no blame, and it does not gate the streak: any act still lights the day.
- *Coins.* Know me already pays up to 7 a day (2 a round, 1 a hit) outside the daily maximum that
  `coin-pacing.test.ts` checks. If most pairs play daily, a full day is 20 coins, not 13, and the
  second-dearest piece takes 19 days, not 29. Before rollout: put the ritual's coins under the
  `games` cap, or pay per week. The ritual's own reward is the reveal and the page, not coins:
  rewards contingent on an act undermine the wish to do it (d about -0.3 to -0.4 over 128
  experiments), and here the act is affection.
- *Minors.* Prompts stay in the existing safe register (no spicy deck). A photo prompt is user
  content between two paired people, already covered by report and block.

### 2. The room remembers you two

**The loop.** I do something small; the room shows it to you when you come, through the cat; you
answer in one tap; I see that next time. Home answers the question every return visit asks: what
happened here since I left?

- **A hug that arrives.** Hug (widget, control, cat sheet) sends at once, as a push in the
  partner's name with the cat carrying a heart; opening it lands on Home, where the cat brings it
  over, and "Hug back" is one tap. Today it uploads when the sender next opens the app and never
  pushes.
- **Homecoming.** After time away, instead of one line for 6 s: the cat comes to the front, and what
  waits is shown in order (the hug, the note carried to the wall, "Leo played laser at 8", what the
  cat did alone from `CatDiary`). Ten seconds, skippable by touching anything.
- **Live traces.** While both are in the app: the "partner petted" reaction and "your partner is
  here" (`CatPlay.partnerPetted`, `LivePartnerView`, both written). Pet together and the cat rolls
  over (`CatPetting`).
- **Missing the one who is away.** `LifeState.missing` shown as behaviour (sitting by the door),
  told only to the partner who is present, never as a reproach to the absent one.

**Why it grips.** A partner-originated signal is the trigger people do not mute; the hug is a bid
that takes one tap to send and one to answer (Finch's one-tap "Good Vibes", Widgetable's "Miss U").
Absence becomes something to come back to, the mechanism behind Neko Atsume and Finch's evening
return. It makes the 3D room a social place instead of a diorama, which almost no competitor has
(one other 3D room among the 56 apps in [aso-research.md](aso-research.md)).

**Needs.** *Server:* one push kind (`hug`, alert lane, collapsed per sender per hour, at most 6 a
day per sender, none in the receiver's 22:00 to 08:00); moods already reach the room. *App:* wire
the unused `Pet` code into `CatDirector` through `RoomControlling`; a homecoming sequence in the
room fed by the journal the app already fetches. *Art:* a heart prop; rolling over uses the brain's
clips or is cut.

**Measure.** `HugSent`, `HugReturned` (new); share of hugs returned within a day; `AppOpened` per
person per day; `NoteOpened` already exists. Feature usage: share of active pairs with a hug in 7
days.

**Risks.** *Volume:* a hug is the app's first push that costs nothing to send, so the cap and quiet
hours are part of the feature, not a later fix. *Uneven pairs:* ten hugs to none returned is a sad
screen; show what was sent as "left for Leo", never a tally of unanswered ones. *Surveillance:*
"Leo was here at 02:14" reads as tracking; homecoming says what was done for the cat and for you,
with soft times ("this morning"), never a log of opens.

### 3. A kinder streak

**The loop.** Unchanged in its core: a day counts when both did something. What changes is what
is shown and what a miss costs.

- **The headline is days you both showed up**, a count that never falls. The current run is second.
- **A week is seven dots** and a full week is five of them. Two rest days a week are built in and
  free; either partner's rest covers both. The 30-day restore becomes unnecessary.
- **No who.** The card says "today is waiting" until both acted, never whose turn it is, except to
  the person themselves ("your half is in").
- **The reminder** becomes an invitation ("Mochi saved today's envelope for you two"), not "before
  midnight to keep your streak". It is a switch that starts **off for 13 to 17** and on for adults.

**Why.** The best-evidenced move in this document. Duolingo's easier streak raised D14 retention
3.3%; an intact streak raises later engagement and a broken one lowers it, most when people blame
themselves and less when it can be repaired; goals with "emergency reserves" are pursued longer; a
missed day does not hurt habit formation. In a pair the one who missed is identifiable, which is
exactly the condition that makes a break worse (inference: no study of paired streaks was found).
NoteIt's top review complaint is streak nagging; state suits against Snap name streaks; the EU's
guidelines on minors ask for streaks and pushes off by default.

**Needs.** *Server:* `LoveStreak` gains `shown` (a total) and a week of marks; `recordStreakDay`
and the reward table keep their tests, with milestone coins moved to showed-up totals. *App:*
`StreakCard`, the streak widgets, `StreakNudge` copy and default. The phone must keep the age
answer it gave in onboarding (to check: today only the under-13 stop is read on the phone).

**Measure.** Experiment `streak-style` (`classic`, `gentle`), new pairs. Primary: both partners
active on day 14 from the retention grid (first-week metrics are too early for a streak). Also
`StreakOpened`, and a new `ReminderSwitched` event (`on` or `off`).

**Risks.** A softer streak may lower daily opens for a few weeks among pairs who were held by fear
of loss; that is the trade being made, and day-14 and day-30 retention decide it, not opens.

### 4. Our cat's book

**The loop.** Things the two do become pages. The book replaces `Lv.` with something shared,
kept by the room, that never goes down and cannot be bought.

- **Bond, not level.** One shared measure fed by what both did (an opened envelope counts most, a
  hug returned, a game, care), shown as chapters ("Kitten days", "Knows your voices"…), not a bar
  to grind. At chapters the cat learns what the brain already models: coming when called,
  high-five, bringing toys (`CatLearnedTrick`, `CatPlay`), and the pair can then ask for it in the
  room.
- **Habits, told.** "Loves morning pets", "Waits for dinner at eight" (`CatUpbringing.habits`,
  `mealHour`, `petHour`): true facts about this pair's cat, appearing as they become true.
- **Finds.** Now and then, after an envelope opened or a few days away, the cat has a small
  object: a button, a feather, a ticket stub. Some depend on what stands in the room (a fish from
  the lantern, a leaf from the monstera) or the season. They sit on a shelf and in the book. About
  60 to start; never sold, never random for coins.
- **Our pages.** Each opened envelope (both drawings, the round's best miss), each milestone day
  (100 days together), each first (first note, first match). "A year ago today" is a page turning
  itself.

**Why it grips.** It gives months of visible progress that money cannot shorten, which the
economy forbids coins to be. It uses endowed progress and the goal gradient without a currency
(34% against 19% completion in the classic field study). Collections of earned, unsold finds are
the Neko Atsume loop and sit outside every loot-box rule. A private archive is the one retention
mechanism in the category that also raises what the pair would lose by leaving, without a penalty.
It also answers the partner who cares less: bond is shared, so one person's care still grows the
cat both of them have.

**Needs.** *Server:* book state in the room (bond total, chapters, finds, pages as references to
notes and rounds, not copies); find rules as a pure function of the room day and the pair's seed,
like the daily deals. *App:* `FeatureBook`, opened from the cat sheet (replacing the level bar) and
from the shelf in the room; tricks wired into the room. *Art:* about 60 small objects (2D, clay
style like the `RowIcon` tiles), chapter illustrations. *Migration:* each phone's `Lv.` converts
once into starting bond, taking the higher of the two.

**Measure.** `BookOpened`, `FindCollected` (new); retention grid at day 30 and 60 split by an
experiment; `TrickDone` already exists.

**Risks.** *Chore:* the moment bond has a daily quota it is a job; no per-day targets and no
decay. *Content:* 60 objects and 12 chapters are the floor; plan a batch each season (idea 6).
*Random finds* must stay unpaid and unpurchasable forever, or the age-rating answer "no loot boxes"
stops being true.

### 5. The Sunday letter

**The loop.** On Sunday evening the cat leaves a letter for both: what you two did this week
(envelopes opened, the drawing both liked, who knew whom better, the cat's favourite spot), one
thing from the book a month or a year ago, and one small choice for the week ahead.

- **The stake becomes real and kind.** The week's Who knows who winner picks from three date ideas
  for the other to plan; it lands in Dates as a plan, with the existing reminders. No loser
  wording.
- **A share card** of the week (the cat and two numbers, no content) for those who want one.

**Why.** A weekly beat gives a quiet week a clean restart (the fresh-start effect) and ends each
week on a high point (the peak-end rule, 174 effect sizes). Locket's weekly "Rollcall" is posted by
over a quarter of its actives. It is the one place where the app speaks first, once a week.

**Needs.** *Server:* a third time in the room's existing alarm (`scheduleAlarm`); weekly aggregates
from tables the room has; one push a week at most, **opt-in**, never to a pair with no activity
that week (a letter about nothing is a guilt trip). Dates must sync first (today swipes and plans
live on one phone), which is its own piece of work. *App:* one sheet.

**Measure.** `LetterOpened` (new); `PickTonightPlanned` and a new `DatePlanned`; week-over-week
return in the retention grid ("either active" on day 7, 14, 30).

**Risks.** The first scheduled push Ourio would send. App Review 4.5.4 and the minors guidance
both point to opt-in; so it is.

### 6. Seasons in the room

**The loop.** Every six to eight weeks the room's world turns: a set of pieces from the 43 unsold
models, a window view and weather (the `window-view` flag lists 15), a handful of finds for the
book, a themed week of envelopes.

**Why.** Content freshness is the long-run problem every source names. It is also the sink the
economy needs before packs are sold: a pair at the cap owns everything in about 8 months, and one
that buys a pack much sooner.

**Needs.** *Art:* almost none new for the first three seasons. *Server:* catalogue rows with
`ShopSale` windows (the D1 schema has them); the shop reads the catalogue route instead of its
hard-coded list. Selling stays in the Shop; the room only shows what the pair owns.

**Measure.** `ShopOpened`, `ShopItemBought`, the economy report's hoarding share and median
balance.

**Risks.** "Leaves on the 30th" is scarcity pressure. Seasonal pieces come back every year and the
shop says so; no countdown on Home; nothing seasonal is pack-only.

### 7. Games for two hands

**The loop.** First, cheaply: each solo game shows the pair, not a rival ("Together you have served
41 dinners. Leo's last pour was 1 g off"), gets a best result and a harder mark as the pair
improves. Then one game that needs both at once: one moves the laser, the other pets to steady the
cat; or a drawing made on one canvas in turns (`LiveRoom` exists).

**Why.** A novel, mildly exciting joint task raised relationship quality more than a mundane one
in the lab; competence needs a curve, and the games have none.

**Needs.** The cheap half: a room-kept best per game and two more difficulty steps each, one week.
The live game: presence, pacing and a scene, six weeks, and the live-strokes tail latency (#326)
is not solved.

**Measure.** `CatPlayed` gains a result detail; games per active pair per week.

**Risks.** Cost against return. Pairs are rarely in the app together; build the turn-based half
first and the live one only if co-presence (measurable after idea 2) is common.

### The ideas against the hard cases

| Case | What happens |
| --- | --- |
| One partner goes quiet for a week | The cat stays well on one person's care. Envelopes wait two days, then keep the active partner's half. The week has rest days; the showed-up count stays. No push names the quiet partner. On return: homecoming, not a list of what was missed. |
| Uneven pair (one plays daily, one weekly) | Bond is shared, so the cat grows for both. Hugs sent are "left for them", not a tally. The Sunday letter talks about "you two". |
| A partner leaves or deletes the account | Say so (`partnerLeft` is stored and never shown). The cat, the room and the book stay with the one who remains, as kept purchases already do; solo envelopes continue; a new pairing continues the book as a new chapter. |
| A breakup | Unpair already exists. The book can be put away (hidden, not deleted) and exported as pictures. |
| 13 to 17 | No loss-framed copy anywhere. Streak reminder and the Sunday push start off. Hug cap and quiet hours for all. No random paid item. Flag targeting by age does not work yet (`ageBand` is never filled), so the age-dependent defaults are decided on the phone. |
| Economy | No idea adds a daily coin. The pacing test has no room (380 / 14 = 27.1 days against a floor of 28). Rewards are the reveal, the page and the cat. Idea 1 needs the Know me coins moved under a cap first. |
| Design system | Home gains no control: state is one line in the scene's label glass and the cat's pose. Each new surface is one `BilletSheet` with one `PrimaryButton`. Lines about the cat are `CatPhrase`s. The room stays sealed: new inputs through `RoomHost(input:)`, taps out through `RoomEvent`. |
| "Home is not a shop" | Nothing here sells on Home. Seasons sell in the Shop only. |
| App Review 2.5.19 | Every variant ships complete; the server only picks among them. |

## 4. First slice: two weeks

**"Today on Home" and a hug that arrives**, behind the remote experiment `today` (`off`, `on`;
default `off`; `draft` until the owner starts it; new pairs only through `pairedSince`).

**In.**

1. The envelope on Home with two formats that need no new game logic on the server: *Know me*
   (today's Who knows who round) on one day, *Draw it* on the next, built on draw-guess as it is:
   each partner draws one of three offered words, each guesses the other's. The room serves which
   day it is.
2. The scene line and the cat holding the envelope; one sheet; the states `mine`, `theirs`,
   `ready`, `opened`.
3. Hug sends at once with a push, the cat brings it, "Hug back" (cap 6 a day, quiet hours).
4. Events: `TodayOpened`, `TodayDone`, `TodayRevealed` (server), `HugSent`, `HugReturned`, each
   added to `ClientEventName`, `analytics.md` and `privacy.md`.
5. The two coin-display bugs, and Know me's coins moved under the `games` cap.

**Out.** New formats, the two-day wait, solo envelopes, the book, any streak change.

**Rough plan.** Days 1 to 3: `today` in the room and its route, the hug push, events. Days 4 to 8:
`FeatureToday`, the sheet, the room input and pose. Days 9 to 10: Simulator walk on SE and Pro Max,
the transition table tests, review notes for both variants.

**Success metric.** Primary: both partners active on day 7 (`d7BothActive`), `on` against `off`.
Because the number of pairs is unknown and probably small (a gap under 13 points needs more than
200 pairs an arm, `experiments.md`), the working measure is inside the `on` arm: **on what share of
pair-days in the first week did both partners finish the envelope**. Target: 35% or more (Candle
reports about 50% DAU/MAU with "active" defined as a finished card; a new feature inside an
existing app should clear about two thirds of that).

**Kill criterion.** After 100 `on` pairs have reached day 7 (or six weeks, whichever is first), any
one of:

- both-finished on fewer than 15% of first-week pair-days;
- `notesPerDay` worse than `off` with the interval excluding zero (the envelope ate the notes);
- partner reports per 100 pairs higher in `on` (the owner reads Reports; agents cannot).

The hug is judged apart: fewer than one hug in five returned within a day means it is noise, not a
bid, and the push goes while the envelope stays.

Killed means the flag's kill switch, then removing the variant in the next release.

## 5. What not to build

- **Anything that punishes absence.** A cat that sickens, runs away or dies; a streak that costs
  coins to repair; "last chance" copy. The category's worst reviews and its legal exposure are
  both here.
- **Coins for affection.** No coin per hug, per envelope, per day in a row. The pacing test has no
  room and the research says it would make the act worth less.
- **Random rewards for coins or money.** No gacha, mystery boxes or paid finds, ever.
- **Comparison between couples.** No leagues, public profiles, visits or "top pairs".
- **More features in Us.** The tab is already the widest; the gap is a day, not another tool.
- **A chat.** The pair has one. Notes are small on purpose.
- **Scheduled pushes from the app, beyond one opt-in letter a week.** No "Mochi is hungry" push
  (`CatNudge` stays unscheduled): Pengu's and Widgetable's reviews show where that leads.
- **Home as a store.** No prices, offers or "new in the shop" in the scene.
- **A second currency, energy, timers that a purchase skips.**
- **A live co-op game first.** It is the most expensive idea with the least evidence of use.

## 6. The numbers to read first

Run when the agent token exists (`scripts/admin-read.sh` now accepts every route below). Each read
names the decision it moves.

| Read | Route | It decides |
| --- | --- | --- |
| How many pairs, and how fast they form | `overview?days=30` (`totals.pairs`, `stats.newPairs`) | whether an experiment can ever reach 100 pairs an arm, or the slice is judged inside one arm |
| Where pairs are lost before day 2 | `overview` `funnel` (signed in → paired → first note → second day), `onboarding` | if most loss is before pairing, the solo envelope moves into the first slice |
| D1, D3, D7, D14, D30 both-active and either-active | `retention` | "either" far above "both" means the quiet partner is the problem (ideas 1, 2, 4 as designed); both low together means the first week is |
| What active pairs touch | `features` | if `CatPetted` is near universal and `ShopOpened` is not, Home is the place for the ritual (as assumed) |
| Is the streak looked at | `trends?event=StreakOpened&metric=pairs&interval=week&range=90&split=none` | priority of idea 3 |
| Do widgets carry the app | `funnel?steps=PairClaimed,WidgetAdded,NoteOpened&window=7d&unit=pair&range=90` | how much of idea 2 should live on the widget |
| Cap hit rates, median balance against prices, hoarding share | `economy?range=30&hold=14` | a `games` cap hit near 0 means games are barely played (idea 7 down); `earn.other` shows how many play Who knows who (idea 1's base rate); a median balance never reaching 45 means the faucet is too slow for seasons |
| Notes per pair per day | `overview` (`notesPerPairPerDay`) | the guardrail's baseline |

The room-only facts (rounds finished by both, riddles solved, moods) have no route. Until the new
events land, `earn.other` and `earn.games` in the economy report are the only proxy.

## 7. Experiment plan

One or two at a time; pairs are few (`experiments.md`).

| Order | Key | Kind | Variants | Primary metric | Decide when |
| --- | --- | --- | --- | --- | --- |
| 0 | none | | events, the two coin bugs, the token, a two-week baseline | | before anything starts |
| 1 | `today` | experiment | `off`, `on` | both active on day 7; inside `on`, both-finished share of pair-days | 100 `on` pairs at day 7, or 6 weeks |
| 2 | `streak-style` | experiment | `classic`, `gentle` | both active on day 14 | 100 pairs an arm at day 14; starts after 1 is decided |
| 3 | `book` | flag, then experiment | `off`, `on` | both active on day 30 | needs 8 weeks; ship to all if 1 held and guardrails are flat |
| 4 | `sunday-letter` | flag | `off`, `on` | either active on day 14 and 30 | rolled out by exposure, watched on the retention grid |

Rules that hold for all: a `flag` or `experiment` entry in `registry` and in Swift before any pair
sees it; every variant complete and described in the review notes; new pairs only, so no pair has
its app change under it; one primary metric written in the description; no stopping early on a
good day; with fewer than 100 pairs an arm, read direction and talk to couples, do not declare a
winner.

## Evidence

Tags: **[A]** RCT, meta-analysis or reported A/B test; **[B]** observational or company data;
**[C]** practitioner, journalism or review text. "Snippet": seen in search results, page not
opened. No product named here publishes a retention curve.

### Couples and close-friend apps

- **Candle**: 1-minute daily rituals from a rotating deck, answers unlock when the partner
  responds, a shared pet tied to the streak; 150k couples, DAU/MAU about 50% six months in, long-run
  retention unproven; sells "Streak Reignite" [B]
  ([TechCrunch](https://techcrunch.com/2025/09/24/these-yc-founders-pivoted-5-times-before-building-a-social-app-that-nabbed-300k-users-and-over-1m-arr-in-6-months)).
- **SumOne**: a question a day, a pet that grows from answers, seasonal decor for soft currency;
  DAU 550k to 1.3M over 2023 to 2024 on about 3M MAU [B]
  ([MoneyToday](https://www.unicornfactory.co.kr/article/2024080909415022427)); complaints: ads,
  slow currency, weak questions after 200 entries [C]
  ([App Store](https://apps.apple.com/us/app/sumone-for-relationships/id1469506430)).
- **Paired, Agapé**: a daily question with a reciprocal reveal; more use, more reported benefit, in
  studies tied to the companies [B]
  ([Open University](https://university.open.ac.uk/research-projects/enduring-love/paired),
  [Rochester](https://www.rochester.edu/newscenter/can-relationship-app-improve-romance-571032/));
  complaints: price, reworded questions, a partner who does not take part [C].
- **Pengu, Widgetable** (co-parented pets): reviews of pings every few hours, a pet "on the Verge
  of death", pets that run away, and "the co-parent doesn't even take care of them so that's more
  work for me" [C]
  ([App Store](https://apps.apple.com/us/app/pengu-raise-virtual-ai-pets/id6462927800),
  [reviews](https://justuseapp.com/en/app/1641107226/widgetable-lock-screen-widget/reviews)).
- **NoteIt**: top complaint is streak alerts and "streak lost" messages [C]
  ([App Store](https://apps.apple.com/us/app/noteit-drawing-app/id1570369625)).
- **Locket**: weekly "Rollcall" posted by "well over 25%" of actives; "the biggest challenge to
  growth in the long run is actually keeping the product fresh and exciting" [B/C]
  ([TechCrunch](https://techcrunch.com/2025/11/03/lockets-social-app-is-picking-up-steam-with-gen-alpha)).
- **BeReal**: about 15M daily users in late 2022, about 6M by spring 2023 [B]
  ([Wikipedia](https://en.wikipedia.org/wiki/BeReal)); that the missing archive was the cause is our
  inference.
- **Ourio's own teardown** of 56 competitors: [aso-research.md](aso-research.md).

### Pet and cozy games

- **Neko Atsume**: absence as the loop; 26 of 86 cats rare and tied to items; an album
  ([Wikipedia](https://en.wikipedia.org/wiki/Neko_Atsume)).
- **Finch**: one bar, an adventure of about 6 hours, an evening return; estimated D1 54%, D7 37%
  (Sensor Tower via
  [Deconstructor of Fun](https://www.deconstructoroffun.com/blog/x0hd2ssr80y5n7gv0w967pg7hwd7tl))
  [B, estimate]; forgiving streaks and one-tap "Good Vibes" (snippets).
- **Tamagotchi**: death by neglect led to distress and school bans; later softened
  ([Mental Floss](https://www.mentalfloss.com/fun/toys/tamagotchi-facts)) [C].
- **Coziness** is "the fantasy of safety, abundance, and softness"; needy pets, nagging and
  extrinsic rewards work against it
  ([Project Horseshoe](https://www.projecthorseshoe.com/reports/featured/ph17r3.htm)) [C].
- **Animal Crossing**: "always new discoveries", a mild cost of absence
  ([Game Developer](https://www.gamedeveloper.com/design/an-inviting-mini-world-how-nintendo-made-i-animal-crossing-i-),
  [Kotaku](https://kotaku.com/what-happens-when-you-abandon-your-animal-crossing-new-1844574997));
  Pocket Camp's timers, notifications and loot boxes read as "stressful"
  ([Kotaku](https://kotaku.com/animal-crossing-pocket-camp-is-still-a-stressful-mess-1830743891)) [C].
- **Hay Day**: a social loop "occupies you for way longer than a simple content update"
  ([mobilegamer.biz](https://mobilegamer.biz/what-supercells-hay-day-team-learned-from-ten-years-of-updates/)) [C].

### Habits, streaks, rewards

- Easier streak: +3.3% D14 retention [A, self-reported]
  ([Duolingo](https://blog.duolingo.com/improving-the-streak)); a broken streak is "quite
  demotivating" ([Duolingo](https://blog.duolingo.com/how-duolingo-streak-builds-habit)).
- A broken streak lowers engagement, less when it can be repaired [A, lab]
  ([Silverman and Barasch](https://doi.org/10.1093/jcr/ucac029)); goals with reserves last longer
  [A] ([Sharif and Shu](https://anderson-review.ucla.edu/emergency-reserves/)); one missed day does
  not harm a forming habit [B]
  ([Lally et al.](https://www.ucl.ac.uk/news/2009/aug/how-long-does-it-take-form-habit)).
- Friend Streak: 22% more likely to finish the daily lesson, correlational [B]
  ([Duolingo](https://blog.duolingo.com/product-lessons-friend-streak/)).
- Contingent rewards undermine intrinsic motivation [A]
  ([Deci, Koestner and Ryan](https://pubmed.ncbi.nlm.nih.gov/10589297/)).
- Endowed progress, 34% against 19% [A, field]
  ([Nunes and Drèze](https://ideas.repec.org/a/oup/jconrs/v32y2006i4p504-512.html)); peak-end rule
  [A] ([meta-analysis](https://ideas.repec.org/a/eee/jobhdp/v170y2022ics0749597822000334.html));
  fresh-start effect [B]
  ([Dai, Milkman and Riis](https://faculty.wharton.upenn.edu/wp-content/uploads/2014/06/Dai_Fresh_Start_2014_Mgmt_Sci.pdf)).
- Notifications: a recently seen template works worse [A]
  ([Yancey and Settles](https://research.duolingo.com/papers/yancey.kdd20.pdf)); volume held down
  on purpose [C] ([Mazal](https://www.lennysnewsletter.com/p/how-duolingo-reignited-user-growth)).
- Benchmarks: D1/D7/D30 about 26% / 13% / 7% across verticals
  ([Adjust](https://www.adjust.com/blog/what-makes-a-good-retention-rate/)) [B].

### Couples research (none tested in an app)

- A novel joint task raises relationship quality [A, lab]
  ([Aron et al.](https://pubmed.ncbi.nlm.nih.gov/10707334/)).
- Good news shared and met with enthusiasm [B]
  ([Gable et al.](https://pubmed.ncbi.nlm.nih.gov/15301629/)); everyday gratitude and next-day
  connection [B] ([Algoe, Gable and Maisel](https://labs.psych.ucsb.edu/gable/shelly/publications/414)).
- Escalating mutual questions build closeness [A, lab, strangers]
  ([Aron et al.](https://ggia.berkeley.edu/practice/36_questions_for_increasing_closeness)).
- A ritual helps only when both see it as one [B]
  ([Garcia-Rada, Sezer and Norton](https://journals.uchicago.edu/doi/10.1086/702761)).

### Minors and rules

- Teens and Snapstreaks: 85% of those who follow them feel closer to people they care about, 45%
  pressured to use the app daily, 16% have paid to keep one (advocacy-funded poll) [B]
  ([Heat Initiative](https://heatinitiative.org/wp-content/uploads/2026/05/SnapchatPolling_HeatInitiative_2026.pdf));
  measured association with problematic use is weak [B]
  ([survey](https://doi.org/10.1016/j.teler.2023.100087)).
- State suits against Snap name streaks ([Pennsylvania AG](https://www.attorneygeneral.gov/?p=11047)).
  EU guidelines on minors (2025, non-binding): streaks and pushes off by default, per a law-firm
  summary, not read verbatim
  ([Hunton](https://www.hunton.com/privacy-and-information-security-law/european-commission-issues-guidelines-on-the-protection-of-minors)).
- App Review: odds for paid random items, bought currency never expires, no promotional push
  without opt-in ([guidelines](https://developer.apple.com/app-store/review/guidelines/) 3.1.1,
  4.5.4).

### Not found

Session length for any product; a retention curve for any couples or pet app; any study of blame
in a paired streak; any evidence on never-resetting counts; any data on two-person games.

### Code read

`packages/ios/pet` (Brain, Life, `CatPlay`, `CatUpbringing`), `packages/ios/features`
(FeatureGames, FeatureUs, FeatureShop, FeatureCanvas, WidgetBridge), `apps/ios/Nooki` (Scene, Room,
UI/Home, Model), `apps/ios/OurioWidgets`, `packages/backend/pair-room` (`guess.ts`, `decide.ts`,
`riddle.ts`), `packages/backend/platform` (`apns-payloads.ts`, `apns-lanes.ts`,
`pair-room-durable-object.ts`, `daily-drawing.ts`, `room-schema.ts`), `packages/backend/admin`,
`packages/backend/flags`, `packages/contracts/domain` (`coins.ts`, `shop.ts`, `streak.ts`,
`metrics.ts`, `coin-pacing.test.ts`), and the docs linked above.
