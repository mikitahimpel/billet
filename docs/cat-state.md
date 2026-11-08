# The cat's shared state

Nooki's cat used to live only on each phone: `CatDirector` drew a random seed per device and kept
the feeds, pets and games in the user defaults, so the two partners saw two different cats. Now the
couple's `PairRoom` keeps the cat's **facts**, and each phone keeps its **dice**.

| Where | What | Why |
| --- | --- | --- |
| Server, `PairRoom` | Profile (name, look, birth, nature seed, UTC offset), the journal of life events, the temper | Both phones fold the same facts, so they agree she is full, sleepy or missing someone. |
| Each phone | The brain's moment-to-moment choices, from a fresh random seed per launch | She is a little random: the two phones may show her doing different things, in the same mood. |

The server never animates anything. It computes the needs only for the widget and, later, a gentle
push ("Mochi misses you"); that push is not sent yet.

## Profile

```ts
CatProfile = {
  name: CatName,          // 1–24 Unicode scalars, trimmed, no control characters (Swift `CatName`)
  look: { model: CatLookId, coat: CatLookId },  // ids from the app's catalog, e.g. "marmalade"/"natural"
  bornAt: EpochMillis,    // set by the room when the cat is adopted, never changed
  natureSeed: string,     // decimal UInt64, drawn once by the room; the brain's nature comes from it
  utcOffsetSeconds: int,  // the pair's clock for the day rhythm, from the last PUT
}
```

`natureSeed` is the seed the brain already uses for the cat's nature (`CatBrain.nature(seed:)`,
`CatTemperament.born(seed:)`), now the same on both phones. The **dice** — `CatBrain.roll` and the
sampler — take a separate seed the phone draws at launch. Keep the dwell and hysteresis rules; only
the dice are live.

## Journal

An append-only list of what the couple did, ordered by the room's `catSeq`. Each entry:

```ts
CatEntry = { seq: int, id: IdempotencyKey, by: UserId, at: EpochMillis, event: CatEvent }

CatEvent =
  | { _tag: "Fed",        grams: int 1…500 }
  | { _tag: "Petted" }
  | { _tag: "Played" }
  | { _tag: "Watered" }                                  // the plant: no need, a little curiosity
  | { _tag: "NoteShared", note: NoteId, kind: "Drawing" | "Photo" | "Text" }  // by the room only
  | { _tag: "GamePlayed", game: CatGameId, score: int ≥ 0, won: boolean }
  | { _tag: "Slept" }
  | { _tag: "Shooed" }
```

- `id` is a UUID the phone makes once and repeats on retry. The room stores one entry per id and
  answers a repeat with the first one. It doubles as Swift's `LifeEvent.id`.
- `by` and `at` are the server's: the signed-in user and the room's clock. A phone that tapped
  offline sends later and gets the later time; `LifeLog.merge` already lets the room's copy win.
- A note sent and received is one entry, `NoteShared`, appended by the room in the same commit as
  the note. It fills Loved for both partners, as Swift's `.note` does.
- Mapping to Swift `LifeEvent.Kind`: `Fed`→`feed`, `Petted`→`pet`, `Played` and
  `GamePlayed`→`play`, `NoteShared`→`note`, `Slept`→`sleep`, `Shooed`→`shoo`. `Watered` has no
  Swift kind yet; an older build skips it (`LifeLog` is lenient).

## Needs

The room folds the journal with the same curves as Swift's `PetLife` (`cat-life.ts` ports it,
constants from `LifeConfig.standard`) and returns:

```ts
CatNeeds = { full, rested, loved, playful: number 0…1, mood: number, asleep: boolean,
             missing?: UserId, at: EpochMillis }
```

Golden vectors (`CatNeeds/*` fixtures with their journal) pin the fold, so the Swift side can check
it computes the same numbers to within 1e-9.

## Temper: slow personality drift

Per pair, the room keeps three values, each starting at 0.5 and held within 0.1…0.9, so they weight
the brain's choices without ever fixing them:

```ts
CatTemper = { curious: number, lazy: number, cuddly: number }
```

Each entry moves them a small step toward a target, `v ← v + r·(target − v)`:

