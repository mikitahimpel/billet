# Draw-guess

One partner draws a word, the other guesses it from a set of letter tiles. The concept, with the
screens, is [apps/ios/docs/draw-guess-concept.md](../apps/ios/docs/draw-guess-concept.md). This page
is what the server and the contracts do.

## The riddle

- The drawer sends a **riddle**: the drawing (its PNG through `POST /v1/media`, and its compact
  strokes), and the word they chose. The partner is the **guesser**.
- A word is its own: no catalog route. The server trims it and lowercases it; it must then be
  lowercase a to z, single-spaced, at most 24 characters and at most 12 letters
  (`RiddleWord` in `packages/contracts/domain/src/riddle.ts`). Anything else is 400.
- Each member has at most one open riddle. A second send while the first is open is 409, so the
  guesser's queue never grows past one per partner. The same riddle id sent again answers with the
  riddle already stored.
- The guesser sees the word's `shape` (letters per word, "north pole" is `[5, 4]`) and the
  **tiles**: the word's letters and random decoys, shuffled, 12 in all, or letters + 2 for words of
  11 or 12 letters. The room makes them from the riddle id, so they are the same on every read.
- The word is sent to the drawer always, and to the guesser only once the round has ended.

## Playing

- **Tries** are unlimited and counted. Each carries its own idempotency `key`: a retry with the
  same key answers as the first time did and counts nothing, even after the round has ended. A try
  is normalised like the word, so " Cat " solves "cat".
- **Hints**, from Mochi: the first takes away half the decoys. Each later hint shows one letter in
  its place, up to all letters but one. Past that, a hint is 409. Which tiles and letters follows
  the riddle id and the hint's number.
- **Give up** ends the round and shows the word.
- The drawer cannot try, hint or give up their own riddle (409), and nothing plays an ended one
  (409). A riddle that does not exist is 404.

## Series and rewards

- The pair's **series** counts solves in a row. It resets to 0 only on a give-up; `best` keeps the
  longest run.
- The room journals `GamePlayed{game: "draw-guess", score, won}` for the guesser when a round ends,
  in the same transaction as the riddle, its try and the series. A solve pays
  max(4, 10 − 2 × hints) coins; a give-up pays 3. For draw-guess, `rewardFor` pays the event's
  `score`; other games keep 10 for a win and 3 otherwise. The games cap of 40 a day applies.
- A client `GamePlayed` for draw-guess is refused (`RoomJournalsGame`, 400), so the coins cannot
  be paid twice.

## API

| Route | Body | Answer |
| --- | --- | --- |
| `GET /v1/riddles` | | `{open, ended, series, best}`: `ended` is the last 20, newest first |
| `POST /v1/riddles` | `{id, word, compact, image}` | the riddle |
| `POST /v1/riddles/:id/guess` | `{key, guess}` | `{riddle, right}` |
| `POST /v1/riddles/:id/hint` | | the riddle |
| `POST /v1/riddles/:id/give-up` | | the riddle |

Refusals are 409, a missing riddle 404, a bad word 400. Every answer is `cache-control: no-store`.

## Realtime and pushes

- A socket that resumes with `riddle: true` gets `RiddleChanged{riddle}` for each open riddle, then
  one on every send, try, hint and give-up, as that member sees it.
- Two pushes on the APNs lanes, with thread-id `draw-guess`: `partner.riddle` to the guesser when a
  riddle arrives ("Your partner drew you a riddle. 4 letters."), and `partner.riddle_solved` to the
  drawer when it ends ("Your partner guessed “cat” on the 2nd try 🎉" or "Your partner gave up on
  “cat”"). The server knows no names, so the text says "Your partner".

## Where it lives

- Rules: `packages/backend/pair-room/src/riddle-rules.ts` (pure) and `riddle.ts` (the room's
  commands). Writes go through `RoomStore.commit` as `SaveRiddle`.
- Storage: the room's SQLite tables `riddles`, `riddle_guesses` and `riddle_series`.
- Routes: `packages/backend/notes/src/riddle-routes.ts`.
- Swift: `Wire/Riddle.swift`, `Routes`, and the `APIClient` methods `riddles`, `sendRiddle`,
  `guessRiddle`, `hintRiddle` and `giveUpRiddle`. `WebSocketDependencies.followsRiddle` adds
  `riddle: true` to each resume.

## Not yet

- English words only.
- No feature flag, no widget and no Inbox lines of its own. The existing game-played Inbox row
  shows a finished round.
- No live mode where the guesser watches the drawing appear.
- The demo partner does not draw or guess.
