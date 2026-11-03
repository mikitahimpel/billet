# The cat's brain

The cat decides what to do with one hierarchical state machine, in
`packages/ios/Sources/Pet/Brain`. It is pure Swift with no scene in it: a scene asks it for a
frame (the state stack, a clip, where to go and where to look) and plays that with the cat's own
clips.

## Regions

Four regions run side by side.

- **Vitality**: awake, drowsy, asleep, one neighbour at a time, with a 12 s dwell. It follows the
  needs engine's sleep pressure (`rhythm·s(h) + tiredness·(1 − Rested)`): drowsy above 0.55,
  asleep when the life says so or while curled up for a nap.
- **Activity**: ten groups of steps (Idle, Explore, Rest, Groom, Eat, Play, Watch, Social, Mischief,
  React). Entering a group plays one of its scripts, such as Rest = find a nap spot, knead, curl,
  wake. When a script ends, utility chooses the next group. React is only entered by events: a
  note sends the cat to carry it to the wall (CarryNote), waking it first if it is curled up.
- **Interaction**: Petted(zone), Held, Toy(kind), Called, Fed, FollowFinger, Greeting, Batting.
  It overrides the
  activity while active, and the activity comes back from its **history** afterwards: a nap
  briefly petted goes on to the end it had.
- **Reflex**: blinks, ear twitches, tail flicks, breath and head tracking. Each is a pure function
  of the time and the seed on a 4 s grid, with no state.

Every move is checked against the chart (`CatStatechart.isLegal`): steps follow their scripts,
groups are entered at their entry steps, vitality never skips drowsy.

## Choosing an activity

Each group's score is

```
score = base × need × personality × time of day × room × novelty × mood × vitality
```

- **need**: `0.5 + 4·(1 − n)²` for the need the group answers (Rest → Rested, Eat → Full, Play and
  Mischief → Playful, Social → Loved), ×1.5 for the need `NeedFocus` holds.
- **personality**: `Π (1 + wᵢ·(2·tᵢ − 1))` over the traits that lean on the group.
- **time of day**: play and mischief peak at dawn and dusk; rest peaks after midday.
- **room**: no window, no Watch; Mischief needs something to nudge, a heap of clothes or a desk;
  a sunbeam (by day, under the window, in clear weather) and something soft make Rest likelier;
  a piece placed in the last day makes Explore twice as likely, and the cat inspects it.
- **novelty**: `Π (1 − 0.6·e^(−age/240 s))` over the recent episodes of the same group.
- **mood**: a happy cat plays and explores more; a low one rests more and still seeks company.
- **vitality**: asleep, only Rest; sleepy, Rest ×3 and the lively groups ×0.2.

The next group is drawn by softmax over log scores with temperature 0.35. A group in play is cut
short only by one scoring 1.6 times better, and only after its minimum dwell.

## Personality

Six traits from 0 to 1: curious, lazy, cuddly, playful, bold, vocal. They are drawn from the pet's
seed in 0.15…0.85, so every cat is someone, and two cats in the same room behave differently.
The app makes no sound: a vocal cat shows itself by perking up and seeking company.

Experience moves them a little. At each day start the traits are the born ones moved by the last
six days of events, each weighted by `e^(−age/3 days)`: games make the cat more playful and less
lazy, pets more cuddly, notes more vocal and a little more curious, and any care a little bolder.
No trait moves more than 0.15 from where it was born, and a week without a game sends it back.

## Memory

- **Favourite spots**: seconds curled up or kneading at each kind of spot, with a minute for each
  pet there. A nap spot it is fond of is up to four times likelier, and Rest scores up to 1.3 times
  higher when one is in reach.
- **Yesterday**: a day starts with yesterday's spots at half strength. Yesterday is not carried
  from the phone's own run but rehearsed: the brain replays the previous day from its canonical
  start with no memory (about 20 ms) and keeps what that rehearsal did. So a phone that just
  launched remembers exactly what one that ran all week remembers, and anything older than two
  days is gone.
- **Who was last**: the partner whose event came last, and how long the other has been away
  (Social and Watch wait for a partner away 12 hours).
- **Recent toys**: the toys this phone's finger played with, shown in the overlay and never
  folded, as the live touch is.

## Brain debug

**Brain debug** in Labs (The cat) puts a card on Home: the state stack, the
five best scores at the last choice with their factors (`n` need, `p` personality, `t` time, `r`
room, `b` boredom, `m` mood, `v` vitality), the last ten moves with their causes, today's traits
with arrows where experience moved them, the favourite spot, and the ×1, ×60 and ×600 clock.

## Determinism and sync

The brain is a pure function of the life events, the time and the seed:

- Decisions fall on a 0.25 s grid of absolute time, and every random draw comes from
  `BrainDice.roll(seed, time, salt)`, a hash with no state. However a phone got to a moment, the
  draw there is the same.
- The needs come from `PetLife.state`, sampled every 15 minutes and at each event.
- Each local day starts at 04:00 from a canonical state (asleep in its nap spot, or sitting), and
  nothing the trajectory learned crosses that line. A fresh replay from 04:00 equals a phone that
  has run all week. A full day's replay takes about 20 ms in a release build.
