# The love streak

One streak for the couple, kept by the pair's `PairRoom`. A day lights once both partners did something in the app
that day (pet or treat the cat, add a moment, write a note, swipe a date idea, plan a movie night, check in a mood);
the flame then grows by one and the pair earns coins. Miss a whole day and it goes out; a streak of at least 3 days
that went out yesterday can be restored, once in 30 days for the pair.

Modelled on TikTok's DM streaks, made gentler: the reminders say whose turn it is, never "you'll lose it". TikTok
shows the flame after 3 days of messages both ways, fades it on a day nobody wrote, ends it after a whole missed day
and allows a few restores a month within 48 hours. Users report the flame turning purple around day 100.

## Rules

`LoveStreak` (`packages/contracts/domain/src/streak.ts`) is `{ days, best, lastDay?, restoredOn?, marks? }`, days as
local `YYYY-MM-DD`. The rules are pure functions there, run by the room's `decide`:

- `markStreakDay(streak, members, user, day)`: `user` did their part on `day`, their own local day. The day lights
  once both members have marked it: it runs through `recordStreakDay`, and its marks go. Until then the mark waits in
  `marks`. A mark at or before `lastDay` changes nothing. Marks more than two days older than the newest are dropped:
  a report may come a day late, and partners' local days differ by up to a day.
  A late report for a day before one that already lit can't light it any more (`lastDay` has moved past it).
- `recordStreakDay(streak, day)`: the day after `lastDay` continues the run, a later one starts over at 1; a day at
  or before `lastDay` changes nothing. `best` never falls.
- `restoreStreak(streak, today)`: only when `today` is two days after `lastDay`, `days >= 3`, and the last restore was
  30 or more days ago. It sets `lastDay` to yesterday and `restoredOn` to today, so today's day continues the old run.
  Marks for today stay. Either partner can restore.

A lit day pays the pair wallet `streakRewardCoins(days)` as one `earn:streak:<day>` coin entry. A day reaching a
milestone (3, 7, 14, 30, 50, 100, 200, 365) adds a `StreakReached` Inbox item, by the partner who lit it, and moves the
other's unread count.

### Coins

The numbers live in one place, `packages/contracts/domain/src/streak.ts`; `test/streak-rewards.test.ts` pins them to
the shop's prices. The streak is a thank-you, never an income: the shop sells things for care, and a streak must not
empty it.

| Source | Coins |
| --- | --- |
| A lit day (`streakDayCoins`) | 1 |
| Day 7 / 30 / 100 / 365 on top (`streakMilestoneCoins`) | 5 / 10 / 15 / 20 |

Against the catalogue (`roomItems`, `inks`, placeholders until the owner sets them): the cheapest paid piece is the
mouse at 45, inks start at 60, the median paid piece is about 120, a rug 180, a tower 540. A treat costs 10.

- A full week of lit days pays 12 (7 days plus the day-7 bonus): about a quarter of the cheapest piece.
- The day-7 bonus is 5, the day-30 bonus 10, day 100 20, day 365 30: each at most a sixth of a mid-priced piece.
- A year of lit days pays about 415 in all, less than the welcome gift (560) and about five days of care (a caring day
  earns around 80, caps 95).

Tests fail when a number breaks one of these, so raising a reward is a deliberate change to the test as well.

## API

| Route | Body | Answer |
| --- | --- | --- |
| `GET /v1/streak` | – | `StreakResponse { streak }`, empty before the room opens |
| `POST /v1/streak/days` | `RecordStreakDayRequest { at, utcOffsetSeconds }` | `StreakResponse` |
| `POST /v1/streak/restore` | `RestoreStreakRequest { utcOffsetSeconds }` | `StreakResponse`, or 409 `StreakNotRestorable` |

- The pair comes from D1; a caller with no partner gets 404. The first day opens the room.
- `at` is when it happened on the phone. A phone that was offline reports late, so the room marks the day `at` falls
  on in the caller's offset, with `at` held between a day before the room's clock and the room's clock. A claim
  further back counts as a day back; one ahead counts as now.
- A socket that resumes with `streak: true` is sent `StreakChanged { streak }` at once, and again on every socket of
  the pair after each mark, lit day or restore, whoever made it.
- A demo partner (`demo-partner`) marks its day after each thing it does, in the cat's offset, so a demo account's
  streak lights too.
- In the room's SQLite the `room` row keeps `streak_days`, `streak_best`, `streak_last_day`, `streak_restored_on`
  and `streak_marks` (JSON).

## Pushes

Both go on the alert lane through the delivery ledger, and carry `PushPayload.Streak { you, lit, streak }`:

- **Your turn** (`streak-turn:<day>:<by>`): a partner marked a day the other hasn't. Not sent once the day lit or the
  other did their part.
- **Lit** (`streak-lit:<day>:<by>`): to the partner who went first. Not sent once a later day lit.

Both collapse under `s-<day>`, so the lit push replaces the turn on the lock screen. The notification extension
writes the partner's name into the title, and the streak into `Us/streak.json` with this phone's unsent days on top,
then reloads the widgets, so the card and the widgets show it before the app opens.

## The phone

`StreakStore` (`apps/ios/Nooki/Model/Streak.swift`) keeps `Us/streak.json` as the room's streak last read, with the
days this phone marked that the room hasn't stored yet (`Us/streak-unsent.json`) marked on top. `LoveStreak.mine` and
`partner` are the marked days; `turn(on:)` says whose part today waits for. Once paired it follows the room through
`StreakRemote`: each day this phone marks is posted at once, a drop leaves it in the unsent list for the next refresh
(the app coming to the front), and a day the room refuses is let go. While the app is in front the room socket
(`InboxLink`) follows the streak, so the partner's day shows here at once. A restore goes to the room; offline it
does nothing. Before pairing the streak stays on the phone and this phone's day lights it alone.

The Us card says whose turn it is ("Lena did their part. Your turn…" or "You did your part…") and shows the flame
half-faded. The family widget's streak row and the lock-screen streak widget say "Your turn today" or "Waiting on
your partner".

On a day the streak would go out at midnight and this phone's person hasn't done their part, the phone shows one
local notification at 20:00 in the cat's voice (`StreakNudge`, `apps/ios/Nooki/Model/StreakNudge.swift`), saying so
when the partner already did theirs. It is planned again whenever the streak changes: in the app, and in the
notification extension when a streak push comes, so the next evening's is planned without the app being opened. It
is never sent once the evening has passed, nor asks for permission; Settings → Reminders turns it off. The switch is
in the app group's defaults, so the extension reads it too.
