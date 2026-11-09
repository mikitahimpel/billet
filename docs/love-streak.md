# The love streak

One streak for the couple, kept by the pair's `PairRoom`. Every day the couple does something together in the app
(pets or treats the cat, adds a moment, writes a note, swipes a date idea, checks in a mood), the flame grows by one.
Miss a whole day and it goes out; a streak of at least 3 days that went out yesterday can be restored, once in 30
days for the pair.

## Rules

`LoveStreak` (`packages/contracts/domain/src/streak.ts`) is `{ days, best, lastDay?, restoredOn? }`, days as local
`YYYY-MM-DD`. The rules are pure functions there, run by the room's `decide`:

- `recordStreakDay(streak, day)`: the first report of a day grows it; the day after `lastDay` continues the run, a
  later one starts over at 1; a day at or before `lastDay` changes nothing. `best` never falls.
- `restoreStreak(streak, today)`: only when `today` is two days after `lastDay`, `days >= 3`, and the last restore was
  30 or more days ago. It sets `lastDay` to yesterday and `restoredOn` to today, so today's first action continues
  the old run.
- A day counts for the pair whichever partner reports it. Both partners doing something is not required.

A day reaching a milestone (3, 7, 14, 30, 50, 100, 200, 365) adds a `StreakReached` Inbox item, by the partner
whose day it was, and moves the other's unread count.

## API

| Route | Body | Answer |
| --- | --- | --- |
| `GET /v1/streak` | – | `StreakResponse { streak }`, empty before the room opens |
| `POST /v1/streak/days` | `RecordStreakDayRequest { at, utcOffsetSeconds }` | `StreakResponse` |
| `POST /v1/streak/restore` | `RestoreStreakRequest { utcOffsetSeconds }` | `StreakResponse`, or 409 `StreakNotRestorable` |

- The pair comes from D1; a caller with no partner gets 404. The first day opens the room.
- `at` is when it happened on the phone. A phone that was offline reports late, so the room counts the day `at`
  falls on in the caller's offset, with `at` held between a day before the room's clock and the room's clock. A
  claim further back counts as a day back; one ahead counts as now.
- A socket that resumes with `streak: true` is sent `StreakChanged { streak }` at once, and again on every socket
  of the pair after each day that changes the streak or a restore, whoever made it.
- In the room's SQLite the `room` row keeps `streak_days`, `streak_best`, `streak_last_day` and
  `streak_restored_on`.

## The phone

`StreakStore` (`apps/ios/Shared/Model/Streak.swift`) keeps `Us/streak.json` as the room's streak last read, with
the days this phone grew it that the room hasn't stored yet (`Us/streak-unsent.json`) counted on top. Once paired it
follows the room through `StreakRemote`: each day that grows the streak here is posted at once, a drop leaves it in
the unsent list for the next refresh (the app coming to the front), and a day the room refuses is let go. While the app is in
front the room socket (`InboxLink`) follows the streak, so the partner's day shows here at once. A restore
goes to the room; offline it does nothing. Before pairing the streak stays on the phone, as it did before the room
counted it.

On a day the streak would go out at midnight, the phone shows one local notification at 20:00 in the cat's voice
(`StreakNudge`, `apps/ios/Nooki/Model/StreakNudge.swift`). It is planned again whenever the streak changes: the day
counting takes it back and plans tomorrow's. It is never sent once the evening has passed, nor asks for permission;
Settings → Reminders turns it off. A day the partner counts reaches this phone only when the app is in front, so
until then the nudge may still fire on it.
