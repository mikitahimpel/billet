# Mini-games and other reasons to stay

More things to play in Ourio, alone and together. A proposal, 2026-11-25. It continues
[gameplay-vision.md](gameplay-vision.md) and [gameplay-home.md](gameplay-home.md) and does not redo
what they started: Mischief, the secret life, Cat school, Night raid and the 29 home mechanics.
Two of the ideas here are built as Labs prototypes ([section 7](#7-the-two-prototypes)); the rest
is on paper.

**The short version.** Ourio's games are about knowing each other (Who knows who, Draw and guess)
or about the room (Mischief, Night raid). Nothing is for two people on one sofa, nothing is a
two-minute thing with any depth, nothing is made for a pair in two cities or for one of them on a
train, and nothing makes a sound. Forty ideas are in [section 5](#5-forty-ideas). The five to
build, fun first:

| # | Idea | In a line | First slice | State |
| --- | --- | --- | --- | --- |
| 1 | **Fold and draw** | One draws the top half of a creature, the other the bottom, seeing only the fold. The sheet opens and the cat names it | 1.5 weeks | Labs prototype, PR #1021 |
| 2 | **Pack for two** | One suitcase, three things each and the cat. The first packs knowing only the names of the other's things | 2 weeks | Labs prototype, PR #1022 |
| 3 | **Postcards from Mochi** | Put the cat into a photo of where you are. It lands on your partner's board as a postcard | 1.5 weeks | on paper |
| 4 | **Twenty sniffs** | Pick a secret thing for your partner. They ask yes-or-no questions and the app answers at once | 2.5 weeks | on paper |
| 5 | **Music box** | Lay eight notes, your partner lays eight over them, and the room's radio plays your tune | 2 weeks | on paper |

Which of them bring a person back several times a day without a reminder: **Fold and draw** and
**Twenty sniffs**, because every finished turn is something the partner did and each takes a
minute; **Postcards**, because the trigger is being somewhere, not the clock. Pack for two and the
Music box are for an evening, and that is fine.

None of the five pays a new coin, sells anything, has a timer or expires.

**Limits of this document.**

- **No usage numbers exist.** There is still no admin token, and the only measure of time,
  `SessionEnded`, reaches real pairs with the next TestFlight build. Every statement about today's
  app is from the code and the docs. Every threshold below is a starting point set by judgment.
- "Fun" is a design judgment. The prototypes were walked in a Simulator by one agent with one
  finger; two people have not played them. That is the next step and the only one that counts.
- The research was read as search summaries, not as pages, except where the evidence list says
  otherwise. Nothing found was an experiment on a couples game.
- Estimates are for one engineer who knows the app, without art unless art is named.

## 1. What exists

Read from the code on `main` at `04d0608f`.

| Thing to do | Who | Rhythm | Flag | Coins |
| --- | --- | --- | --- | --- |
| Care games: feed, water, laser, brush (`FeatureGames`) | solo | whenever a need is low | none | 3 a play, `games` cap 4 a day |
| Who knows who | both, by turns | one round a day, closes at midnight | none | 2 a round, 1 a hit |
| Draw and guess | both, by turns | one open riddle each | none | up to 3, `games` cap |
| A note, doodle or photo to the partner's widget; live drawing when both are on the canvas (`LiveRoom`) | one sends | free | none | 1 or 2, `notes` cap 3 |
| Pick tonight; date ideas swipe | both, by turns | free | `pick-tonight` on | 2 a date match, 6 a rating |
| Love streak, mood check-in, hug | both | daily | none | 1 a lit day |
| Decorate, shop, daily gift | solo | free, daily | none | sinks; gift 1 or 2 |
| Mischief: hide the toy mouse | both, by turns | free, a mouse waits | `mischief` off | 2 for a find, `games` cap |
| Cat school: tricks, stars, routines | solo, routines to the partner | free | `cat-school` off | none |
| The secret life: one episode, split clues | both, by turns | a beat a room day | `story` off | none |
| Night raid: keeper against cat | two on one phone | free | Labs only | none |

Written and unused, relevant here: the live canvas has a "your partner is here" view
(`LivePartnerView`) with no caller; `DailyPrompt` holds 14 questions and 14 doodle prompts nobody
sees; `CatPlay.partnerPetted` and `JointCatChoice` (both holding at once) have no caller; the Labs
switch list (`LabExperiment`) already names `sealedNote`, `nextVisit`, `onThisDay` and
`sundayPost`.

What the list has in common: seven of the eleven are by turns across two phones, and all four
solo games are the same on the twentieth play. One thing is for two people in one place, and it
is in Labs.

## 2. The gaps, by moment

| Moment | What a person can do today | What is missing |
| --- | --- | --- |
| **Waiting for the partner** (they have not answered; they are asleep nine hours away) | Care games, decorate | Something solo that leaves a thing for the other to find, and takes longer than ten seconds |
| **A two-minute break** | Pour kibble to a mark | A small game with a right and a wrong way to play it; a puzzle the two can compare over dinner |
| **A long evening together** | Night raid, in Labs | Anything to play side by side: one phone passed back and forth, or both leaning over it |
| **A pair in two cities** | Notes, Who knows who | Being in the same place at the same time: the live canvas exists and nothing invites anyone onto it. Nothing uses the two places being different |
| **Made up after a fight** | A hug, which uploads when the sender next opens the app and sends no push | A small wordless gesture that arrives |
| **A lazy morning** | Nothing slow | Something with no clock that takes ten minutes and can be put down |
| **Travelling** | Photo notes | The cat coming along. Anything that works with the phone in one hand, and waits for signal |
| **By ear** | Nothing: the app is silent | Any play with sound, music or voice |

Two more gaps are not moments. **Split knowledge:** only the secret life gives the two different
halves of something, and it is one episode. **Authorship:** Draw and guess, Mischief and the raid
let one partner make a puzzle for the other; these never run out, and there are three.

## 3. What the references teach

Sources and their weight are in [Evidence](#evidence). Eight lessons, each used below.

1. **One small thing, the same for both.** Wordle was built by one man for his partner. Its
   author said a random word would not have caught on: it is "one puzzle, and everybody is
   solving it", three minutes a day, with no push and no endless play. Families report talking
   more because of a shared daily result. For Ourio: a tiny puzzle both get from the same seed
   (27, If it fits), and no notification for it.
2. **Turns that wait, and a shelf of small games.** GamePigeon's reviewers praise that "you can
   respond … when you have time" and the variety; they complain about first-mover advantage, slow
   games that never finish and nothing new for years. Words With Friends is still the default
   answer to "a game for a long-distance couple". For Ourio: every game by turns, one open turn
   each way as riddles have, the starter swaps.
3. **Long-distance couples play together, not against.** A 2025 University of Washington diary
   study of 13 long-distance couples who play weekly: cooperative play dominated, competition
   worked only at equal skill, sensing the other's presence mattered most, physical closeness was
   the facet games served worst, and memories of play were lost in screenshot folders. For Ourio:
   co-op first; a kept gallery for whatever a game makes (the board exists); one-phone games for
   the days the two are in one place, because that is when a phone can bring them shoulder to
   shoulder.
4. **Misunderstanding is the joke.** Gartic Phone and its ancestors run on the drawing drifting
   from the prompt. Nobody has to draw well; drawing badly is better. For Ourio: Fold and draw.
5. **Split information makes people talk.** Keep Talking and Nobody Explodes gives one player
   the bomb and the other the manual: "there's no way to disarm the bomb without the
   information", so the talk is the game. Wavelength and The Mind are built on guessing what the
   other is thinking under a tight limit on what may be said. For Ourio: Pack for two; the
   lights-out walk; same wavelength.
6. **The phone as a prop.** Heads Up! is a word on a forehead and a tilt. It needs a room with
   people in it and no screen-staring. For Ourio: a few games played with the phone, not on it.
7. **One touch, and it looks different tomorrow.** Tiny Wings is one finger and islands that
   change every day. Monument Valley can be finished in about 90 minutes and nobody minded. For
   Ourio: a solo game may be small if the touch is good; it does not need a hundred levels.
8. **A hit drawing game died in a month.** Draw Something lost about 4 of 14 million daily
   players in a month of 2012; commentators blamed bugs, ads and sameness. Its words came from a
   catalogue and its turns were a chain with no end. For Ourio: the pair makes the content, a
   round ends, and what it made is kept.

On couples apps: Paired, Lovify, Candle and Coupletition all sell the same loop, a daily question
hidden until both answer, and all add a streak; Candle adds a "thumb kiss" and one-minute games.
Ourio has that loop already (Who knows who). None of them has a place, a cat, or a game the pair
authors. That is the room to work in.

## 4. The kind rules

As in [gameplay-home.md](gameplay-home.md#3-the-kind-rules), hard for every idea below: nothing
expires; no guilt and no nag; no dark patterns; safe for 13 to 17; no couple against couple; no
sold surprise; no daily coin; Home is not a shop. Three notes on how they bite here:

- **A turn is the only push.** "Leo folded a sheet for you" is something the partner did, sent
  once. No game below has a reminder, a daily window or a "your turn is waiting".
- **Winning inside the pair is fine; a running tally is not.** A round has a result. No screen
  counts who is ahead.
- **Text.** Ideas that let one partner type to the other say so in their risk; each offers word
  chips first, and typed text is capped at 40 characters under the report and block that notes
  have.

**Coins.** The pacing test has no room for a new daily coin (380 / 14 = 27.1 days against a floor
of 28), so no idea adds one. "none" below means the game pays nothing. "`games` cap" means it
could pay from the existing source inside its cap of 4 a day, as Mischief's find does, so the
day's budget does not move. **(coins)** marks an idea that gives an existing sink a new use or
suggests a later one: with `payments` on it is something money can shorten, and it needs the
owner's eye then.

## 5. Forty ideas

Each row: the idea in a line; who plays; how long a sitting is; what content it needs to start
and to keep going; what it stands on in the code; coins; the main risk. Scores, 1 to 5, are in
[the table after](#scores).

### Side by side: one phone, two people

| # | Idea | Who | Sitting | Content | Stands on | Coins | Risk |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | **Fold and draw.** Top half, fold, bottom half, open. The cat names the creature | two, one phone; later by turns on two | 2 to 3 min | none: the pair is the content | `Stroke`, `InkLayer`, the Machine pattern; later the riddle route and the board | none; inks get a second use **(coins)** | Drawings between two people already exist as notes; nothing new for 13 to 17 |
| 2 | **Pack for two.** One suitcase, three things each and the cat; the first knows only the names of the other's things | two, one phone; later by turns | 3 to 5 min | none: levels are cut from a seed | new model, Foundation only; the Machine pattern | none | Too hard or too easy is a tuning question only two people can answer |
| 3 | **Four paws.** Each holds one end of a tray with the cat's cream on it, a thumb each, and they carry it across the room past the furniture | two, one phone, at once | 1 to 2 min | none: the room is the course | the raid's board from `DecorLayout` and its fixed-step run | none | Two thumbs on a small phone are cramped; cannot be tried in a Simulator |
| 4 | **Say it sideways.** Phone on the forehead; the other describes the word; tilt for the next. Decks include the pair's own films, places and date ideas | two or more, one phone | 1 min a round | 6 decks of 50 words; the pair's lists cost nothing | `SharedList`, To watch, places; CoreMotion | none | The genre is well known; the personal deck has to be the point. Same room only |
| 5 | **Same wavelength.** A dial between two opposites ("a snack … a meal"). One sees the target and says one clue; the other turns the dial | two, one phone; by turns with clue chips | 2 min | 80 pairs of opposites | the hidden-until-both rule of `guess.ts` | none | A typed clue is free text; aloud or chips first |
| 6 | **Let go together.** Both hold a finger down and try to lift at the same moment with no countdown. The closer, the louder she purrs | two, one phone or two | 30 s | none | `JointCatChoice`, presence | none | A toy, not a game; fine as the smallest thing two can do |
| 7 | **Paw slap.** A fish swims by; first paw down gets it. A false start makes her sneeze | two, one phone | 30 s | none | the Machine pattern | none | Reflexes favour one partner every time; best of five, no tally |

### Apart, at the same time

| # | Idea | Who | Sitting | Content | Stands on | Coins | Risk |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 8 | **One sheet.** Both draw on the same paper at once, to a prompt that splits the work ("you draw the roof, I draw the door") | both, live | 3 to 5 min | 40 prompts | `LiveRoom`, `LivePartnerView`, `DailyPrompt`: written, unused | `notes` cap, unchanged | Both must be there; show the invitation only when presence says so |
| 9 | **Paw to paw.** Touch where your partner's finger is; the cat purrs between the two and the phone hums | both, live | 20 s | none | presence, `LiveStrokeBatcher` | none | Other couple apps have a "thumb kiss"; here it is a doorway into 8, not a feature |
| 10 | **Stargazing.** Out of the night window, each joins stars into a constellation and names it from word chips. A shared atlas keeps them | solo or both, live or not | 2 to 5 min | none: seeded skies | strokes, the window view (Labs today) | none | Needs the window as a close-up scene |
| 11 | **Press play.** Both tap ready on tonight's pick; three, two, one. The room dims and the cat settles to watch | both, live | 10 s, then the film | none | Pick tonight, presence | none | A utility, not a game. Cheap, and it is what long-distance pairs do anyway |
| 12 | **The lights-out walk.** One sees the room from above, the other steers the cat in the dark and hears only directions | two, one phone turned away, or a call | 2 min | none: the pair's room | the raid's board and run | none | Across two cities it needs a voice call the app does not have |

### By turns

| # | Idea | Who | Sitting | Content | Stands on | Coins | Risk |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 13 | **Twenty sniffs.** Pick a secret thing from 200 pictured ones. The partner asks yes-or-no questions from chips; the app answers at once; twenty questions at most | both, by turns; the asker plays alone | 2 min | 200 things with 24 yes-or-no facts each, once | the riddle route (one open each way), its push | `games` cap, or none | One wrong fact makes an unfair answer; the set needs a careful pass |
| 14 | **Our word.** Choose a five-letter word for your partner; six tries; the cat reacts to each letter | both, by turns | 2 min | a word list to accept tries; English only | `RiddleWord`, the riddle route | `games` cap | Too near Draw and guess's letter tiles and a famous daily game. Only if riddles prove loved |
| 15 | **Rug games.** A board on the rug: four in a row, dots and boxes, kibble mancala. A move a visit. Sometimes she sits on it | both, by turns | 30 s a move | none | one turn record and a push, like riddles | `games` cap | Generic; the first mover wins some of them, so the starter swaps |
| 16 | **Mochi's dream.** Each gives three words blind (a food, a place, a noise). The cat's dream comes out with all six in it | both, by turns | 1 min | 30 dream templates | hidden-until-both (`guess.ts`) | none | Typed words are free text; chips by default |
| 17 | **A photo in pieces.** Send a photo as a jigsaw. Your partner puts it together to see it | one sends | 2 to 4 min | none | moments and their media | `notes` cap, unchanged | A puzzle in front of a photo is friction: "just show me" is always there |
| 18 | **Two skies.** A photo prompt both answer ("the sky where you are", "your left shoe"). The two open side by side | both, by turns | 30 s | 60 prompts | moments, hidden-until-both | `notes` cap, unchanged | A prompt a day is a task. A prompt is drawn when someone asks for one |
| 19 | **Then and now.** Take an old moment again, with the old photo ghosted over the camera. Kept as a pair | solo or both | 2 min | none | moments, the camera | `notes` cap, unchanged | Occasional by nature |
| 20 | **Sealed for later.** A note or a drawing sealed until a date you pick, or until "when we next meet" | one sends | 1 min | none | notes; `sealedNote` is a Labs switch already | none | Forgotten seals: each shows on the calendar |
| 21 | **Slow post.** A long letter the cat carries, and it takes hours to arrive | one sends | 5 min | none | notes | none; stamps and seals get a use **(coins)** | A delay on purpose can read as a bug. Per letter, never the default |
| 22 | **Treasure map.** Hide a real thing at home, draw the map, mark the X. Found, it is confirmed with a photo | both, same home | 5 min | none | the canvas, the riddle route | none | Same home only |
| 23 | **Tiny quests.** Dares for an evening in: cook with one hand each, build a blanket fort. Swiped and matched like date ideas | both | an evening | 60 cards | `SwipeDeck`, the date catalogue | the existing 2 and 6 for a date | Only as good as the cards |
| 24 | **Echo.** A tune the two build: I play three notes, you repeat them and add one, and so on. The longest is kept | both, by turns | 30 s | none | the Music box (29) | none | Memory games frustrate some; a wrong note just ends that tune |

### Alone, and it reaches the other

| # | Idea | Who | Sitting | Content | Stands on | Coins | Risk |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 25 | **Postcards from Mochi.** Take a photo, place the cat in it, send. It arrives as a postcard on the board and the widget | solo; the partner receives | 1 min | none; six cat poses baked as the splash hero is | `CatFigure` and `bake_hero.py`, moments, the partner widget | `notes` cap, unchanged; stamps **(coins)** | A flat cut-out can look cheap: shadow, scale and six poses |
| 26 | **Mochi on your table.** The same with the real model standing on a real surface | solo | 2 min | none | the RealityKit cat, ARKit | as 25 | Performance, a camera prompt, and no splat cat in a Simulator. After 25 proves itself |
| 27 | **If it fits.** Today's box and a handful of cat-shaped pieces. The same box on both phones; older boxes stay | solo, compared | 2 min | none | Pack for two's model | none | Puzzle fatigue; it is a side dish |
| 28 | **Loaf.** One finger: she slides down sofa-cushion hills at dusk, hold to dive, let go to fly. The distance joins a trail the two share | solo | 2 min | none: seeded hills | a fixed-step run as in the raid; `TownPicture` | `games` cap | The feel takes weeks of tuning, and that cannot be estimated |
| 29 | **Music box.** Eight steps, five notes that always sound right. One lays a line, the other adds theirs, and the radio plays it | solo, then the other | 2 min | none: notes are made, not recorded | the radio model (bundled, unsold) | none; instruments later **(coins)** | Sound in a silent app: off until asked for, and it respects the mute switch |
| 30 | **Knock it off.** Flick things off the shelf into the basket with her paw. A good shot is sent as a replay | solo | 2 min | none: seeded shelves | replay from inputs, as the raid | `games` cap | Physics by hand |
| 31 | **The sound of where I am.** Five seconds of where you are. The partner picks which of four pictures it is | one sends | 30 s | none | a new kind of media | none | The widest privacy surface here: audio from 13-year-olds, `privacy.md`, storage, reporting |
| 32 | **Hum it.** Hum a song; the partner picks from your three titles | one sends | 30 s | none | 31's audio | none | As 31 |
| 33 | **Lap time.** Put the phone down. She curls up on the screen and purrs in your hand; if your partner's phone is down too, the two cats sleep side by side | solo or both | as long as you like | none | presence, haptics | none | A lit screen and a battery. Not a game, and maybe the most used thing here for a pair apart |
| 34 | **Find Mochi.** A crowded drawing of a room; she is in it somewhere | solo, compared | 1 min | a drawing each: heavy | none | none | The art is the whole cost |

### The cat

| # | Idea | Who | Sitting | Content | Stands on | Coins | Risk |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 35 | **Pet together.** Both stroke her at once and she melts in a way she never does for one | both, live | 20 s | none | `CatPlay.partnerPetted`, `CatPetting`: written, unused | `care` cap, unchanged | Being there together is rare |
| 36 | **Cat's choice.** Each offers one option: tonight's film, who washes up. She walks to one | both, or one phone | 20 s | none | her walk to a named spot | none | People will use it for things that matter; the copy keeps it a joke |
| 37 | **Three cups.** I shuffle the cups by hand; you watch the replay once and point. She watches too, and is no help | both, by turns | 1 min | none | replay from inputs | `games` cap | Thin after a week |

### Soft moments

| # | Idea | Who | Sitting | Content | Stands on | Coins | Risk |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 38 | **White flag.** After a row: she carries a small flag to your partner's side of the room. A tap takes it, and she sits between you | one sends | 10 s | none | the hug, once it arrives (see the vision's groundwork) | none | It must never show "not accepted"; the sender sees it taken or sees nothing |
| 39 | **Paper chain.** A chain to the next visit; either of you tears a link and may draw on it | both | 20 s | none | `nextVisit` is a Labs switch already; the canvas | none | A link a day is a task. Any number can be torn at any time |
| 40 | **The weave.** A five-by-five crossword where one has the across clues and the other the down | both, by turns | 10 min | a grid and ten clues each time: a treadmill | hidden halves, as `ClueSplit` | none | Content for ever. Named so nobody starts it lightly |

### Scores

Judgments, 1 to 5: **fun**; **back** (does it bring a person back in the same day, unprompted);
**pair** (does one person's play reach the other). Weeks are a first slice.

| # | Idea | Fun | Back | Pair | Weeks | Content to keep up |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Fold and draw | 5 | 5 | 5 | 1.5 | none |
| 13 | Twenty sniffs | 4 | 5 | 5 | 2.5 | none after the set |
| 25 | Postcards from Mochi | 4 | 4 | 5 | 1.5 | none |
| 2 | Pack for two | 4 | 3 | 5 | 2 | none |
| 29 | Music box | 4 | 3 | 5 | 2 | none |
| 3 | Four paws | 5 | 2 | 5 | 2 | none |
| 8 | One sheet | 4 | 2 | 5 | 1 | prompts |
| 33 | Lap time | 3 | 4 | 4 | 1.5 | none |
| 16 | Mochi's dream | 4 | 3 | 5 | 1.5 | templates |
| 27 | If it fits | 3 | 3 | 3 | 0.5 after 2 | none |
| 4 | Say it sideways | 4 | 2 | 4 | 2 | decks |
| 5 | Same wavelength | 4 | 2 | 5 | 1.5 | pairs of opposites |
| 23 | Tiny quests | 4 | 1 | 5 | 1 | cards |
| 28 | Loaf | 4 | 3 | 2 | 3 or more | none |
| 17 | A photo in pieces | 3 | 2 | 4 | 1.5 | none |
| 18 | Two skies | 3 | 3 | 5 | 1 | prompts |
| 38 | White flag | 3 | 1 | 5 | 0.5 after the hug | none |
| 36 | Cat's choice | 3 | 2 | 4 | 1 | none |
| 15 | Rug games | 3 | 4 | 4 | 2 | none |
| 24 | Echo | 3 | 3 | 4 | 0.5 after 29 | none |
| 12 | The lights-out walk | 4 | 1 | 5 | 1.5 after the raid | none |
| 30 | Knock it off | 4 | 3 | 2 | 3 | none |
| 10 | Stargazing | 3 | 2 | 4 | 3 | none |
| 20 | Sealed for later | 3 | 1 | 5 | 1 | none |
| 19 | Then and now | 3 | 1 | 4 | 1.5 | none |
| 35 | Pet together | 3 | 1 | 5 | 1 | none |
| 9 | Paw to paw | 2 | 2 | 5 | 1 | none |
| 6 | Let go together | 2 | 1 | 5 | 0.5 | none |
| 7 | Paw slap | 3 | 1 | 3 | 0.5 | none |
| 11 | Press play | 2 | 2 | 5 | 0.5 | none |
| 39 | Paper chain | 2 | 3 | 4 | 1 | none |
| 37 | Three cups | 2 | 2 | 3 | 1 | none |
| 21 | Slow post | 3 | 1 | 4 | 1 | none |
| 22 | Treasure map | 4 | 1 | 5 | 1 | none |
| 14 | Our word | 3 | 4 | 4 | 1.5 | a word list per language |
| 26 | Mochi on your table | 4 | 2 | 4 | 3 | none |
| 31 | The sound of where I am | 4 | 3 | 5 | 3 | none |
| 32 | Hum it | 4 | 2 | 5 | 1 after 31 | none |
| 34 | Find Mochi | 3 | 3 | 2 | 2 and art | a drawing each time |
| 40 | The weave | 4 | 3 | 5 | 3 | a grid each time |

## 6. The five to build

Picked for fun first, then for needing no content from us, then for filling a gap nothing else
fills. Each behind its own remote flag (`off`, `on`; default `off`; `draft`), each shippable
alone. The measure they share is the vision's: the share of sessions of three minutes or more
(`SessionEnded`), `on` against `off`, with `opensPerDay` and `notesPerDay` as guardrails. Under
100 pairs an arm, read the numbers inside `on` and talk to couples
([experiments.md](experiments.md)).

### 1. Fold and draw (`fold`), 1.5 weeks on top of the prototype

- **Why.** It is the oldest drawing game there is, it cannot be played badly, and the reveal is
  a laugh every time. The canvas, the strokes and the riddle plumbing exist. It fills "side by
  side" on one phone and "apart" by turns with the same code.
- **First slice.** By turns across two phones: a folded top half is a record in the pair's room,
  shaped like a riddle (one open sheet each way, one push: "Leo folded a sheet for you"). The
  finished creature and its name are kept on the board. The one-phone mode stays for the sofa.
  A sheet of three parts (head, body, legs: A, B, A) is the first thing to add.
- **Out.** Prompts, inks other than the two, sharing outside the app, a gallery beyond the board.
- **Events.** `SheetFolded`, `SheetOpened`.
- **Works if** pairs that opened one sheet finish a median of four a week in weeks 2 to 4, and
  70% of folded tops are finished within three days.
- **Kill if** under one a week, or under 40% of tops are ever finished.
- **Coins.** None. The inks a pair owns could draw here **(coins)**: an existing sink with a
  second use, to be looked at when `payments` is on.
- **13 to 17.** A drawing from one partner to the other is what a doodle note already is, under
  the same report and block. The name is the cat's: nobody types.

### 2. Pack for two (`pack`), 2 weeks on top of the prototype

- **Why.** It is the only idea here where the fun is thinking about what the other person has.
  "Leo's guitar" is a name on a list until it has to fit round your boots. It gives the two
  different halves of one thing, which the app has once (the story) and the research keeps
  pointing at.
- **First slice.** By turns across two phones: my three things packed is a record in the room;
  you fit yours and zip, or send it back. The suitcase of the day comes from the room's day and
  seed, so a pair can also each try it alone (27, If it fits, is this with all seven pieces in
  one hand). The ending card is kept: "Packed in one go, 14 November. Mochi came too."
- **Out.** A trip theme, more than one suitcase size, things bought in the shop as pieces.
- **Events.** `SuitcaseHandedOver`, `SuitcaseZipped` (detail: `snug` or `cat-on-top`),
  `SuitcaseSentBack`.
- **Works if** 60% of suitcases handed over are zipped within three days, and pairs that zipped
  one zip a median of two a week in weeks 2 to 4.
- **Kill if** under 30% are ever zipped, or more than half the zipped ones took three or more
  sendings back (it is a chore, not a puzzle).
- **Coins.** None.

### 3. Postcards from Mochi (`postcards`), 1.5 weeks

- **Why.** It is the one thing here for a person out in the world with a minute and one hand,
  and it is solo play whose whole point is the partner. It makes the cat a shared running joke
  about where each of them has been. Nothing in it needs the other to be awake.
- **First slice.** From "+": take or pick a photo, choose one of six poses, drag and pinch her
  into place, send. It arrives as a moment in a postcard frame, on the board and the partner
  widget. Poses are baked the way the splash hero is, in the pair's coat.
- **Out.** The 3D cat on a real surface (26), captions, a map of where she has been.
- **Events.** `PostcardSent`. A reaction to it is the existing photo reaction.
- **Works if** a third of active pairs send one in their first two weeks with it, and those send
  a median of two a week after.
- **Kill if** under 10% send a second.
- **Coins.** The photo note's existing 2, inside the `notes` cap: nothing new. A stamp on a
  postcard is the existing postage sink **(coins)**.
- **13 to 17.** A photo from one partner to the other exists today; no new surface.

### 4. Twenty sniffs (`sniffs`), 2.5 weeks

- **Why.** One partner's choice is the puzzle ("of course you picked the kettle"), and the
  asker gets an answer at once instead of waiting a day per question. It is the fastest turn of
  any two-person game here: set one in ten seconds, solve one in two minutes.
- **First slice.** 200 pictured things, each with the same 24 yes-or-no facts ("Is it alive?",
  "Would it fit in the box?", "Does she sit on it?"). The setter picks one and may add a nudge
  from chips ("you used it today"). The asker taps questions; she nods or shakes her head; a
  guess can be made at any time. One open riddle each way, one push, as Draw and guess.
- **Out.** The pair's own things as secrets (the room's furniture, list items), typed questions.
- **Events.** `SniffSet`, `SniffSolved` (detail: the number of questions, in ranges).
- **Works if** pairs that solved one set a median of five a week in weeks 2 to 4.
- **Kill if** under one a week, or more than a quarter are given up.
- **Coins.** None at first. If it must pay, a solve pays from `games` inside its cap, as a
  riddle does.
- **Cost that is not code.** The 200 by 24 table is three days of careful work and a second
  reader; a wrong fact is the only way this game can be unfair.

### 5. Music box (`music-box`), 2 weeks

- **Why.** The app is silent and nothing in it is made with the ears. A grid of five notes that
  cannot sound wrong lets anyone make something in a minute, and the second layer is the
  partner's. Then the room plays it: the vision's promise, "some of it was your partner's
  doing", as a tune.
- **First slice.** A sheet of eight steps by five notes; tap to set, it loops. Send it; the
  partner lays a second line in another voice over it. A finished tune is kept (ten at most on
  the shelf) and plays, quietly, when either taps the radio in the room. Sound is made by the
  phone from the notes, so there is nothing to record, store or moderate.
- **Out.** Echo (24), instruments, longer tunes, tunes on the widget.
- **Events.** `TuneLaid`, `TuneFinished`, `TunePlayed`.
- **Works if** half of first lines get a second line within three days, and finished tunes are
  played a median of three times each.
- **Kill if** under 20% get a second line, or sound is switched off by more than half of the
  pairs that tried it.
- **Coins.** None. Instruments could be a sink later **(coins)**.
- **Needs.** A radio in the room: the model is bundled and unsold, and standing it there is the
  Room owner's call.

### After the five

**One sheet** (8) is a week, because the live canvas is written: it should go to the first pair
who say they are long-distance. **Four paws** (3) is the funniest thing on the list for two
people on a sofa and cannot be judged without two people; prototype it after someone has played
the two that exist. **Lap time** (33) may matter more than any game to a pair apart, and it is
cheap. **White flag** (38) waits for the hug to arrive at all.

## 7. The two prototypes

Both are Labs only (`#if DEBUG || LABS_YES`), in Settings > Labs · Games beside Night raid, with
no server, no coins and no flag. Both are two people and one phone. The models import only
Foundation and the wire types, and are tested on the PC.

| | Fold and draw | Pack for two |
| --- | --- | --- |
| PR | #1021 (draft) | #1022 (draft) |
| Targets | `FoldInterface`, `FeatureFold` | `PackInterface`, `FeaturePack` |
| State | `FoldMachine`: drawing (top or bottom), folded, opened | `PackMachine`: packing (first or second), handover, closed |
| Tested | where a line is cut at the fold, the strip that shows, the name, every transition and every rejected event | 200 seeded levels each have a way to pack them, placing rules, "does the rest still fit", every transition and every rejected event |
| Walked | One round in a Simulator, by one agent: an empty top and a top that stops short of the fold are refused with a reason; the second sees only the strip; the sheet opened with both halves and the name "the Lesser Morfle" | One round in a Simulator, by one agent: a piece that sticks out or lies on another is refused with the reason; "Ask Mochi" answered both ways; zipped with the cat on the lid. "Send it back" was not walked, only tested |

**What they are for.** One question each, answered only by two people: is the reveal funny when
you did not see the top half; and does not knowing the other's shapes make you talk, or just
guess.

**What is rough.** No art: a suitcase is a grid and a thing is coloured squares with a name.
The creature's two inks are fixed. A piece is laid by tapping a square, not dragged. Neither
keeps anything when the screen closes. In Fold and draw the bottom lines were started by eye from
the strip and missed the top's ends by a few points: the pen should snap to a line end near the
fold. In Pack for two the first walk showed that a tap had to find the piece's corner square;
the piece now lies over the tapped square any way it fits.

## 8. What not to build

- **A daily puzzle with a streak.** The same puzzle for both is the good half of Wordle; the
  streak is the half its own players call pressure. If it fits has no count of days.
- **Trivia from a catalogue.** It runs out, it is the same for every couple, and Who knows who
  already asks 150 questions.
- **Anything with a clock on the other person.** No "answer within", no round that closes. (Who
  knows who closes at midnight today; that is the one place the app does this.)
- **A leaderboard, a rating or a "couple score" for any of it.**
- **Voice or sound recording, yet** (31, 32). Fun, and a new kind of personal data from people
  as young as 13. Not before `privacy.md`, storage and reporting are thought through.
- **Games that need location, health or the microphone to be on.** No step counts, no "how far
  apart are you" from GPS.
- **A game arcade.** Forty tiles in a grid is a shelf nobody reads. At most three or four games
  are offered at once, where they belong: drawing games by the canvas, the suitcase by the door.
- **Coins for any of it beyond the `games` cap that exists.**

## Evidence

Tags: **[B]** observational or company data; **[C]** practitioner, journalism or review text.
"Snippet": read as a search summary, the page not opened. No source is an experiment on a game
for couples. The evidence in the vision and the home document is not repeated.

### Short games people keep

- Wordle: one puzzle a day, the same for all; no push, no endless play, "three minutes a day";
  built for the author's partner [C, snippet]
  ([NPR](https://www.npr.org/2022/01/12/1071840091),
  [Game Developer](https://www.gamedeveloper.com/marketing/josh-wardle-reflects-on-the-the-unconventional-road-to-wordle-s-success)).
  Families share results in group texts and talk more [C, snippet]
  ([AARP](https://www.aarp.org/family-relationships/wordle/)). The once-a-day design is also
  reported as streak pressure by some players [C, snippet].
- The New York Times treats retention as the measure of its games, and subscribers who play
  more of them stay longer [B, snippet]
  ([Digiday](https://digiday.com/media/the-next-level-for-us-the-new-york-times-eyes-longer-play-sessions-for-games-in-subscription-drive/));
  Connections is sixteen words in four groups
  ([TechCrunch](https://techcrunch.com/2023/08/28/connections-is-the-new-york-times-most-played-game-after-wordle)).
- GamePigeon: reviewers like turns taken "when you have time" and the variety; they dislike
  first-mover advantage, games that take too long, and nothing new [C, snippet]
  ([App Store](https://apps.apple.com/app/gamepigeon/id1124197642)).
- Heads Up!: built for a television show in 2013, a word on the forehead and a tilt, each round
  filmed [C, snippet]
  ([AppSamurai](https://appsamurai.com/blog/mobile-app-success-story-heads-up/)).
- Tiny Wings: one touch, hills that are different every day, later a daily mode; 5.6 million
  sold by one self-taught author [C, snippet]
  ([Wikipedia](https://en.wikipedia.org/wiki/Tiny_Wings)).
- Monument Valley: every puzzle fits one screen; finished in about 90 minutes [C, snippet]
  ([The Ringer](https://www.theringer.com/video-games/2024/4/3/24119719/monument-valley-10-year-anniversary-ustwo-mobile-gaming-apple-ios)).
  Gorogoa: the player's one lever is where to look; limits made the puzzles better [C, snippet]
  ([Game Developer](https://www.gamedeveloper.com/design/how-rigid-design-limitations-improved-i-gorogoa-i-s-puzzles)).
- Draw Something: about 14.3 million daily players in April 2012, 10.4 million a month later;
  the reasons given are commentators' theories [B, snippet]
  ([The Week](https://theweek.com/articles/475789/draw-somethings-disastrous-month-3-theories-behind-slump)).

### Games built on two heads

- Gartic Phone and Broken Picture Telephone: the comedy is the drift between a drawing and its
  caption [C, snippet]
  ([Know Your Meme](https://knowyourmeme.com/editorials/guides/what-is-gartic-phone-and-why-do-streamers-love-it-the-multiplayer-drawing-game-explained),
  [Wikipedia](https://en.wikipedia.org/wiki/Broken_Picture_Telephone)).
- Keep Talking and Nobody Explodes: one has the bomb, the others the manual [C, snippet]
  ([Stuff](https://www.stuff.tv/app-reviews/keep-talking-and-nobody-explodes/review)).
- The Mind: cards played in order with no talking, "a cooperative game that doesn't allow
  cooperation"; Wavelength: one clue for a hidden point between two opposites [C, snippet]
  ([Game Informer](https://gameinformer.com/column/top-of-the-table/2018/09/07/the-mind-a-cooperative-game-that-doesnt-allow-cooperation),
  [Wikipedia](https://en.wikipedia.org/wiki/Wavelength_(game))).

### Couples

- Devasia, Rodriguez, Tuttle and Kientz, "Partnership through Play: Investigating How
  Long-Distance Couples Use Digital Games to Facilitate Intimacy", DIS 2025: a diary study and
  interviews with 13 long-distance couples who play at least weekly [B]
  ([arXiv](https://arxiv.org/abs/2505.09509)). The first third of the page was read; the
  findings used above (cooperation in most sessions, presence, physical closeness least served,
  lost memories) come from a machine summary of the rest and should be checked before they are
  quoted anywhere else.
- Paired: one free question or quiz a day, answers hidden until both are in; Lovify: answer
  about yourself, then guess your partner's; Candle: one-minute daily games, a thumb kiss,
  photo prompts; Coupletition: three free rounds a day and a streak [C, snippet]
  ([Paired](https://apps.apple.com/app/id1469609343),
  [Lovify](https://apps.apple.com/us/app/lovify-couple-questions-game/id1645893544),
  [Candle](https://apps.apple.com/us/app/6743355635),
  [Coupletition](https://apps.apple.com/app/id6758271057)). No retention figure was found for
  any of them.
- Lists of "games for long-distance couples" lead with Words With Friends and classic board
  games by turns [C, snippet]
  ([Plarium](https://plarium.com/en/blog/best-games-for-couples-online-in-2026-play-together-anywhere/)).

### Cozy

- Pets that take kindness "without punishment or expectation" are a source of coziness [C,
  snippet] ([Kitfox](https://medium.com/kitfox-games/designing-for-coziness-d33d2519a59e)).

### Not found

How long anyone plays a two-person phone game; how often a pair on one sofa picks up one phone
together; any retention figure for a couples game; any study of a game played after an
argument; any account of why GamePigeon's games are the ones that lasted.

### Code read

`packages/ios/features` (FeatureGames, FeatureCanvas, FeatureRaid, FeatureMischief,
FeatureSchool, FeatureStory, FeatureUs, WidgetBridge, WidgetUI), `packages/ios/core`
(`Machine`, `Store`, `SeededRandom`, `SessionMeter`), `packages/ios/pet` (`CatPlay`),
`apps/ios/Nooki` (UI/Raid, UI/Draw, UI/Settings/LabsSections, Room/Games),
`packages/contracts/domain` (`coins.ts`, `metrics.ts`), and the docs linked above.