- `CatBrainRunner` keeps a checkpoint every 5 minutes of brain time for the last two hours. An
  event that arrives late, such as the partner's, sends it back to the checkpoint before the event
  and forward again.
- This phone's own touch is an overlay over the interaction region. It never changes the fold, so
  the phones agree again as soon as the touch ends.

Two phones agree when they hold the same events, room and seed. The room is each phone's own
choice of room, furniture and window view; a pair with different rooms sees different cats.

Between decisions, `advance(to:)` is one comparison and a frame allocates nothing.

## Rules that stay

The cat never dies, is never sick, never guilts or sulks, and is never punished. Mischief is cute:
a mug is nudged towards the edge, never off it. The touch router still decides what a touch is.

## In the room

The brain is always on, and so are the cat's needs: there is no switch for either. Home runs a
`CatBrainModel` beside the life model and hands each frame to the scene in `PetPlayState.brain`.
The styled rooms (`GenzCatBrain.swift`) carry it out:

- **Affordances** come from the room as it stands, after decorating: a bed, a box, a shelf,
  something soft (cardigan, hoodie, jumper), a small item (mugs, phone, candles), a rug, the window,
  the bowl and the toys. Whatever stands on the top the cat lives on is in reach. The rest can be
  looked at: a moved piece out of reach is inspected from the nearest edge. The scene reports
  them up as `PetSceneEvent.affordances` with the weather outside.
- **Body**: the cat walks (or runs, for a chase or zoomies) to where the step wants it, then plays
  the step's clip through the model's clip lookup and stand-ins. A one-shot that is shorter than
  its step repeats with a rest in its base pose (groom, knead, eat, bat), or holds its base. A
  blink or a tail flick cuts into the calm steps.
- **Gaze**: the head follows the step's gaze (the camera, out through the window, the mug it is
  about to nudge, or a slow sweep for looking around) unless a finger has it.
- Touch, games, the bowl, lifting and calls keep their own handling. The scene reports what this
  phone's touch is doing as `PetSceneEvent.touching`, which the brain shows in its interaction
  region without changing the fold.
- At ×60 or ×600 on the debug clock the body jumps to each place instead of walking, so a day
  reads as a time-lapse.

### Moments

What used to be five Labs switches is part of the brain, in the styled rooms and the Nooki room:

- **Carries the note**: a note puts the brain in React's CarryNote, and the room plays the cat
  carrying the note in its mouth to the wall or the glass and taping it up.
- **Purrs**: stroking purrs under the finger with hearts, a long pet rolls it over. It is the
  Petted interaction.
- **Bats at your finger**: only a finger *resting* near the edge (still within 8 pt for 0.35 s),
  so a quick swipe to turn the room is never batted at, and only by a cat in the mood: awake, not
  napping or eating, and `½·urgency(Playful) + ½·playful trait ≥ 0.4`. A playful cat nearly
  always is, an even one once its Playful need is below about half, a lazy one rarely. It shows
  as the Batting interaction and counts as a game. A rest lapses after 6 s.
- **Greets you**: back after 3 hours or more away, an awake cat runs up to the glass and
  headbutts it (the Greeting interaction). A sleeping cat lets it go.
- **Chases**: only when Play chooses a chase or zoomies; the room sends the cat after the lamp's
  dot of light (the yarn in the Nooki room). There is no fixed 45–90 s clock any more.

### Clips

| Step | Clip | Composed or standing in |
|---|---|---|
| Sit, find nap spot, wait by door, sit in cardigan, sit on desk | sit | |
| Loaf | loaf | sit on the low-poly cats |
| Look around | sit | head sweeps side to side |
| Wander, sniff object, inspect furniture, walk to bowl, bring toy | walk, then sniff | no carry clip |
| Knead | knead | repeats |
| Curl | lieDown, then sleep | lieDown only when it comes from standing or kneading |
| Wake | stretch | |
| Groom paw, flank, tail | groom | one groom clip for all three |
| Eat | eat | repeats |
| Lick lips | happy | no lick clip |
| Stalk | crouchWiggle | |
| Pounce | pounce | |
| Chase, zoomies | run at the clip's own speed, then perk or happy | a fast walk on the low-poly cats |
| Bat object, push item | bat | |
| Watch window | sit | head out through the glass |
| Watch partner's window | slowBlink | |
| Seek you | walk, then perk | |
| Rub | headbutt | no side rub |
| Slow blink | slowBlink | |
| Startle, curious tilt | perk | no startle or tilt |

### Clips wanted

For the Detailed and Hero cats, in order of what shows most. Loaf, run and lieDown landed in
#190 and are in use; the rest are coming.

1. **loaf**: lying with the paws tucked under, eyes open, slow breath (loop, base sleep-low).
2. **run**: a trot-to-gallop loop for chase and zoomies (walk at ×3 reads as skating).
3. **lieDown**: from standing, a turn and settling into the curl (one-shot, stand → sleep). The
   cross-fade from sit to sleep is the weakest moment of a nap.
