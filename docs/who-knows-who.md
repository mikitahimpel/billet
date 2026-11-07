# Who knows who

A daily guessing game for the pair. One partner answers five questions about themselves, the other
guesses, and nobody sees a thing until both are done. Then the answers open together and the cat
keeps score.

It exists for two reasons. It gives the pair a reason to open the app every day, and each question
deck doubles as a TikTok carousel ("5 questions your partner will get wrong about you"). The app
holds what a carousel can't: hidden answers, the reveal and a running score.

## The round

- One round a day per pair, five questions, all about one partner: the **subject**. The other
  partner is the **guesser**. The subject switches every day, so on Monday it is "about Mia" and on
  Tuesday "about Leo".
- The day is the room's day, in the time zone the room already uses for coins.
- Each question has four options. The subject picks the true one and the guesser picks a guess.
  There is no free text: options keep the score unarguable and a round takes about a minute.
- Either partner can go first. Answers lock once chosen.
- When both have answered all five, the round **reveals**: questions open one by one, showing the
  subject's answer, the guess, a hit or miss, and the cat's reaction.
- A round left half done closes at the end of the day without a score. The next day starts a fresh
  round about the other partner.

## Questions

- A server catalog like the date catalog: `packages/backend/guess/src/question-catalog.json` with a
  `version`, served to the app and bundled in the build as a fallback.
- One question: `id`; `guess`, the guesser's text with a `{name}` placeholder for the subject ("What
  does {name} order at a restaurant they've never been to?"); `self`, the same question to the
  subject in the second person; four `options`, worded so they read right to both partners; and a
  `tag` (`food`, `habits`, `past`, `music`, `money`, `us`, `dreams`, `quirks`).
- The first deck is about 150 questions, written to be funny, specific and safe to show on a
  carousel. No spicy deck in v1.
- The room picks the five questions for each round from a seeded order, so both phones get the same
  ones, and a question does not come back until the pair has seen the whole deck.

## Score

- One point to the guesser for each hit. The subject scores nothing for being guessed.
- The week runs Monday to Sunday in the room's time zone. The weekly score is shown as
  "Mia 31 · 12 Leo" and resets on Monday. The all-time score and the best week are kept.
- The stake is a line under the weekly score: "loser plans Friday's date", which opens Date Night.
  v1 shows it and does nothing else with it.

## Rewards

- Coins go through the room like every other earning (#428): two new `EarnEvent` cases,
  `guessHit(round:question:)` for each hit and `roundPlayed(round:)` once both partners finish a
  round. The amounts are server-side, at the same level as `dateMatched`. Each ref earns once.
- When the streak rules land (#20), a played round counts as something done together.

## Notifications

- When one partner finishes their part, the other gets one push through the existing APNs lanes,
  with its own `thread-id` like Pick tonight: "Mia answered 5 questions about herself. Your turn to
  guess" or "Leo guessed 5 things about you. Answer to see how he did".
- The reveal is not pushed. It waits in the app, where the moment happens.

## Server

The room decides, like Pick tonight (`packages/backend/pair-room/src/pick-tonight.ts`).

- **Room state:** the round (`day`, `subject`, `questions`), one answer row per member and question
  (`member`, `question`, `option`, `at`), and the weekly and all-time tallies.
- **Hidden answers:** until both partners have answered the whole round, the room never returns the
  other partner's choices. It returns only a count ("Mia answered 5 of 5"). This is the rule the game
  stands on, and it lives on the server, not in the app.
- **Routes,** in `packages/contracts/http-api`:
  - `GET /v1/guess`: today's round, the caller's own answers, the partner's progress, the reveal once
    both are done, and the week's score.
  - `POST /v1/guess/answers` `{ round, question, option }`: locks one answer. A second answer to the
    same question is rejected.
  - `GET /v1/guess/catalog`: the question catalog, public and cached, the same shape as the date
    catalog.
- **Realtime:** a partner's progress and the reveal reach the other phone through the room socket, so
  the reveal appears without a refresh.

## App

- **Entry:** a "Who knows who" card on the Us tab, between Date night and the Wishlists. It shows
  today's state: "Answer 5 about yourself", "Guess 5 about Leo", "Waiting for Mia" or "Results are
  in". It also shows the weekly score.
- **Round screen:** one question at a time with four option buttons, a progress bar (1 of 5) and the
  subject's avatar. It reads "about Mia" for the guesser and "about you" for the subject.
- **Waiting:** the cat waiting by the phone, with the partner's live progress.
- **Reveal:** questions open one at a time: the subject's answer, the guess, a hit or miss, and a cat
  reaction (happy on a hit, a dramatic flop on a miss). Then the round score, the week score and the
  coins earned.
- **Unpaired:** the card reads "Pair up to play". In the dev build, the demo partner plays its part
  10 to 40 seconds after the owner answers, so the game can be tried alone.
- **Look:** the app's dark tokens (`Shared/Kit/Ink.swift`), honey for the subject's true answer and
  blush for a miss, as in the carousel mock.

## Analytics

The room already has the numbers that matter most: how many rounds both partners finish, and how many
days in a row a pair plays. Client events (`guess_round_started`, `guess_answered`,
`guess_revealed`) wait for a change to `ClientEventName`.

## Not in v1

- Free-text answers judged by the subject.
- The pair's own questions.
- A shareable score card. This comes next: it is the user-generated content for TikTok.
- A spicy deck.
- A stake that does anything beyond its line of text.
- A nudge button on the waiting screen. The push already goes out when a part is finished.

## Decided

- The game is free: every question and every round, no paid decks.
- A missed day breaks nothing. Its round closes unscored, the week score keeps what was played, and
  only the love streak (once #20 lands) notices the gap.
- The name stays "Who knows who": it says what the game is, and it matches the carousels.
