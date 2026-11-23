# Cat school: tricks, stars and routines

The first slice of concept C in the gameplay vision (`docs/gameplay-vision.md`, PR #1010): the two
teach the cat tricks, ask for them, and send each other a routine that plays in the other's room
as it went. Behind the `cat-school` flag, off by default.

## What a pair sees

- **Where it lives.** One pill, "Tricks", in the care sheet (tap Mochi's portrait on Home), shown
  only when the flag is `on` and the pair is paired. Home gains no control. The school is a sheet
  that fits its content, so the room and the cat stay in view above it.
- **The tricks.** Four, each one a move the cat's body already had: Spin, Jump, High five and Bow.
  Each has zero to three stars, shared by the pair, and shows who taught it first.
- **A lesson.** "Teach" (or "Practise") starts a lesson for the next star. It is five rounds of a
  small timing game, and three good ones earn the star. A mark runs along a bar; a tap on "Now!"
  while it crosses the lit part is a good one, and the cat does the trick. Otherwise the cat yawns,
  washes, tilts its head or shakes. Each trick has its own rhythm: Bow is slow with its moment at
  the end, Jump is quick and sharp, Spin has two beats, and High five's moment moves every round.
  A higher star narrows the lit part. A lesson that falls short loses nothing.
- **Asking.** "Ask" has the cat do a trick it knows: half the time at one star, three times in four
  at two, always at three. The rest of the time it does something else.
- **A routine.** "Make a routine" strings three to five known tricks. "Try it" plays the take in
  the room, each trick landing or not by its stars. "Send" keeps that take in the pair's room.
- **The partner's routine.** When the partner has sent one, the sheet says so and "Watch it" plays
  the same take, flubs included, in this phone's room.

## The kind rules

- **Nothing is lost.** A star never goes away, a failed lesson costs nothing, and no trick is
  forgotten for lack of practice.
- **Nothing is counted against anyone.** No timer, no daily limit, no streak, no ranking, no score
  compared with another couple.
- **Nothing is sold.** No star, lesson or trick has a price, and the school pays no coins, so the
  daily budget in `docs/economy.md` is unchanged.
- **No push.** A routine waits in the sheet until the partner opens it.
- **No text.** The school stores ids and times only; nothing a person types.

## How it works

| Part | Where |
| --- | --- |
| Contracts | `packages/contracts/domain/src/school.ts`, `packages/contracts/http-api/src/school.ts` |
| Rules | `packages/backend/pair-room/src/school.ts`: `decideLesson`, `routineIsKnown`, `SchoolRoom` |
| Storage | the pair's Durable Object: `school_tricks` (one row a trick), `school_routines` (one row a member) |
| Routes | `GET /v1/school`, `POST /v1/school/lessons`, `POST /v1/school/routines` |
| App logic | `packages/ios/features`: `SchoolInterface` (tricks, plan, book), `FeatureSchool` (`LessonMachine`, `RoutineMachine`, `SchoolMachine`, the store) |
| App screens | `apps/ios/Nooki/UI/School` |
| The cat | `RoomControlling.school(_:)` to `CatDirector.school(_:)`, which holds the cat's own plans for four seconds |

Server rules:

- A star is earned one at a time: a lesson for star `n` is taken only when the trick has `n - 1`.
  A star already held changes nothing, so a retry is safe; a skipped star is refused with 400.
- Either partner can earn any star. The first teacher stays the trick's teacher.
- A routine holds three to five steps, each a trick the cat knows; it replaces the member's last.
- Leaving the pair deletes the school with the rest of the room.

The phone decides whether a round was a hit and whether a trick landed; the server checks only
the order of stars. Stars buy nothing, so there is nothing to gain by lying about them.

## Events

| Event | Detail | When |
| --- | --- | --- |
| `TrickTaught` | the trick's id | the room took a star |
| `TrickDone` | the trick's id | the cat did a trick it was asked for |
| `RoutineSent` | none | the room took a routine |

## Measuring it

From the gameplay vision: it works if half of the pairs that taught one trick reach a second star
within two weeks; stop if under a fifth teach a second trick. Time in the app is read from
`SessionEnded`. The thresholds are judgment, to be moved once a baseline exists.

## Not in this slice

- Each partner as the only teacher of a trick until its third star.
- The monthly show, judges, ribbons and classes.
- Depth for the four mini-games.
- A reaction from the partner to a routine, and a routine on the widget.
- New animation: the four tricks reuse moves the cat had.
