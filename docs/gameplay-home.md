# Gameplay: the cat and the home

Game mechanics around the cat and the room the two of you keep: caring and watching, upkeep and
small repairs, renovating, arranging, the home while you are away, things that take two. A
proposal, 2026-11-23: nothing here is built. It continues the gameplay vision (PR #1010,
`docs/gameplay-vision.md` on its branch) and does not redo what that started: Mischief
([mischief.md](mischief.md)), the secret life ([secret-life.md](secret-life.md)), Cat school and
`SessionEnded`.

**The short version.** Today the home is a backdrop: a pair can place up to eight bought pieces,
and after that the room never asks for anything, never changes by itself and remembers nothing.
29 mechanics below make it a place that is lived in. The five to build first, picked for fun
against cost:

| # | Mechanic | The fun | First slice | Room code touched |
| --- | --- | --- | --- | --- |
| 1 | **While you were out** | Come home and see what the cat got up to, then watch her show you | 1.5 weeks | no |
| 2 | **Little messes** | The cat leaves a piece askew; one press puts it straight | 2 weeks | no |
| 3 | **The cat's requests** | She wants a nap in the sun; arrange the room so she gets it, and she uses it | 2 weeks | no |
| 4 | **Parcels** | What you buy arrives in a box, a gift arrives wrapped, the cat keeps the box | 1.5 weeks | little |
| 5 | **The home book** | A portrait of the room every month, and the story of how it got this way | 2 weeks | little |