4. **groomFlank** and **groomTail**: licking the side, and the tail held in the forepaws.
5. **lickLips**: a quick tongue flick after eating (one-shot, sit, about 1 s).
6. **startle**: an arched back and a small hop back (one-shot, stand).
7. **headTilt**: a curious tilt of the head to one side, ears forward (one-shot, sit).
8. **carry**: walking with a toy in the mouth (loop, stand), for bringing a toy.
9. **rubSide**: rubbing the cheek and flank along something (one-shot, stand).
10. **lookUp**: sitting and watching something high, the head well back (loop, sit), for birds
    and snow. The head turn stops at 0.45 rad up.
11. Additive layers on masked joints: **blinkLayer**, **earFlick**, **tailFlickLayer**, **breathe**.
    Reflexes now cut in as whole clips and only in calm steps.
12. **jumpDown** and **jumpUp** for the seat: the cat bed on the rug is out of reach until then.

## Statechart

```mermaid
stateDiagram-v2
  state CatBrain {
    state Vitality {
      [*] --> Awake
      Awake --> Drowsy : sleep pressure
      Drowsy --> Awake : rested
      Drowsy --> Asleep : night or nap
      Asleep --> Drowsy : wakes
    }
    --
    state Activity {
      state Choose <<choice>>
      [*] --> Idle
      state Idle {
        [*] --> Sit
        [*] --> Loaf
        [*] --> LookAround
        LookAround --> Sit
        Sit --> LookAround
        Sit --> [*]
        Loaf --> [*]
        LookAround --> [*]
      }
      state Explore {
        [*] --> Wander
        [*] --> InspectFurniture
        InspectFurniture --> SniffObject
        Wander --> SniffObject
        Wander --> [*]
        SniffObject --> [*]
      }
      state Rest {
        [*] --> FindNapSpot
        Curl --> Wake
        FindNapSpot --> Curl
        FindNapSpot --> Knead
        Knead --> Curl
        Wake --> [*]
      }
      state Groom {
        [*] --> GroomPaw
        [*] --> GroomFlank
        GroomFlank --> GroomTail
        GroomPaw --> GroomFlank
        GroomPaw --> [*]
        GroomFlank --> [*]
        GroomTail --> [*]
      }
      state Eat {
        [*] --> WalkToBowl
        Eat --> LickLips
        WalkToBowl --> Eat
        LickLips --> [*]
      }
      state Play {
        [*] --> Stalk
        [*] --> Chase
        [*] --> BatObject
        [*] --> Zoomies
        Chase --> Pounce
        Pounce --> Chase
        Stalk --> Pounce
        Pounce --> [*]
        Chase --> [*]
        BatObject --> [*]
        Zoomies --> [*]
      }
      state Watch {
        [*] --> WatchWindow
        [*] --> WatchPartnerWindow
        WatchWindow --> [*]
        WatchPartnerWindow --> [*]
      }
      state Social {
        [*] --> SeekYou
        [*] --> SlowBlink
        [*] --> BringToy
        [*] --> WaitByDoor
        SeekYou --> Rub
        SeekYou --> SlowBlink
        Rub --> [*]
        SlowBlink --> [*]
        BringToy --> [*]
        WaitByDoor --> [*]
      }
      state Mischief {
        [*] --> PushItem
        [*] --> SitInCardigan
        [*] --> SitOnDesk
        PushItem --> [*]
        SitInCardigan --> [*]
        SitOnDesk --> [*]
      }
      state React {
        [*] --> Startle
        [*] --> CuriousTilt
        [*] --> CarryNote
        Startle --> [*]
        CuriousTilt --> [*]
        CarryNote --> [*]
      }
      Idle --> Choose : script ends
      Explore --> Choose : script ends
      Rest --> Choose : script ends
      Groom --> Choose : script ends
      Eat --> Choose : script ends
      Play --> Choose : script ends
      Watch --> Choose : script ends
      Social --> Choose : script ends
      Mischief --> Choose : script ends
      React --> Choose : script ends
      Choose --> Idle : utility
      Choose --> Explore : utility
      Choose --> Rest : utility
      Choose --> Groom : utility
      Choose --> Eat : utility
      Choose --> Play : utility
      Choose --> Watch : utility
      Choose --> Social : utility
      Choose --> Mischief : utility
      note right of React : any step jumps here on a note or a startle
    }
    --
    state Interaction {
      [*] --> None
      None --> Petted
      Petted --> None : ends, activity resumes from history
      None --> Held
      Held --> None : ends, activity resumes from history
      None --> Toy
      Toy --> None : ends, activity resumes from history
      None --> Called
      Called --> None : ends, activity resumes from history
      None --> Fed
      Fed --> None : ends, activity resumes from history
      None --> FollowFinger
      FollowFinger --> None : ends, activity resumes from history
      None --> Greeting
      Greeting --> None : ends, activity resumes from history
      None --> Batting
      Batting --> None : ends, activity resumes from history
    }
    --
    state Reflex {
      Blink
      EarTwitch
      TailFlick
      Breathing
      HeadTracking
    }
  }
```
