# Gameplay vision

How to make Ourio a place a couple wants to open and stay in. A proposal, second round,
2026-11-22: nothing here is built. Sources and the code read for it are in [Evidence](#evidence).

**The short version.** Ourio is a beautiful room where very little happens. The cat has a rich
inner life that nobody can play with, the games are the same on the twentieth play, and nothing
surprises. The first round of this document answered with a daily ritual; the owner's verdict was
that a daily task is a chore, and that the goal is time people *want* to spend. So this round is
about a world worth lingering in. Eight concepts; the three that are the most fun:

1. **Mischief.** Hide the toy mouse somewhere in the room for the other to find, with the cat
   giving it away. Move one thing and see if they notice. The room becomes a board the two play on.
2. **The secret life of the cat.** Small mysteries told over days in the room itself, where each
   partner finds a different half of every clue.
3. **Cat school and the show.** Teach tricks, each partner their own; string them into routines;
   earn ribbons. The games get depth and the cat gets to be funny.

Each has a first slice of one to three weeks ([section 4](#4-first-slices)). Nothing in them
expires, nags or sells.

**Limit of this document.** No real usage numbers were read. The admin agent API has no service
token yet (Proton Pass has no `cloudflare-agents` item in vault `Ourio`), so every statement about
today's app is from the code. [Section 6](#6-the-numbers-to-read-first) lists the reads that
confirm or overturn it. "Fun" below is a design judgment, argued from what comparable games do;
no study ranks these concepts.

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
reads a room, and nothing measures how long a session lasts. Any gameplay work starts by adding a
few events ([section 4](#4-first-slices)).

## 2. The fantasy and the promise

**Ourio is a tiny world with one cat in it, and the two of you are the only people who know what
goes on there.** The promise: *something has happened since you last looked, and some of it was
your partner's doing.* The cat is a character with a life: habits, moods, a past, friends at the
window, things it gets up to at night. The room is a place you both play in, hide things in, dress
up and build out. What you do there alone is found by the other; what you do together is kept.

**What the two actually do**, when they feel like it and never because a counter says so:

- **Look around.** What is the cat up to? What moved? Who was at the window? Is there a clue?
- **Play a turn.** Hide something, find something, teach a trick, add to a doodle chain.
- **Leave a trace.** Something the other will discover later, and laugh at.
- **Keep what was found.** A souvenir on the shelf, a ribbon on the wall, a page of the story.

The measure of success is not a daily checkmark. It is whether a person opens the app *with
nothing to do* and stays to watch, hunt and tinker.

Three things the rest depends on, because they are what makes a place feel alive:

- **Surprise that is earned, never sold.** What turns up is uncertain; that it costs nothing is not.
- **Nothing expires.** A story waits, a hidden mouse waits, a season comes round again.
- **Alone feeds together.** Almost everything can be done solo, and almost everything done solo
  leaves something for the partner.

## 3. The concepts

Eight concepts, then the three picked. Scores are judgments: fun, linger (does it hold a person in
the room) and pair (does solo play feed the other) from 1 to 5; cost in weeks for one engineer,
content and art named apart.

| # | Concept | Fun | Linger | Pair | Cost of a first slice | Cost to run |
| --- | --- | --- | --- | --- | --- | --- |
| A | **Mischief**: hide and seek, spot what moved, pranks | 5 | 4 | 5 | 1.5 weeks | none: the pair is the content |
| B | **The secret life of the cat**: mysteries in episodes, split clues | 5 | 5 | 5 | 3 weeks | an episode every 2 to 3 weeks |
| C | **Cat school and the show**: tricks, routines, ribbons, game depth | 4 | 4 | 4 | 2 weeks | a show theme a month |
| D | **Cat watch**: a field guide to what the cat does, photographed | 4 | 5 | 3 | 1.5 weeks | none for months: the brain is the content |
| E | **Party box**: doodle telephone, don't wake the cat, caption this | 5 | 3 | 5 | 2 weeks | prompts |
| F | **Out the window**: expeditions, souvenirs, a cabinet | 3 | 3 | 4 | 2 weeks, 40 small pictures | finds each season |
| G | **The neighbours**: visitors with their own stories | 4 | 4 | 3 | 3 weeks, character art | characters |
| H | **The sill garden, then the street**: a slow thing built together | 3 | 4 | 5 | 3 weeks, plant art | little |

**Picked by fun: A, B, C.** D is the cheapest way to make people linger and should follow at once;
E is as funny as A but needs both to answer in the same day more often; F, G and H are the long
game, and B is the door into all three (an episode's ending is how a neighbour arrives, a souvenir
is found, a seed is given).

### A. Mischief

**The fantasy.** The room is where you two mess with each other.

- **Hide and seek.** I hide the toy mouse: behind the armchair, in the box, under the rug, on the
  bookcase. Any spot the cat can reach is a hiding place (`catSpots`, and `placedSpots` adds one
  for every piece the pair stood in the room). I can tuck a line with it ("you looked under the rug
  first, didn't you"). You open the room and hunt by turning and zooming. The cat knows where it
  is and is bad at keeping secrets: ears up and a glance back as the camera gets warm, a sniff at
  the right piece (`perkUp`, `glanceBack`, `sniffObject` exist). Found: the cat pounces, the line
  opens, your time is kept. Your turn to hide.
- **Spot what moved.** I move or turn one piece in a "sneaky" mode. You get three taps to say
  which. It uses the pair's own room and the decorating that exists.
- **Pranks, later.** The cat waits in the box and jumps out when you open the app. A bow or a tiny
  hat left on the cat for you to discover. A doodle on the mirror.

**Why it is fun.** Hiding is authorship: the hider imagines the other looking. Seeking is a small
hunt with a living hint. It is the one concept here that needs no content from us, cannot run out,
and is different in every room. Every piece of furniture bought becomes a hiding place, so
decorating gains a use without anything being sold on Home. A novel, playful thing done together
is what the couple research supports ([Evidence](#evidence)).

**The quiet partner.** A hidden mouse waits. After three days the cat "finds" it and leaves it by
the door with the line; the hider can hide again. Nobody is counted.

**Needs.** *Server:* one small piece of room state (who hid what where, the line, when found),
shaped like a riddle (`riddle.ts`); the push that exists for riddles ("your partner hid something").
*App:* `FeatureMischief`; a `RoomHost` input for "hunting" and the spot, events out for taps on
pieces, so the room stays sealed. *Art:* none for the first slice; the mouse is a model.

**Risks.** The line is user text between two paired people: 40 characters, report and block as for
notes. More furniture means more hiding places; that is a reason to decorate, not an advantage
over anyone. A hunt must be winnable in a minute: the cat's hint gets plainer with time.

### B. The secret life of the cat

**The fantasy.** The cat has a life you only catch the edges of, and you two are the detectives.

- **An episode is a small mystery in five beats.** "The fish plush is gone." "Who leaves a button on
  the sill every morning?" "The radio was on when nobody was home."
- **A beat is something changed in the room.** Paw prints to the window. The yarn basket tipped
  over. A feather on the rug. You find it by looking; finding it is the play.
- **Each partner gets a different half.** My phone shows the feather; yours shows the torn corner
  of a letter. Neither solves it alone, so you have to tell each other, in the app or over dinner.
- **The case board.** Clues pin to the corkboard that Moments already has (`BoardRoomScene`: a desk,
  a cork wall, the cat sitting on the desk). Each of you names a suspect from three; the guesses
  stay hidden until both are in (the rule `guess.ts` already keeps).
- **The ending plays in the room.** The crow comes to the window; the cat trades the plush for a
  shiny button. The button is yours to keep, and the crow now knows where you live (G).
- **Letters.** Between episodes a pen pal writes to the cat; a letter comes in pieces over days and
  hints at the next case.

**Pace.** The next beat appears on the room day after the last one was found by both. Nothing is
lost by waiting: a pair that looks once a week gets the same story more slowly. Finished episodes
can be reread from the board.

**Why it is fun.** Curiosity is a pull that needs no reward attached; the room becomes worth
searching every time it is opened, which is lingering by design. Split clues make the story a
thing the two talk about. Animal Crossing's designers call the core of it "always new discoveries";
Neko Atsume and Finch both make what happened while you were away the reason to come back.

**Needs.** *Content:* an episode is five beats, ten clue halves, three suspects, an ending and a
souvenir; a written format so they can be produced steadily (one every two to three weeks; six
make a season with a thread through it). *Server:* the episode's state in the room (beat, who
found what, guesses), beats served by id from a catalogue like the question deck. *App:*
`FeatureStory`; clues as room inputs (a prop at a spot, a flat mark on the floor or wall); the
board's case section; ending as existing cat steps (`watchWindow`, `chatter`, `bringToy`,
`dashToDoor`) plus one illustrated card. *Art:* props come from the 55 bundled models (box, chest,
radio, fish plush, yarn basket, mirror); marks and letter scraps are flat pictures.

**Risks.** *Content is a treadmill.* If episodes stop, the world goes quiet again; the format must
be cheap enough to keep up, and D and A must carry the weeks between. *Too hard or too easy:* three
suspects and a cat that leads you to an unfound clue after a while. *One partner far ahead:* the
story moves at the pace of the slower one; the faster one has A, C and D meanwhile.

### C. Cat school and the show

**The fantasy.** You two are raising a small, proud, unreliable performer.

- **Tricks.** Sit, wave, spin and high-five are written and unused (`CatPlay`); clips exist for
  roll over, jump up, beg, fetch and boop (`CatAction`: `rollOver`, `jumpUp`, `reachUp`, `carry`,
  `headbutt`). Each is taught in a short game of its own: lead with a treat along a path, tap in
  time, hold still.
- **Stars, and comedy.** A trick has one to three stars. At one star the cat does it sometimes; the
  rest of the time the cat flops, washes a paw or walks off. How it fails follows the personality
  the brain already has: a lazy cat needs bribing, a bold one adds a pounce.
- **Each partner is a teacher.** The cat learns wave from you and spin from Leo, and answers only
  its teacher until the third star. So a full routine needs both.
- **Routines.** String three to five tricks, try it, send the take to the other: it replays in their
  room, flubs included.
- **The show.** Each month a theme ("Lazy Sunday", "The circus is in town") and three judges with
  tastes (one loves spins, one only cares that nobody falls over). Enter one routine; get a ribbon
  to hang in the room. The pair's class rises (Kitten, Alley, Parlour, Grand) and never falls.
  There is no other couple anywhere in it.
- **Depth for the old games.** Laser gets courses that run through the pair's own furniture (through
  the tunnel, over the armchair) and best times; feed gets recipes; each keeps a best and shows
  the partner's.

**Why it is fun.** Mastery with a visible curve is what the four games lack; a creature that
half-obeys is funnier than one that obeys. Ribbons and classes give months of progress that money
cannot shorten. It replaces `Lv.` with something that means something.

**Needs.** *App:* wire `CatPlay` into `CatDirector`; a teaching game per trick; routine record and
replay as a list of steps, not video. *Server:* stars per trick and teacher, routines, ribbons in
the room. *Art:* ribbons; judges as three small portraits.

**Risks.** Teaching games must not be a grind: a star is five good minutes, not fifty repeats.
"Rank" must stay a class the pair grows into, never a place in a list.

### The other five, briefly

- **D. Cat watch.** The brain names about fifty things the cat does (`CatBrainStates`: `zoomies`,
  `chaseTail`, `knockOff`, `sitInCardigan`, `chatter`, `bask`, `sulk`, `waitByDoor`). A camera
  button and a field guide: catch each one on film. Some happen only at dusk, in a sunbeam, when
  both of you are in, when a new piece arrives, when dinner is late. Photos go to a shared album;
  the partner captions them. It rewards exactly the thing the owner wants people to do: watch the
  room. *First slice:* shutter, 24 entries, the album.
- **E. Party box.** *Doodle telephone:* I draw, you caption it, I draw your caption, you caption
  that; the strip opens at the end. *Don't wake the cat:* take turns stacking things on the
  sleeping cat. *Caption this:* one photo of the cat, two captions, the cat picks. *First slice:*
  doodle telephone on the canvas and riddle plumbing that exist.
- **F. Out the window.** The cat goes out at night and comes back with something. The two pack the
  satchel, one thing each, and the pairing decides where the cat goes (the 15 window views are the
  places). Souvenirs fill a cabinet; a postcard comes back. *First slice:* satchel, three places,
  40 finds as small pictures.
- **G. The neighbours.** A crow who trades, a kitten at the window, a snail who brings the post.
  What stands in the room draws them; each has a few scenes and leaves things. If one is at the
  window now, you can call your partner in. *First slice:* the crow, arriving through an episode.
- **H. The sill garden, then the street.** Three pots on the sill; seeds grow over days; your flower
  next to mine makes a hybrid neither had. Later the street the bedroom window already paints
  (`TownPicture`: seeded houses whose windows light at dusk) fills in: a bakery opens after your
  twentieth dinner, a bookshop after the first season. *First slice:* three pots, six seeds.

### What stays from the first round

Groundwork, cheap, and the kind rules in practice:

- **A hug that arrives.** Today a hug uploads when the sender next opens the app and sends no push.
- **The partner shown in the room.** The cat's reaction when the partner pets (`partnerPetted`),
  "your partner is here" (`LivePartnerView`): both written, both unused.
- **A kinder streak.** A count of days you both showed up that never falls, rest days in the week,
  no "whose turn", the 20:00 reminder reworded and off for 13 to 17. The best-evidenced change in
  the first round ([Evidence](#evidence)); it is not gameplay, and it removes the one thing in
  Ourio that punishes.

Dropped: the daily envelope. Who knows who stays where it is.

### The concepts against the hard cases

| Case | What happens |
| --- | --- |
| One partner goes quiet | A hidden mouse and a story beat wait. After three days the cat turns the mouse up. The active partner still has tricks to teach, the field guide and the room to watch. Nobody is named as late. |
| Uneven pair | Solo play is whole: teaching, watching, hunting what the cat left. It all lands in shared state the other finds later. |
| A partner leaves | Say so (`partnerLeft` is stored and never shown). The cat, tricks, ribbons, souvenirs and the story so far stay; split clues fall back to whole ones. |
| 13 to 17 | No timers, no expiry, no loss copy. No random item is ever sold. Text the pair writes (a hidden line, a caption) is short and covered by report and block. No ranking against anyone. |
| Economy | Nothing here pays a daily coin; the pacing test has no room for one (380 / 14 = 27.1 days against a floor of 28). Rewards are souvenirs, ribbons and story. Later sinks: cat bows and hats, show props, seeds, all in the Shop and all cosmetic. |
| Design system | Home gains at most one control (the camera, in D). State is the cat's behaviour and one line in the scene's label glass. Each new surface is one `BilletSheet` with one `PrimaryButton`. Lines about the cat are `CatPhrase`s. The room stays sealed: inputs through `RoomHost(input:)`, taps out through `RoomEvent`. |
| "Home is not a shop" | Nothing sells on Home. |
| App Review 2.5.19 | Every variant ships complete; the server only picks among them. |

## 4. First slices

Three slices, each behind its own remote flag (`off`, `on`; default `off`; `draft` until the owner
starts it), in this order. Each can ship alone.

**Before any of them: a way to see time.** Nothing today measures a session. Add `SessionEnded`
with a closed detail (`under-1m`, `1-3m`, `3-10m`, `over-10m`), listed in `ClientEventName`,
`analytics.md` and `privacy.md`. Without it the goal of this document cannot be judged. Fix the
two coin-display bugs in the same change.

| | 1. Hide and seek (`mischief`) | 2. First tricks (`cat-school`) | 3. Episode one (`story`) |
| --- | --- | --- | --- |
| Time | 1.5 weeks | 2 weeks | 3 weeks |
| In | hide the mouse at any cat spot with a line; hunt with the cat's hint; time kept; turns | four tricks from `CatPlay`, a teaching game each, stars shared by the pair, a routine of three replayed to the partner | "The fish plush is gone": five beats, split clues, the case on the board, three suspects, an ending card, one souvenir |
| Out | spot what moved, pranks | the show, ribbons, game courses | letters, neighbours, a second episode |
| New events | `MouseHidden`, `MouseFound` | `TrickTaught` (trick id), `RoutineSent`; `TrickDone` exists | `ClueFound` (beat id), `CaseSolved` |
| Works if | in pairs that hid once, a median of 3 or more hides a week in weeks 2 to 4 | half of the pairs that taught one trick reach a second star within two weeks | 60% of pairs that found beat one reach the ending |
| Kill if | under 1 hide a week in weeks 2 to 4, or under half of hidden mice found within three days | under 20% teach a second trick | under 30% reach the ending, or median days per beat over 4 |

The thresholds are starting points set by judgment, to be moved once a baseline exists. For all
three the shared question is time: the share of sessions of three minutes or more, `on` against
`off`, and `opensPerDay` and `notesPerDay` as guardrails. With few pairs, read the within-arm
numbers above and talk to couples; do not call a winner under 100 pairs an arm (`experiments.md`).

Why this order: the first needs no content and tells us in two weeks whether the pair will play
*with each other* in the room. The second reuses written code and gives solo play. The third is
the most captivating and the only one with a content pipeline; it should start being written while
the first two are built.

## 5. What not to build

- **A daily task for two.** The owner's verdict on the first round, and right: a thing that must be
  done is not a thing people linger in.
- **Anything that punishes absence.** A cat that sickens or runs away, a story beat that expires, a
  streak that costs coins to repair, "last chance" copy.
- **Sold surprise.** No gacha, mystery box or paid find, and no rare item behind a pack.
- **Coins for affection or for showing up.** The pacing test has no room and it cheapens the act.
- **Comparison between couples.** Classes and ribbons are the pair's own; no lists, no visits.
- **Scheduled nagging.** No "Mochi is hungry" push (`CatNudge` stays unscheduled). A push is
  something the partner did.
- **Home as a store.** No prices or offers in the scene.
- **A chat, more tools in Us, a second currency, energy, skip-timers.**
- **A live two-player action game first.** Turn-based play gives the laugh without both being in the
  app at once.

## 6. The numbers to read first

Run when the agent token exists (`scripts/admin-read.sh` now accepts every route below). Each read
names the decision it moves.

| Read | Route | It decides |
| --- | --- | --- |
| How many pairs, and how fast they form | `overview?days=30` (`totals.pairs`, `stats.newPairs`) | whether an experiment can ever reach 100 pairs an arm, or the slice is judged inside one arm |
| Where pairs are lost before day 2 | `overview` `funnel` (signed in → paired → first note → second day), `onboarding` | if most loss is before pairing, solo play (C, D) goes first and A waits |
| D1, D3, D7, D14, D30 both-active and either-active | `retention` | "either" far above "both" means one partner carries the pair, so solo play that feeds the other (C, D) matters most; both low together means the first week has too little to do |
| What active pairs touch | `features` | if `CatPetted` is near universal and `ShopOpened` is not, Home is where play belongs (as assumed); `DecoratingOpened` shows how many pairs have a room worth hiding things in (A) |
| Is the streak looked at | `trends?event=StreakOpened&metric=pairs&interval=week&range=90&split=none` | priority of the kinder streak |
| Do widgets carry the app | `funnel?steps=PairClaimed,WidgetAdded,NoteOpened&window=7d&unit=pair&range=90` | whether a hunt or a clue should also show on the widget |
| Cap hit rates, median balance against prices, hoarding share | `economy?range=30&hold=14` | a `games` cap hit near 0 means the four games are barely played, so C must replace them, not extend them; `earn.other` shows how many play Who knows who (the base rate for any two-sided game, A and E); the median balance against prices says whether cat hats and show props can be sinks |
| Notes per pair per day | `overview` (`notesPerPairPerDay`) | the guardrail's baseline |

The room-only facts (rounds finished by both, riddles solved, moods) have no route. Until the new
events land, `earn.other` and `earn.games` in the economy report are the only proxy.

## 7. Experiment plan

One or two at a time; pairs are few (`experiments.md`).

| Order | Key | Kind | Variants | Primary metric | Decide when |
| --- | --- | --- | --- | --- | --- |
| 0 | none | | `SessionEnded`, the two coin bugs, the token, a two-week baseline | | before anything starts |
| 1 | `mischief` | experiment | `off`, `on` | share of sessions of 3 minutes or more; inside `on`, hides a week | 100 `on` pairs at day 28, or 6 weeks |
| 2 | `cat-school` | experiment | `off`, `on` | the same; inside `on`, pairs reaching a second star | starts when 1 is decided |
| 3 | `story` | experiment | `off`, `on` | both active on day 14; inside `on`, pairs reaching the ending | after 2; needs episode two written |
| 4 | `streak-style` | experiment | `classic`, `gentle` | both active on day 14 | any gap in the queue |

Rules that hold for all: an entry in `registry` and in Swift before any pair sees it; every variant
complete and described in the review notes; new pairs only, so no pair has its app change under
it; one primary metric written in the description; no stopping early on a good day.

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