| Entry | curious | lazy | cuddly |
| --- | --- | --- | --- |
| Petted | | | → 0.9 at 0.02 |
| NoteShared | | | → 0.9 at 0.01 |
| Played | → 0.9 at 0.01 | → 0.1 at 0.02 | |
| GamePlayed | → 0.9 at 0.02 | → 0.1 at 0.01 | |
| Fed | | → 0.9 at 0.005 | |
| Watered | → 0.9 at 0.005 | | |
| Slept | | → 0.9 at 0.01 | |
| Shooed | | | → 0.1 at 0.02 |

A day or more with no entry before this one pulls `cuddly` toward 0.1 at 0.02 per whole day
missed, up to a week: a neglected cat warms up again only with care. About fifty pets move
`cuddly` most of the way from 0.5 toward 0.9, so the drift shows over weeks, not minutes. The phone
multiplies its brain's `curious`, `lazy` and `cuddly` traits by `temper / 0.5`, clamped to 0…1.

## API

| Route | Body | Answer |
| --- | --- | --- |
| `GET /v1/cat` | – | `CatResponse { cat?: CatProfile, temper, needs, lastSeq }` |
| `PUT /v1/cat` | `SaveCatRequest { name, look, utcOffsetSeconds }` | `CatResponse` (first PUT adopts: sets `bornAt`, `natureSeed`) |
| `GET /v1/cat/journal?after=&limit=` | – | `CatJournalResponse { entries: CatEntry[] }`, oldest first, at most 100 |
| `POST /v1/cat/events` | `RecordCatEventRequest { id, event }` | `RecordCatEventResponse { entry, temper, needs }` |

- The pair comes from D1, never from the client. A caller with no pair gets 404.
- `POST /v1/cat/events` before the cat is adopted is 404: there is no cat to feed. `NoteShared`
  from a client is 400.
- Notes are recorded in the journal only once a cat exists; before that they still earn coins.

## Realtime

On the room's WebSocket:

- `ClientMessage.Resume` gains an optional `lastCatSeq`. A socket that sends it is caught up with
  every `CatEntry` after it, then sent each new one as it is stored, both partners' and its own
  (the phone merges by `id`).
- `ServerMessage.CatEntryAdded { entry }` carries one journal entry (its `seq` is `entry.seq`).
- `ServerMessage.CatSaved { cat }` tells each socket that follows the journal the cat was adopted,
  renamed or given a new look.

A socket that never sends `lastCatSeq` gets no cat frames, so older builds are unaffected. Push
comes later; for now a phone in the background catches up from `GET /v1/cat/journal` on launch.

## On the phone

`CatLife` (`apps/ios/Nooki/Model/CatLife.swift`) is the brain's `CatEventSource` in every room. Once the phone is
paired, `RoomController.connectCat` points it at the pair's room:

- `GET /v1/cat` gives the nature seed, `bornAt` and the pair's offset, so both phones fold the same cat. The phone
  that finds no cat adopts her with `PUT /v1/cat`, under the name and coat from onboarding.
- The journal comes from `GET /v1/cat/journal` (at most the last 500 entries on a first sync) and then from the
  Inbox socket, which resumes with `lastCatSeq`. An entry the phone already has under its `id` replaces it.
- A touch here appears at once and goes to `POST /v1/cat/events` under the same `id`. A run of strokes is one
  `Petted` every 10 minutes. Offline, requests wait in an outbox in the user defaults and go on the next sync
  (connect, or the app coming to the front); a request the room refuses is dropped.
- A new seed, birth or pair resets the brain from the events (`CatLifeChange.reset`). Unpairing gives the phone a
  fresh cat of its own.

Everything is kept in the user defaults (`cat.life`), so offline the cat is the one last seen. A phone that kept
`LocalCatEvents` before carries its seed and events over until it is paired.

## Storage

In each room's SQLite: a one-row `cat` table (profile and temper, `last_cat_seq`) and
`cat_entry (seq PK, id UNIQUE, by, at, body JSON)`. Ending the pair, as account deletion and
unpairing do, deletes the cat and its whole journal with the room's other data.
