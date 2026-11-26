# What makes the cat read as alive

Notes behind the Labs switch **Lively cat** (`labs.livelyCat`), for the splat cat of the Nooki rooms
(`CatWalker`, `CatBehavior`). The model is `packages/ios/pet/Sources/Pet/Alive`; the Mac harness
that plays and measures it is `tools/cat-motion`.

## What a real cat does

A cat that sits and does nothing still reads as alive, and a rigged one with ten idle animations
often does not. What the animal does, as the standard texts describe it (Bradshaw, *The Behaviour
of the Domestic Cat*; Turner and Bateson, *The Domestic Cat*; Leyhausen, *Cat Behavior*) and as
any footage of a house cat hearing a noise shows. The timings below are rough figures to design
by, not measurements:

1. **One attention, spread over the body in a fixed order.** A sound turns one ear first, in about
   a tenth of a second, the ear on its side and alone. Only something worth it gets the head, a
   quarter of a second later and fast, with a blink on a big turn. The chest follows the head after
   about a second, the body only if she decides to go there. Most sounds get an ear and nothing
   more.
2. **Stillness is the signal.** While she listens or stares she freezes: no weight shifts, no tail
   wave. The one thing that moves is the tip of the tail, in short bursts. A model that sways all
   the time never looks like it is paying attention to anything.
3. **Bursts and holds, not a steady rhythm.** Head moves are quick and far apart. The gaps are
   mostly a few seconds and now and then much longer; a uniform 2–5 s reads as a loop.
4. **She gets used to things.** The first time something moves she looks. The fourth time in a
   minute it gets an ear.
5. **She looks at things that are there.** The window, the bowl, the person, the thing that just
   moved; rarely at an empty wall.
6. **Intent shows before the move.** Before she gets up to go somewhere she looks at it, ears
   forward, leans a little, and then gathers herself. On arriving she does not sit at once: she
   stands, looks about, then turns and sits.
7. **On her feet she is still a head and two ears.** Walking, the head keeps looking at things and
   the ears keep working; only the legs are busy.
8. **Arousal ties it together.** Anything noticed wakes her a little: the next looks come sooner and
   the head moves faster. Left alone she calms over a quarter of a minute.

## What the app had

`CatBehavior` drew a glance direction at random every 2–5 s, a phantom sound every 6–16 s, a look
at the camera every 6–14 s, each on its own timer, and none of them changed the others: the tail
waved through a stare, a sound never interrupted a glance in any order, and nothing in the room was
ever looked at except the camera. Up from sitting she was head noise and fixed ears until she sat
again. Sent somewhere, she stood up the frame she was told to.

## What the switch changes

- `CatAttention` (a `Machine`): `free → pricked → watching → releasing`. A heard thing pricks the
  ears first and turns the head only from a salience of 0.4; a seen thing turns the head at once.
  A new thing takes her off what she watches only if it matters 1.25 times more than what is left
  of her interest, which halves over the hold.
- `CatNoticing`: feeds the machine. It keeps how used she is to each source (each meeting takes
  35 % of what is left, forgotten over 90 s), an arousal that rises with what she notices and
  settles in 15 s, and when nothing happens chooses her next look from what stands in the room,
  weighted, with the last two looked at a quarter as likely. Gaps are log-normal about 5 s,
  shorter the more awake she is and longer when drowsy, and now and then one look follows another
  at once. It is seeded: the same seed and calls give the same cat.
- `CatRegard` is what it asks of the body each frame: head, each ear, how much the chest follows,
  a lean, how still she holds, how quick the head is, the tail tip's twitch, a blink.
- `CatBehavior` takes the regard in place of its random glances, sounds and checks. The rest of it
  (yawn, wash, pet, blinks, the tail's wave, a finger) is as it was, scaled down by her stillness.
- `CatWalker`: before a trip she looks at where she is going for 0.55–1.2 s (`CatPace.regard`),
  then gets up; arrived, she looks about for 0.9–1.8 s (`survey`) before she turns to sit; on the move her head
  and ears take the same attention within a narrower neck. The eager pace of the games does
  neither.
- `CatDirector` tells her what stands in the room (her spots, weighted) and how curious she is,
  and reads the switch four times a second.

- `CatFidgeting` chooses her small acts (an ear flick, a flick or curl of the tail's tip, a slow
  blink, a head tilt, a shake, a yawn, a wash, a shift of weight, a sigh) in place of a timer each:
  weighted by how awake, sleepy and content she is, each with a least rest before it comes again,
  the last two a fifth as likely, none while something holds her still, and one soon after she lets
  go of a stare. Having just sat down she most often sighs: a deep breath, lids lowering as it goes
  out. When the brain directs her it keeps the larger acts (yawn, wash, shake, tilt) for itself.

What catches her eye today: whoever watches (on first sight, and when the camera moves more than
0.3 rad about her within 2 s), the room's spots, the partner arriving, where the brain has her
look, where she is about to go, and noises of her own.

## Measuring it

```sh
tools/cat-motion/run.sh off idle errand
CAT_LIVELY=7 tools/cat-motion/run.sh on idle errand
tools/cat-motion/compare.sh off on
```

`idle` is a minute and a half of her sitting with the partner coming in, the camera turned round
her twice and a pet; `errand` sends her across the room and home. The report's attention lines:
head turns a minute and their peak speed, the holds between them, how many turns an ear led, how
much of her rest the head is held still and whether an ear or the tail tip moves in those holds,
and per errand the time and head travel before she stirs and between her last step and sitting.

## Next

- More idle acts to choose from (stretch, knead, loaf variants).
- The tail as a mood barometer: carried high on a greeting, low on a stalk, lashing when cross.
- Gaits by intent (stroll, trot, stalk), and pauses mid-walk with a paw lifted.
- Turning her seat toward something that stays behind her.