They are one loop, not five features ([section 5](#5-one-loop)): the cat lives in the room every
day (1), her life disturbs it a little (2), she asks for changes (3), new things arrive as events
(4), and the home keeps the record (5). The best mechanic for two people, **Flat-pack for two**,
is sixth only because it costs three weeks.

**The rule that decides everything in this document.** Upkeep is a toy, never a debt. A mess never
grows, a plant never dies, a repair never becomes urgent, and no screen says who did more.
Chore apps show what happens otherwise ([Evidence](#evidence)).

**Limits of this document.**

- No usage numbers were read; there is no admin token. Every statement about today's app is from
  the code and docs. Above all, nobody knows how many pairs decorate at all (`DecoratingOpened`,
  `RoomItemPlaced`), and four of the top five lean on the room being used. Read that first
  ([section 7](#7-numbers-to-read-first)).
- "Fun" is a design judgment. The research found no experiment or controlled study for any
  mechanic here; the strongest sources are designers' own accounts and two observational studies.
- Estimates are for one engineer who knows the app, without art unless art is named.

## 1. What exists

Read from the code on `main` at `8c28ce0e`. "Unused" means written, tested and without a caller.

### The room

| Fact | Where | What it means for play |
| --- | --- | --- |
| Three scenes: living room, bedroom, the corkboard (8 slots) | `RoomScene` | A close-up scene like the board is an existing pattern |
| Decorate is a grid of 5 cm cells on the floor and two walls; floor pieces turn in 45° steps; one-step undo; "Reset room" | `shop.ts`, `DecorPanel.swift` | Rich enough for arranging puzzles as it is |
| At most 8 bought pieces a room, 35% of the floor free, the cat must reach her tree | `DecorLayout.maxPlaced`, phone only | The ceiling on decorating is low; a pair can hit it in a few months |
| The layout is shared: every change goes to the pair's room and the last write per piece wins. Only the current layout is kept (`layout_log` holds the last change ids against repeats, not a history) | `decide.ts`, `room-schema.ts` | Arranging is already a thing two people do to one room. How the room used to look is not recorded anywhere |
| 12 pieces are sold; 55 models are bundled | `shop.ts`, `Resources/Shop` | **43 models are unsold**, about 35 of them already placeable (footprints exist): six armchair colours, plants (cactus, fiddle fig, pothos, succulents), fish tank, record player, radio, mirror, globe, guitar, books, mugs, tea set, clock, box, tunnel, window seat |
| No wallpaper, floor, paint, window view or weather in a release build | `WindowChoice` and weather are Labs only; the old `RoomStyle` (10 paints, 5 papers, 5 floors) is deleted by a migration | Renovation has nothing to stand on yet |
| On the baked shell the walls, floor and sun patches are pictures | [baked-shell.md](baked-shell.md) | A new wall colour is a new bake, not a parameter |
| Nothing in the room has a state: no dirt, wear, broken or toppled thing; no way to put a prop at a spot | `RoomInput`, `RoomControlling` | Mischief's mouse is not drawn and the story's clues are text for this reason. Any mechanic that needs a prop needs Room work first |
| A placed piece cannot be lit or animated | `DecorStage.swift` | A lamp you buy does not switch on |
| The bedroom lamps switch on and off, 18:00 to 06:00, kept per phone | `BedroomLights` | The only interactive fixture, and not shared |
| The camera turns ±43° and zooms; no photo of the room, no share | `CatRoom.yawLimit` | A room portrait is new |
| A piece bought as a wrapped gift for the partner | `ShopModel.buy(_:asGift:)`, `ShopGiftSent` | unused |

### The cat

| Fact | Where | What it means for play |
| --- | --- | --- |
| Four needs (full, rested, loved, playful), floor 0.2, no sickness, no death | `LifeConfig`, [cat-brain.md](cat-brain.md) | Care is already kind; keep it so |
| "Mochi's day": up to eight moments of her day, built from the brain's diary | `CatDiary`, `CatDayStory`, the care sheet | The day log exists, three taps deep, as text |
| Her day is a pure function of the journal, the seed and the room, replayed from 04:00 in about 20 ms | `CatBrainRunner` | "What she did while you were away" can be computed, not stored. Only today and yesterday |
| A homecoming after 3 hours shows one line for 6 seconds | `HomecomingLine` | The one moment the app tells you what happened, and it is gone in 6 seconds |
| Favourite spots: seconds napped at each kind of spot | brain memory | Shown as one word in About; nothing is made of it |
| A piece placed in the last day makes her explore and inspect it | `CatUtility.roomTerm`, `since` | **Appears not to fire in the shipped room**: `NookiSpot.affordances` passes no placing time. Not checked on a device |
| The brain's Mischief group (pushes a small thing, sits on the desk, sits in the cardigan) | `CatBrainStates` | **Appears unreachable in the shipped room**: it needs a small item, something soft or a desk, and the room offers none. Not checked on a device |
| The server's slow temper drift (curious, lazy, cuddly) | [cat-state.md](cat-state.md), `CatTemper` | Decoded by the phone and then, as far as the code shows, never applied |
| A `Watered` journal event and a `PlantWatered` Inbox line "Anya watered the monstera" | `CatEvent`, `activity.ts` | No client sends it. Plant care was started and left |
| Stroke zones, rolling over under a long stroke | `CatPetting`, `CatTouchRouter` | unused |
| Both partners holding a ring at once | `JointCatChoice` | unused; a ready "it takes both hands" primitive |
| The partner's socket is open or not | `ServerMessage.Presence` | The app knows when both are home. It is used for a 3-second glance |
| Cat widget with a Feed or Pet button; needs reach the widget with 6 hours' freshness | `CatNeedsGlance` | A widget can show a pose, never the live room |
| The cat's look is a coat chosen once; nothing for the cat is sold | `CatCoat`, `ShopOffer` | |
| Shared lists with who ticked what; a tick pays 1 coin, 1 a day | `SharedList`, `earn.lists` | A chore list is possible today as a custom list |

### The economy, as it bounds this document

- A full day pays 13 coins. `coin-pacing.test.ts` allows 14 at most and needs the second most
  expensive piece (380) to take 28 days: 380 / 14 = 27.1. **There is no room for any new daily
  coin**, and this document adds none.
- A one-off reward must stay under a quarter of the cheapest piece (45 / 4, so 11 coins at most).
  This document pays no coins at all: every reward is a thing kept, a change in the room or a
  behaviour of the cat.
- What it does add is **sinks**, which [economy.md](economy.md) asks for ("add sinks"). With
  faucets fixed, every new sink competes with the 26 unlocks that already take about 8 months at
  the cap. So renovation is **labour first**: the doing is free, coins only choose a look.

Two things in today's economy sit badly with the kind rules; neither is this document's to change:
the daily gift is a daily coin drip, and economy.md says seasonal items "leave the catalogue",
which is scarcity by deadline. [Mechanic 22](#7-seasons-and-the-long-run) proposes they come back
every year and say so.

## 2. What the references teach

Sources and their weight are in [Evidence](#evidence). Seven lessons, each used below.

1. **Tidying is fun when nothing can go wrong.** Unpacking has "no scores, or fail states or
   negative consequences"; A Little to the Left accepts several right answers because order "can
   be really personal". PowerWash Simulator players report a small rise in mood, most of it in
   the first 15 minutes. The pleasure is the before and after, the sound and the click into place.
2. **The cat is the comedy in a tidy world.** A Little to the Left's cat "brings this comedic
   relief" and tells the player not to take tidiness seriously. Little Kitty, Big City dropped
   survival because nobody wants to watch a kitten struggle, and opened on boxes and things
   knocked off shelves.
3. **A character with its own life is worth checking on.** In Tsuki's Odyssey, "every time you log
   in, you can find your furry companion doing any number of things", and catching an animation
   tied to one piece of furniture is the highlight. Usagi Shima "never demands your time".
4. **Decorating to a brief beats decorating to a score.** Happy Home Paradise gives a loose theme
   and a few required items and never grades; the Happy Home Academy's score is disliked because
   it rewards rules over taste. Townscaper's author: if there is a score you play to the score.
5. **Building holds people for a long time.** 226 million of The Sims 4's 1.2 billion hours in 2021
   were in Build Mode, about one hour in five.
6. **Two players should hold different halves.** It Takes Two gives each player their own
   abilities and makes them talk. Unpacking tells a relationship through whose things must fit
   round whose.
7. **Chore apps hurt when one partner assigns.** "The app turned my wife into my manager."
   Co-parented pets get the same complaint: "the co-parent doesn't even take care of them so
   that's more work for me." Clarity agreed beforehand helps; points and assignment do not.

And from the makers of cozy games, a line to design by: "nothing bad ever happens in Hay Day".

## 3. The kind rules

Hard, for every mechanic below. A mechanic that cannot keep one is dropped, not softened.

| Rule | In this document |
| --- | --- |
| Nothing expires | A mess, a wish, a repair, a parcel, a project step waits for ever. Seasons come round again with everything they had |
| No guilt, no nag | No push for any of it. Nothing gets worse with time: no pile of mess, no wilting, no "Mochi is sad" |
| No scorekeeping between partners | No screen counts who tidied, fixed or watered more. A deed may carry a name where it is a memory ("Mended by Mia"), never in a tally |
| No dark patterns | No timers to skip, no energy, no appointment, no streak, no "last chance" |
| 13 to 17 safe | No free text in any first slice but one gift tag (40 characters, as the mouse's line, under report and block). No loss copy |
| No couple against couple | No room rating, no ranking, no visiting to compare |
| No sold surprises | Nothing random is bought. A parcel holds what was chosen |
| No daily coins | No mechanic pays coins. Sinks only, all cosmetic, all in the Shop |
| Home is not a shop | No price in the room. A mechanic that wants a piece says "in the Shop" at most, and no request of the cat's ever needs a purchase |
| The cat is never hurt, sick or cross with you | Mess is cute. Nothing breaks: [cat-brain.md](cat-brain.md), "Rules that stay" |

**Payments.** Mechanics marked **(coins)** add a sink or a spend. With `payments` off they only
move earned coins. When `payments` is on, every one of them becomes something money can shorten,
so each needs the owner's eye then: the price against the pricing anchor, and no path from the
room to the packs.

## 4. The mechanics

Each has: the fun in a line; **Pair** (solo, pair, or solo feeding the pair); **Cost** (first
slice, and what content it keeps needing); **Coins**; **Risk**. Scores in the table at the end
of the section.

### 1. Cat care and moods

**1. Favourite things.** She has a favourite spot, piece, sunbeam hour and game, and you learn
them by watching; a page fills in as you notice.

- Pair: solo feeding the pair; either partner's noticing fills the shared page.
- Cost: 1 week. The brain already keeps favourite spots; add favourite piece and hour from the
  diary. No content to keep up.
- Coins: none. It makes a bought bed matter (she picks it or pointedly does not).
- Risk: a page of facts is a list, not play; it earns its place only with 3 and 11.

**2. Little wishes.** She wants things that are not needs: the curtain side of the sill, the box
left out, the lamp on at dusk. She shows it by behaviour; granting it gives a new pose or habit.

- Pair: solo feeding the pair.
- Cost: 2 weeks, about a dozen wishes, each a rule over the room plus a clip that exists.
- Coins: none.
- Risk: read as a need and it becomes a nag. A wish is never shown on the needs ring or a widget.

**3. A good brush.** Stroke zones that exist and are unused: she has a spot she loves today,
found by touch, and rolls over under a long stroke.

- Pair: solo; her spot of the day is the same on both phones.
- Cost: 1.5 weeks to wire `CatPetting` and `CatTouchRouter`. Overlaps Cat school's work on
  `CatPlay`: agree the boundary with that agent first.
- Coins: none; `earn.care` is capped at 2 a day already.
- Risk: touch on the room is slow on old phones.

### 2. Upkeep and small repairs

**4. Little messes.** After a wild hour the cat leaves a piece askew: an armchair turned 45°,
the rug slid a cell, a paw print beside it. Press and hold, it slides home with a click and a
haptic, and she looks faintly offended. *(Top 5.)*

- Pair: solo feeding the pair. Either partner straightens it for both.
- Cost: 2 weeks, no art, no Room change: the nudge is a display layout handed to `RoomInput.decor`,
  worked out on both phones from the diary and the seed; the stored layout is untouched.
- Coins: none.
- Risk: a careful decorator may hate it. Three open messes at most, never a wall piece, and a
  setting, "Mochi leaves the furniture alone". Must look unlike Mischief's "spot what moved".

**5. Small fixes, and mended marks.** Now and then something small needs a hand: a picture hangs
crooked, one fairy light is dead, the table wobbles. Each is a 30-second tactile puzzle, and the
mended thing keeps a small gold mark with a name and a date.

- Pair: solo feeding the pair; the mark is the memory.
- Cost: 3 weeks for six fixes and the Room work for a fixture's state. Each new fix is a small
  puzzle, so it is content.
- Coins: none.
- Risk: the first that feels like work spoils it. One or two a week at most, and a fix that is
  ignored is simply a crooked picture.

**6. Plants.** Water the monstera and it grows a leaf over weeks; a cutting goes in a new pot
on the partner's side of the sill. A plant never dies; unwatered, it rests.

- Pair: either waters; cuttings are for the other.
- Cost: 2.5 weeks. The `Watered` event and its Inbox line exist; needs growth stages for one
  plant (art: 4 stages) and a prop state. Five more plant models are bundled.
- Coins: **(coins)** pots and the unsold plants as shop pieces.
- Risk: growth only when watered is an appointment in disguise. Growth follows weeks lived in the
  room; water adds a flourish, not the leaf. This is the cheap first step of the vision's sill
  garden (H).

### 3. Renovation and styles

**7. Room projects.** A project changes the room for good: build the window seat, put up the long
shelf, restore the floorboards. Four to six steps over days, each a minute of sanding, brushing or
fitting, and at the choice steps each partner proposes a finish and you settle it.

- Pair: steps go to whoever opens the room; choices need both (the hidden-until-both rule of
  `guess.ts`).
- Cost: 4 weeks for one project plus its art. Every project is art, so it is the dearest content
  in this document.
- Coins: **(coins)** finishes only. The work is free.
- Risk: Homescapes-style renovation is the genre's grind. One project at a time, no step costs
  anything, the next step opens the next room day and waits.

**8. Paint and paper.** Put up three swatches and live with them for a few days; then paint the
wall with a roller, in strokes, and a half-painted wall stays half-painted until someone comes
back to it.

- Pair: each votes on a swatch; both can paint.
- Cost: 4 weeks or more. The baked shell makes each colour a bake; a live-tinted wall is a
  rendering decision for the owner of the Room files.
- Coins: **(coins)** paint, priced like an ink (60 to 120).
- Risk: the cost. Do not start before the baked shell question is answered.

**9. Reupholster.** Take an armchair you own and re-cover it: six colours of the armchair are
already bundled.

- Pair: solo; the partner finds the room changed (see 14).
- Cost: 1 week, no art.
- Coins: **(coins)** a small sink, priced like a stamp (30 to 45), the first that acts on
  something already owned.
- Risk: thin alone. It is the cheapest test of whether pairs will pay to change, not to add.

**10. Our style.** The room is described, never graded: "bookish, warm, a little chaotic", in the
cat's words, as a card you can keep.

- Pair: solo feeding the pair.
- Cost: 1.5 weeks: tags on pieces and a rule; copy.
- Coins: none; it gives collections a meaning beyond their bonus.
- Risk: any hint of a score and it becomes the Happy Home Academy. No numbers, no "better".

### 4. Arranging and puzzles

**11. The cat's requests.** She wants a nap in the sun, a lookout, a clear runway for zoomies, a
place to hide. Each is a loose brief for the room; meet it and she uses what you made, at once
and from then on. *(Top 5.)*

- Pair: solo feeding the pair; the layout is shared, so one arranges and both get the payoff.
- Cost: 2 weeks: briefs as data (like episodes), a checker over the layout that needs only
  Foundation, six briefs. A new brief is an hour's writing.
- Coins: none. **No brief may need a piece the pair does not own.**
- Risk: only five kinds of piece mean anything to the cat (`CatUse`) and a room holds eight
  pieces, so briefs run out near twenty. Enough to learn whether it works.

**12. Parcels.** What you buy arrives as a box by the door. Open it and the piece comes out in
your hands, ready to place; the box stays, and the cat moves in. A gift for your partner arrives
wrapped, with a tag. *(Top 5.)*

- Pair: solo, and the gift is the pair.
- Cost: 1.5 weeks. `buy(_:asGift:)` and `ShopGiftSent` exist; the box model is bundled and the cat
  already knows what a crate is.
- Coins: **(coins)** the existing spend at the existing price; a gift costs the same.
- Risk: a box between buying and having is friction if it cannot be skipped: one tap opens it.

**13. The shelf.** A close-up of one shelf, like the corkboard: souvenirs, books and small things
arranged any way you like, by either of you, and sometimes the cat has moved one.

- Pair: both arrange the same shelf, which is a quiet conversation.
- Cost: 3 weeks: a new close-up scene. It is where souvenirs from the story, mended things and
  the cat's hoard (26) go, so it pays back as those arrive.
- Coins: none at first; small shelf things later **(coins)**.
- Risk: a scene with nothing in it. Build it after three kinds of thing exist to put there.

**14. The reveal.** Redo the room while your partner is away. When they next open it, the old
room wipes to the new one, once.

- Pair: the pair's own; needs no content.
- Cost: 1 week on top of the home book's snapshots.
- Coins: none.
- Risk: the last write wins on a shared layout, so two redoing at once undo each other. Show
  "your partner is arranging" from presence.

### 5. The home while you are away

**15. While you were out.** Coming back after hours, a small reel of what happened: she slept on
your side, chased the yarn at dusk, your partner fed her at nine. Tap a moment and she walks
there and does it again for you. *(Top 5.)*

- Pair: solo feeding the pair; the partner's deeds are in the reel.
- Cost: 1.5 weeks. The diary, the day story, the homecoming and "send her to a spot" all exist.
- Coins: none.
- Risk: the reel must be true on both phones. Compute it from the shared layout of the living
  room, not from whichever room the phone shows.

**16. Home on the widget.** The cat widget shows where she is and what she is doing now, as a
pose and a place: "on the sill, watching the rain".

- Pair: solo.
- Cost: 1.5 weeks; poses exist (`MochiPose`), the widget's budget is an entry every 10 minutes.
- Coins: none.
- Risk: a widget that is wrong is worse than none. Say "about now", and never show a need.

**17. Your partner's traces.** The room shows the other person. Their mood is an object (a
blanket out for sleepy, a laptop on the desk for busy), and the bedroom lamp is one lamp: switch
it on here and it glows there.

- Pair: the pair's own.
- Cost: 1 week for the shared lamp (lights are a `RoomInput` already; they need a place in the
  pair's state). 2 more for mood objects, which need a prop at a spot.
- Coins: none.
- Risk: a lamp left on can read as "waiting for you". It is a light, with no message and no push.

**18. The sill.** What you put out decides who comes by: a feeder, a saucer, a lantern. A guest
book records each visitor and which of you saw them first.

- Pair: solo feeding the pair, and "come and look" when both are home.
- Cost: 3 weeks and character art. It is the home half of the vision's neighbours (G); build
  them together or not at all.
- Coins: **(coins)** the feeder and what goes on the sill.
- Risk: Neko Atsume's loop is "buy to attract". Visitors must come for free things too.

### 6. Things that take two

**19. Flat-pack for two.** The cat tower arrives in pieces. One of you has the instructions, the
other has the parts, and neither has both. Describe, guess, assemble; a tower built wrong stands
anyway, and you may keep it that way.

- Pair: needs both, by turns, never at the same moment. The halves split as the story's clues
  do (`ClueSplit`), with no server change.
- Cost: 3 weeks for one piece. Each further piece is a diagram and a set of parts.
- Coins: none; it makes a big purchase an evening's fun **(coins: the purchase itself)**.
- Risk: a pair of one cannot build. After three days the instructions turn up in the box.

**20. Two-hand jobs.** Some things take both of you at once: hanging the long garland, moving the
bookcase. Both hold, it moves.

- Pair: both, live; `JointCatChoice` is the gesture and presence says when it is possible.
- Cost: 2 weeks.
- Coins: none.
- Risk: live play is rare for a pair in different time zones. Never the only way to do a thing:
  alone it takes two tries and the cat "helps".

**21. The thank-you vase.** For the real home. One of you ticks "did the dishes" on a list, the
other sends thanks with a tap, and a flower goes in the vase. When the vase is changed the old
flowers are pressed into a book.

- Pair: the pair's own.
- Cost: 2 weeks: lists and `doneBy` exist; a vase prop; preset thanks, no free text.
- Coins: none. The list tick's existing 1 coin a day is unchanged.
- Risk: the highest in this document. No assigning, no due dates, no counts per person, no
  reminder. If it cannot be only gratitude, do not build it.

### 7. Seasons and the long run

**22. Seasons and the decorations box.** The window follows the real season and the weather; in
December a box of lights comes out of the closet, and it comes out again next December with
everything you added.

- Pair: putting them up is a two-hand job (20) or anyone's.
- Cost: 3 weeks. Window views and weather exist behind Labs; season art for the window.
- Coins: **(coins)** seasonal pieces. Proposal against economy.md: they return every year and
  the Shop says so.
- Risk: a season is a deadline unless it visibly returns.

**23. The house remembers.** The home wears in where life happens: a notch on the door frame for
every month of the cat, with both your names; a hollow in the cushion she prefers; scratches on
the post; a faded square where the print used to hang.

- Pair: solo feeding the pair; notches are made together or alone.
- Cost: 3 weeks: marks are flat pictures laid in the room, which is Room work, and the baked
  shell limits where.
- Coins: none.
- Risk: wear must read as love, not damage. Nothing looks dirty.

**24. The home book.** A portrait of the room is taken each month on the cat's day. The book is
those portraits as a flip-book, with what happened between them: the piece that arrived, the
case solved, the request met. *(Top 5.)*

- Pair: solo feeding the pair.
- Cost: 2 weeks: an offscreen picture of the room, kept on the phone and in the pair's storage,
  with the layout of that day beside it. The room's past is not recorded today, so the book
  starts from the day it ships.
- Coins: none. It can retire `Lv.`, which means nothing today.
- Risk: empty for the first month. Start it with the day the cat came and "day one".

**25. A second space.** The door that has always been stuck opens: a balcony, an attic.

- Pair: both.
- Cost: months, and a scene's worth of art. Named so that nobody starts it early.
- Coins: **(coins)**.
- Risk: the cost.

### 8. Collection and display

**26. The cat's hoard.** She keeps things: a pencil after you drew, a ribbon after a gift, a
bottle cap after nobody knows what. Find her stash and each thing says when it was taken and why.

- Pair: solo feeding the pair; half the hoard comes from the partner's deeds.
- Cost: 2 weeks, about 40 small pictures and a rule each over the journal.
- Coins: none.
- Risk: a collection for its own sake is "complete the set". No count out of a total is shown.

### 9. Surprise and discovery

**27. Things behind things.** Move the bookcase and there is a patch of older wallpaper; lift the
rug and there is a pencilled height chart from whoever lived here before. A dozen finds, each
once, each found by rearranging.

- Pair: solo feeding the pair.
- Cost: 2 weeks: a rule over cells and a flat picture each; feeds the story's episodes.
- Coins: none.
- Risk: finite. Twelve finds are twelve small delights and then done, which is fine.

**28. The night room.** After midnight the room is another place: a patch of moon on the floor,
the radio on low, the cat doing things she only does at night.

- Pair: solo.
- Cost: 2 weeks on the live shell, more on the baked one. Belongs with the vision's Cat watch (D).
- Coins: none.
- Risk: rewards being up late. Night follows the pair's clock from dusk, not from midnight.

### 10. Economy fit

**29. The saving jar.** Pick one piece to save for together. A jar on the shelf fills as coins
come in, and the day it is full the piece arrives as a parcel.

- Pair: both choose (the wishlist exists).
- Cost: 1 week.
- Coins: **(coins)** no new number: it shows the balance against a goal. It turns "8 months of
  slow coins" into something watched together.
- Risk: when `payments` is on, a jar that is nearly full is an upsell. The jar never links to
  packs and never says how much is missing in money.

### Scores

Judgments, 1 to 5: fun, linger (holds a person in the room), pair (solo play feeds the other).
Weeks for a first slice; "Room" is whether the sealed Room code must change.

| # | Mechanic | Fun | Linger | Pair | Weeks | Room | Content to keep up |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 15 | While you were out | 4 | 5 | 4 | 1.5 | no | none |
| 4 | Little messes | 5 | 4 | 4 | 2 | no | none |
| 11 | The cat's requests | 4 | 4 | 4 | 2 | no | light |
| 12 | Parcels | 4 | 3 | 5 | 1.5 | little | none |
| 24 | The home book | 3 | 3 | 4 | 2 | little | none |
| 19 | Flat-pack for two | 5 | 4 | 5 | 3 | no | a piece at a time |
| 17 | Partner's traces (the lamp) | 4 | 3 | 5 | 1 | little | none |
| 5 | Small fixes | 4 | 4 | 3 | 3 | yes | fixes |
| 27 | Things behind things | 4 | 3 | 3 | 2 | yes | finite |
| 26 | The cat's hoard | 4 | 3 | 4 | 2 | no | pictures |
| 6 | Plants | 3 | 4 | 4 | 2.5 | yes | little |
| 14 | The reveal | 4 | 2 | 5 | 1 | no | none |
| 29 | The saving jar | 3 | 2 | 4 | 1 | little | none |
| 9 | Reupholster | 2 | 2 | 3 | 1 | no | none |
| 1 | Favourite things | 3 | 3 | 3 | 1 | no | none |
| 3 | A good brush | 3 | 3 | 2 | 1.5 | no | none |
| 2 | Little wishes | 3 | 4 | 3 | 2 | some | wishes |
| 16 | Home on the widget | 3 | 2 | 2 | 1.5 | no | none |
| 10 | Our style | 3 | 2 | 3 | 1.5 | no | copy |
| 20 | Two-hand jobs | 4 | 2 | 5 | 2 | yes | none |
| 13 | The shelf | 4 | 4 | 4 | 3 | yes | things to put on it |
| 23 | The house remembers | 4 | 4 | 4 | 3 | yes | little |
| 22 | Seasons and the box | 4 | 4 | 4 | 3 | yes | season art |
| 28 | The night room | 3 | 4 | 2 | 2 | yes | little |
| 21 | The thank-you vase | 3 | 2 | 5 | 2 | yes | none |
| 18 | The sill | 4 | 4 | 3 | 3 | yes | characters |
| 7 | Room projects | 5 | 5 | 5 | 4 | yes | projects, art |
| 8 | Paint and paper | 4 | 4 | 4 | 4+ | yes | bakes |
| 25 | A second space | 5 | 5 | 5 | months | yes | a scene |

## 5. One loop

The five picked are the five that need the least and connect the most. Together they are the
loop the brief asks for, a home that slowly changes with the cat's life:

| Rhythm | What happens | Mechanic |
| --- | --- | --- |
| Each time you come back | You see what she did, and what your partner did | 15 While you were out |
| Most days, or not | Something is askew because of what she did; you put it right, or leave it | 4 Little messes |
| About weekly | She wants the room a little different; you make it so and she moves in | 11 The cat's requests |
| When you buy or give | A box arrives, is opened, and becomes hers | 12 Parcels |
| Monthly | The room is photographed, and the month goes in the book | 24 The home book |

Each feeds the next. The reel (15) is where a mess (4) is explained: "19:10, zoomies" is why the
armchair is crooked. A request met (11) and a parcel opened (12) are entries in the book (24),
and the book's monthly portrait is where a pair sees that the room they have is the one their cat
asked for. All five read the same three things that already exist: the cat's journal, her diary
and the shared layout.

What joins the loop next, in order:

1. **Flat-pack for two (19)** turns a parcel into an evening for two.
2. **The lamp (17)**, a week, the simplest "you are here too".
3. **The cat's hoard (26)** and **things behind things (27)** give the book and the shelf
   something to hold.
4. **Small fixes (5)**, **plants (6)**, **the house remembers (23)**: these need the Room to
   hold state, so they wait for one piece of Room work, a prop or a mark at a spot. Mischief's
   mouse and the story's clues wait for the same thing. It is the most valuable single enabler
   in the app and it belongs to the owner of the Room files.

With the three already built: a mess is the cat's, Mischief's "spot what moved" is the partner's,
and they must look different (askew with a paw print, against neatly moved). A story episode's
ending can arrive as a parcel. A trick learned at Cat school is a book entry.

## 6. First slices

Each behind its own remote flag (`off`, `on`; default `off`; `draft`), each shippable alone, in
this order. The measure they share is time: the share of sessions of three minutes or more
(`SessionEnded`, on `main` since #1013), `on` against `off`.

### 1. While you were out (`away-reel`), 1.5 weeks

- **In.** On a homecoming (3 hours away, as today), a card over the room instead of the 6-second
  line: up to four moments since you were last here, from `CatDayStory` and the partner's deeds,
  each with her pose and the place. Tap a moment: she walks to the spot and plays the step again.
  The card can be dismissed and is in the care sheet afterwards.
- **Out.** Traces in the room, the widget (16), anything older than yesterday.
- **Events.** `AwayReelShown`, `AwayMomentReplayed`.
- **Works if** a moment is replayed on 40% of the homecomings that showed a reel, in weeks 2 to 4.
- **Kill if** under 15%, or the card is dismissed within two seconds on most homecomings.

### 2. Little messes (`little-messes`), 2 weeks

- **In.** After an hour the diary gives to play or mischief, one floor piece is shown turned 45°
  or slid one cell, with a paw print. Hold to straighten: a slide, a click, a haptic, her
  reaction. A `Tidied` journal event (fills no need, pays nothing) clears it on the partner's
  phone. At most three open; moving the piece in Decorate clears it too. A setting turns it off.
- **Out.** Toppled or spilled things (they need Room state), wall pieces, the bedroom.
- **Events.** `MessTidied`.
- **Works if** pairs that saw a mess tidy a median of four a week in weeks 2 to 4, and in half of
  those pairs both partners have tidied.
- **Kill if** under one a week, or more than 15% of pairs switch it off, or `RoomItemMoved` falls
  against `off` (the mess put people off arranging).
- **Note.** A new journal event needs `minAppVersion`, as Mischief's did.

### 3. The cat's requests (`cat-requests`), 2 weeks

- **In.** Six briefs as data: a nap in the sun (a rest piece within two cells of the window), a
  lookout, a runway (a clear lane for zoomies), a hiding place, the bed away from the bowl,
  something new to sniff (any three pieces moved). One open at a time, shown as a pill in the care
  sheet and by her behaviour. Met: she uses it at once, and a card is kept. "Not this one" swaps
  it without cost. The next opens the room day after. Every brief can be met with the base room
  and the two starter pieces; a test proves it.
- **Out.** Briefs from visitors, briefs for the bedroom.
- **Events.** `RequestMet` (brief id), `RequestSwapped`.
- **Works if** half the pairs that saw the first meet three within three weeks.
- **Kill if** under 20% meet a second, or more are swapped than met.

### 4. Parcels (`parcels`), 1.5 weeks

- **In.** A bought piece arrives as a box by the door; a tap opens it into arranging. The box
  stays until put away and does not count towards the eight pieces. "Wrap it for {partner}" in the
  buy sheet: the partner's room shows a wrapped box with a tag of up to 40 characters, and the
  Inbox says a parcel came. The buyer sees it opened.
- **Out.** Flat-pack (19), parcels from the story, the saving jar (29).
- **Events.** `ParcelOpened`; `ShopGiftSent` exists.
- **Works if** one purchase in five is a gift in weeks 2 to 4, and half the boxes are still in the
  room a day later.
- **Kill if** under one in twenty is a gift.
- **Payments.** Uses the existing order path and price. Check the wrap flow again before
  `payments` is on: a gift must never be a reason to show packs.

### 5. The home book (`home-book`), 2 weeks

- **In.** A picture of the living room taken on day one (for a pair that already exists, the day
  the flag turns on) and on each month's cat day, kept for the pair with that day's layout. A
  sheet from the care sheet: the portraits as a flip-book, and between them the entries
  that exist today (the cat came, a piece arrived, a case solved, a request met).
- **Out.** Wear marks (23), the reveal (14), a yearly recap, sharing outside the app.
- **Events.** `HomeBookOpened`.
- **Works if** half the pairs open it in the month after their second portrait, and a third open
  it twice.
- **Kill if** under 15% open it twice in 60 days.
- **Open question.** Whether `Lv.` goes when the book arrives. It should; it is the owner's call.

The thresholds are starting points by judgment, as in the vision. Under 100 pairs an arm, read
the numbers inside `on` and talk to couples ([experiments.md](experiments.md)).

**Order with what is already queued.** Mischief, Cat school and the story are ahead in the
experiment queue. `away-reel` changes one moment and can run beside any of them. `little-messes`
should not run in the same arm as Mischief's "spot what moved" when that is built.

## 7. Numbers to read first

No admin token exists, so none of this was read. Each read moves a decision here.

| Read | Route | It decides |
| --- | --- | --- |
| Pairs that open Decorate, place, move | `features` (`DecoratingOpened`, `RoomItemPlaced`, `RoomItemMoved`) | If few pairs ever arrange the room, 4 and 11 start from nothing: build 15 and 12 first and let parcels pull people into arranging |
| Pieces owned per pair | `economy`, `ShopItemBought` | If most pairs own two or three pieces, requests must stay within the base room, and the cap of eight is not yet a problem |
| Median balance against prices, hoarding share | `economy?range=30&hold=14` | Whether any new sink (6, 8, 9, 22) has coins to take. A low median says: labour only, no new prices |
| How often a pair comes back after 3 hours | none yet; `AppOpened` per day is a proxy | How often 15 can show at all |
| Session ranges | `SessionEnded` | The baseline every slice is judged against. Two weeks of it before the first flag starts |
| Gifts today | `ShopGiftSent` | Should be zero (no screen sends it); if not, something else is |

## 8. What not to build

- **Dirt that builds up, plants that die, things that break for good.** The whole genre of
  upkeep-as-pressure. It is what makes a pet app a chore, and reviews say so.
- **A chore chart with assignment, points or a tally per partner.** See lesson 7.
- **A room score, or anyone else's room to compare with.**
- **Repair or build timers, with or without a way to skip them.** A step that opens "the next
  room day" is pacing; a countdown is an appointment.
- **A brief or a wish that needs a purchase.** That is a shop in the room.
- **Mystery parcels.** A parcel holds what was chosen or what a story gave.
- **Coins for tidying, fixing or watering.** There is no room in the pacing test and it would
  turn a toy into a wage.
- **Real-weather or real-location features that need a new permission.** Seasons come from the
  date.

## Evidence

Tags: **[B]** observational or company data; **[C]** practitioner, journalism or review text.
"Snippet": seen in search results, page not opened. Nothing found was an experiment or a
controlled study. The vision's evidence (couples research, streaks, minors) is not repeated.

### Tidying, repair, building

- Unpacking: "no scores, or fail states or negative consequences"; pillars "contemplation,
  discovery, and expression" [C]
  ([Game Developer](https://www.gamedeveloper.com/design/unpacking-the-design-pillars-of-a-chill-puzzle-game)).
  Story only through about 1,000 items; a partner's fixed things you must fit round [C]
  ([GDC 2022](https://www.gamedeveloper.com/gdc2022/gdc-2022-unpacking-a-narrative-through-1-000-household-items)).
- A Little to the Left: several valid answers; the cat as comic relief; a daily small puzzle [C]
  ([Nintendo Life](https://www.nintendolife.com/features/exclusive-theres-always-a-new-mess-turning-real-life-and-a-real-cat-into-a-tidying-up-game)).
- PowerWash Simulator: 162,325 mood reports from 8,695 players; mood rose 0.034 on a 0 to 1 scale
  during play, most in the first 15 minutes; no causal claim [B, snippet]
  ([Oxford](https://www.ox.ac.uk/news/2024-09-25-new-study-reveals-positive-mood-changes-during-video-game-play)).
- The Sims 4 in 2021: 226M of 1.2B hours in Build Mode [B]
  ([Sims Community](https://simscommunity.info/2021/12/16/the-sims-4-player-stats-for-2021/)).
- House Flipper: the before and after is praised; "a boring and repetitive rut" after a few
  houses [C, snippet]
  ([Game Informer](https://www.gameinformer.com/review/house-flipper/a-definite-fixer-upper)).
- Townscaper: "more of a toy"; a score makes you play to the score [C, snippet]
  ([PC Gamer](https://www.pcgamer.com/townscapers-developer-on-how-its-radically-casual-design-is-inspiring-a-new-wave-of-low-stress-builders-to-adapt-the-blueprint)).
- Homescapes: a finished task lets you pick one of several designs [C, snippet]
  ([AppGamer](https://www.appgamer.com/homescapes/strategy-guide/how-do-you-handle-renovations)).

### Animal Crossing, Cozy Grove, Hay Day

- New Horizons: big changes take a real day; crafting was added for people who play when the
  shops are shut [C]
  ([Game Developer](https://www.gamedeveloper.com/design/why-nintendo-s-new-i-animal-crossing-i-features-allow-instant-change-in-the-real-time-game)).
  Tools that break are the most repeated complaint [C, snippet]
  ([Screen Rant](https://screenrant.com/animal-crossing-new-horizons-crafting-system-bad-boring/)).
- Happy Home Paradise: a loose brief, no grade [C, snippet]
  ([Kotaku](https://kotaku.com/animal-crossings-happy-home-dlc-isnt-just-worth-buying-1848015955)).
  Happy Home Academy's score rewards rules over taste [C, snippet]
  ([Screen Rant](https://screenrant.com/animal-crossing-new-horizons-happy-home-academy-ranking/)).
- Cozy Grove: pacing as "an enjoyable episodic experience over months"; the game says when the
  day's story is done and you may still decorate [C]
  ([Vice](https://www.vice.com/en/article/bvx9vw/cozy-grove-is-ok-telling-players-to-log-off-its-delightful)).
  "If you can't decorate, it's not fun" [C]
  ([Siliconera](https://www.siliconera.com/interview-spry-fox-explains-how-animal-crossing-shaped-cozy-grove/)).
  Criticised as "artificial and frustrating" by players with a free afternoon [C, snippet]
  ([Nintendo Life](https://www.nintendolife.com/reviews/switch-eshop/cozy_grove)).
- Hay Day: "nothing bad ever happens in Hay Day" [C]
  ([Supercell](https://supercell.com/en/news/nothing-bad-happens-in-hay-day/)).

### Cats and characters with their own lives

- Little Kitty, Big City: survival dropped; boxes and things knocked off shelves came first [C]
  ([Game Developer](https://www.gamedeveloper.com/design/how-little-kitty-big-city-was-designed-to-steal-hearts-and-fish)).
- Tsuki's Odyssey: the character is found doing something different at each visit [C]
  ([GameGrin](https://www.gamegrin.com/reviews/tsukis-odyssey-review/)).
- Usagi Shima: touch and free placement; "never demands your time" [C]
  ([Siliconera](https://www.siliconera.com/review-usagi-shiima-improves-on-the-neko-atsume-formula/)).
- Adorable Home (a couple, cats, a house): praised for mood; complaints are waiting, one
  currency source and repetition; players ask for more to do with the partner [C, snippet]
  ([App Store](https://apps.apple.com/gb/app/adorable-home/id1486637414)).

### Two people

- It Takes Two: each player their own abilities, "communication is key" [C]
  ([The Ringer](https://www.theringer.com/2021/4/22/22396763/josef-fares-it-takes-two-interview-co-op-gaming)).
- Chore apps: "The app turned my wife into my manager"; clarity agreed first is what helps [C]
  ([MIT Sloan](https://sloanreview.mit.edu/article/hacking-inequality-at-home/)). 86% of one
  family organiser's users were women; getting the less engaged partner in is unsolved [C]
  ([MIT Technology Review](https://www.technologyreview.com/2022/05/10/1051954/chore-apps/)).
- Fair Play study: not peer-reviewed, funded by the licensor, 27% finished; modest shifts [B]
  ([Daminger](https://allisondaminger.substack.com/p/but-does-it-really-work)).

### Dark patterns

- The darkpattern.games taxonomy (temporal, monetary, social, psychological); "complete the
  collection" and "reciprocity" are on it, which is why 26 shows no total and 19 has a way out
  for one [C, via a summary] ([Gigazine](https://gigazine.net/gsc_news/en/20251117-dark-pattern-game)).
- FTC and the Genshin Impact publisher, 2025: no loot boxes to under-16s without consent [B,
  snippet]
  ([FTC](https://ftc.gov/business-guidance/blog/2025/01/level-tips-businesses-ftcs-settlement-genshin-impact-developer-hoyoverse)).

### Not found

Time spent decorating in any game but The Sims; retention for Adorable Home, Cats & Soup or Usagi
Shima; any study of gamified housework in couples; any measurement of a "help your friend" loop;
any designer's account of why Animal Crossing's small daily tasks feel pleasant.

### Code and docs read

`RoomInterface`, `DecorInterface`, `FeatureDecor`, `FeatureShop`, `FeatureMischief`,
`FeatureStory`, `packages/ios/pet` (Brain, Life), `apps/ios/Nooki` (Room, Scene, UI/Home, UI/Decor,
Model), `apps/ios/OurioWidgets`, `packages/backend/pair-room`, `packages/backend/platform`
(`room-schema.ts`), `packages/contracts/domain` (`shop.ts`, `coins.ts`, `metrics.ts`,
`test/coin-pacing.test.ts`), `packages/contracts/realtime`.

Found on the way, for whoever owns them:

- The three "appears" rows in [section 1](#the-cat): the inspect-a-new-piece behaviour and the
  brain's Mischief group look unreachable in the shipped room, and the server's temper is not
  applied. Each is behaviour the cat was written to have and does not show.
- [cat-brain.md](cat-brain.md) names `GenzCatBrain.swift`, which is gone; [cat-state.md](cat-state.md)
  says the dice use a seed drawn per launch, and the code uses the room's; [widgets.md](widgets.md)
  says needs do not reach the widget, and they do.
- The cap of eight placed pieces is checked on the phone only.
