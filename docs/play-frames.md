# Play frames: contract note

Design only. No schema, fixture, Worker or Swift code exists for anything below, and nothing is
deployed. It extends [shop-sharing.md](shop-sharing.md) (which owns the shop rules) and gathers
what the Labs experiments (`labs:` lines in the build status) said they would need from the
server. Decisions that belong to the owner are marked **Owner** and listed at the end.

## 1. Why a separate family

Notes have a gapless `seq`, HTTP history and push delivery. Pets, treats, the shop and the Labs
toys are none of that, and putting them in `seq` would give every client gaps in note history.
So play gets its own messages and its own counter, `playSeq`.

Today the real contract (`contracts-realtime`) has only `Resume`, `Stroke` and `Presence` going
up and `Stroke`, `Presence` and `NoteReceived` coming down. The `play` frames that exist
(`pet`, `treat`, `name`, `react`) live only in the dev-only `DemoRoom`, as loose JSON with a
`kind` string. This note moves them into the real contract under the same names.

## 2. Envelope

Names follow the contract (`_tag`, PascalCase). The demo's lowercase `kind` maps one to one
(`treat` is `Treat`).

Client to server:

```
Play { id: UUID, at: ISO-8601 with offset, action: PlayAction }
```

- `id` is the idempotency rule of `SendNoteRequest.key` (#93): the room applies an `id` once per
  sender and answers a repeat with `Duplicate`. It is also the shop's local transaction ID.
- `at` is the sender's wall time with its UTC offset, as in the demo. It is for showing and for
  deriving the sender's calendar day. It never orders anything: the room orders by arrival. The
  room rejects an `at` more than 36 hours from its own clock (`badTime`).
- `action` is a tagged union, one case per row in sections 4 and 5.

Server to the sender, for every `Play`:

```
PlayAnswer { id, result: Applied { playSeq } | Duplicate { playSeq } | Rejected { reason } }
```

Server to the partner, when the action changes state or is an event:

```
PlayReceived { playSeq, by: UserId, at, action }
```

Ephemeral actions (class C below) arrive as `PlayRelayed { by, action }` with no `playSeq`.

On connect, after `Resume`'s notes, the room sends one `PlayState { playSeq, state }` (section
6). The client replaces its copy of the room's state, then resends frames the room never
answered. A reconnecting client may send `Resume { lastSeq, lastPlaySeq }` so a short gap is
filled with `PlayReceived` instead of a snapshot; the snapshot is always allowed.

A frame that does not parse is ignored and logged, as for notes. If its `id` can be read, the
sender gets `Rejected { reason: "invalid" }`.

Limits: a `Play` is at most 8 KiB (only `Door` carries strokes; everything else is far smaller),
and a user may send 20 per minute and 2 per second. Going over answers `Rejected { reason:
"tooFast" }`; it never closes the socket.

## 3. Three classes

| Class | Stored | Replayed on connect | Pushed | Examples |
| --- | --- | --- | --- | --- |
| A, state | yes, folded into current state | yes, in `PlayState` | no | shop, lamp, visit, frame, door, gift |
| B, event | yes, bounded log | counters only, plus a bounded queue for what an offline partner should still see | no | treat, pet, opened, react |
| C, ephemeral | no | no | no | hold |

Nothing in this note rides a push lane. Notes are the only thing that wakes a phone. The one
place a play event might reach a lock screen is `Opened` through a widget or Live Activity
update; that waits for the widget work and is not part of this contract.

## 4. Shop actions

The rules (ledger, closet, referee, rollback) are in shop-sharing.md and are not repeated. This
adds the fields, checks and answers.

`ItemId` is a catalog item id string. The catalog (id, price, category, mount, surface, whether a
material) must exist on the server too, as one shared contract file with a version number, or the
server cannot check `item`. An id the server does not know is `Rejected { unknownItem }`, so the
server ships before an app that sells a new item.

| Action | Fields | Checks and effect | Reasons |
| --- | --- | --- | --- |
| `Buy` | `item` | ledger `spend:<id>` for the price, closet plus one | `unknownItem`, `notEnoughStamps { needed, have }`, `alreadyOwned` (materials are bought once) |
| `Place` | `item`, `x`, `z`, `yaw` | closet minus one, placement `placed-<id>` | `unknownItem`, `notInCloset`, `wrongKind` (a treat), `roomIsFull`, `badPosition` |
| `Unplace` | `placement` | placement removed, closet plus one | `unknownPlacement` |
| `Move` | `placement`, `x`, `z`, `yaw` | last frame wins | `unknownPlacement`, `badPosition` |
| `Paint` | `surface`, `item` or null | sets the wall or floor material; null clears | `unknownItem`, `notInCloset`, `wrongKind` |
| `Spend` | `item` | closet minus one; the partner gets `PlayReceived`, so both scenes react | `unknownItem`, `notInCloset`, `wrongKind` (not a consumable) |

- `x`, `z` are metres on the floor plane, `yaw` is radians, all finite numbers. The room checks
  `x` and `z` against the room's bounds (walls sit at -0.6; the other bound is fixed with the
  server's copy of the layout rules) and rejects `badPosition` rather than clamping.
- `Paint` carries `surface` because null has no item to infer it from. shop-sharing.md derived
  it from the item; this is the one change to that note.
- `reason` strings are the Swift `ShopError` cases, lower camel case.
- The wallet is computed by the room from its ledger. How stamps are earned is the streak rule
  (#20) and is not decided.
- Later, `Purchase` adds `purchase:<store transaction id>` once the owner decides what is sold.
  The one `grant:demo` entry stays room-written.

## 5. Labs actions

Taken from the `labs:` build-status lines. Each says what the experiment does locally today and
what the room has to add. Experiments with no backend need are listed at the end.

| Labs item | Frame | Fields | Class | What the room does |
| --- | --- | --- | --- | --- |
| 5 the cat came back | `Opened` | `note` | B | Accepts it from the receiver of a note the partner sent, once per note (`notInRoom`, `notYours` otherwise), and tells the sender. The sender's phone ends the cat's errand. |
| 10 two wisps | `Hold` | `on` | C | Relays to the partner while both are connected. The 1.2 s overlap rule stays on the phones. When a user's last socket closes, the room relays `Hold { on: false }` for them, as it does for presence. |
| 13 lamp colours, 14 lights out | `Lamp` | `on`, `colour` (`gold`, `rose`, `green`, `amber`, `cream`) | A, one record per user | Whole lamp state, newest frame wins, so a reconnect needs one row. The "both out for nine hours" rule uses each record's stored time, and stays on the phones. |
| 16 next visit | `Visit` | `day` (`YYYY-MM-DD`) or null | A, one record per pair | Newest wins; null clears. `day` is a calendar day with no zone. Rejects `badTime` more than 400 days ahead or more than a day in the past. |
| 8 framed notes | `Frame` | `note`, `framed` | A | See below. **Owner** |
| 19 wrapped delivery | `Gift`, `Unwrap` | `gift` (UUID), `item`; `gift` | A | See below. **Owner** |
| 20 our advent | `Door` | `year`, `number` (1 to 24), `strokes` (`CompactStrokes`) | A, keyed by author, year, number | Stores a door once; a second frame for the same key is `alreadyFilled`. Strokes use the note budget of 3 KiB. `number` after the sender's day of December is `notYet` (allowing one day for zones). No PNG: the receiver renders from strokes. Doors of older years are kept for two years. |
| 12 porch light | `Pause` | `day` | B | Marks one of a device's days as paused for the streak. Blocked: the rule is #20's. **Owner** |

### Framed notes

The experiment frames up to three received notes, oldest out. Syncing it needs one answer: is the
wall shared (either partner frames any note, one wall per pair, three in total) or personal
(each phone chooses, nothing to sync)? The recommendation is shared, to match the one shared room
in shop-sharing.md. Then `Frame { note, framed }` adds or removes a note, the room evicts the
oldest when a fourth is added and tells both, and it rejects a note that is not in the room.

### Gifts

Labs gives each phone its own closet and moves an item from one to the other. shop-sharing.md
makes the closet shared, so a transfer would move an item from the pair to itself. If the closet
stays shared, a gift is a surprise rather than a transfer: `Gift` takes the item out of the closet
into a wrapped state the partner sees, `Unwrap` by the partner returns it and both scenes show the
unwrapping, and an unopened gift stays out of the closet. If the closets are separate the shop
note has to change instead. **Owner**

### Not play frames

These change existing contracts, so they are not part of `PlayAction`:

- **Their sky (15)** needs the partner's time zone. Add an optional `zone` (an IANA id, at most
  64 characters, letters, digits and `_/+-`) to `Resume`, sent once per connection. The room
  keeps it per member and sends the partner's in `PlayState` and when it changes. It is not
  checked against a zone list (zone data differs between phones), and the app already handles an
  unknown one. The zone says roughly where the partner is, so `docs/privacy.md` has to say it is
  stored and shown to the partner only.
- **Sealed note (9)** is a field on `SendNoteRequest`: `opensAt`. The room keeps the note in a
  `held` table with no `seq`, and its alarm appends it as a normal note at `opensAt`, so `seq`
  stays gapless for both partners and `sentAt` follows `seq` as #68 requires. The sender sees a
  pending note and may retract it before. Push, the socket and history are unchanged afterwards.
  Today the Labs version holds the note on the sender's phone and sends only while the app is
  open, which cannot keep a secret across a closed app.
- **Watch it being drawn (4)** needs time in the ink. `CompactStrokes` already has a version tag;
  version 2 would add a start offset and a duration per stroke (about 10 bytes a stroke against
  the 3 KiB budget). The grid and budget are #13's decision.

### No backend need

Overnight stay (3), today's word (6), Sunday post (7), wallpaper shortcut (11), on this day
(17), seasons (18) and bedside widget (21) work from data the phone already has. On this day is
quiet until there is a year of history.

## 6. What the room stores

New tables in `PairRoom`, each created by a Drizzle migration. They all go away with the room
(#95, #21), and `docs/privacy.md` needs a line for each when built.

| Table | Holds |
| --- | --- |
| `play_log` | `play_seq`, sender, frame id (unique with sender), action as JSON, `at`; pruned to the newest 500 |
| `ledger`, `closet`, `placement`, `surface` | the shop state, as in shop-sharing.md |
| `lamp` | one row per user |
| `visit`, `frame_wall` | one value, and up to three note ids |
| `gift` | wrapped items and who sent them |
| `door` | author, year, number, strokes |
| `member` gains `zone` | the partner's time zone |
| `held_note` | sealed notes waiting for `opensAt` |

`PlayState` is those tables folded into one message, with `playSeq`. It is bounded: a shop
with a full closet, 3 frames, 48 doors and the lamps is well under 64 KiB, the socket's frame
limit.

## 7. Build order

1. The envelope: `Play`, `PlayAnswer`, `PlayReceived`, `PlayRelayed`, `PlayState`, with fixtures,
   Wire types and the existing demo kinds (`Pet`, `Treat`, `Name`, `React`).
2. The shared catalog file, then the shop actions and their tables.
3. `Opened`, `Hold`, `Lamp`, `Visit`, `Zone`.
4. `Door`, `Frame`, `Gift` after the owner answers; `Pause` after #20; sealed notes and ink
   timing as their own issues.

Each step needs fixtures, a Swift conformance test and the room tests of the existing kind
(restart from storage, concurrent senders, a repeated `id`).

## 8. Open questions for the owner

Also in `~/.billet-manager/pet-concept/owner-questions.md`.

1. Framed notes: one shared wall of three, or a personal one per phone?
2. Gifts: separate closets with a real transfer, or a shared closet with a wrapped surprise?
3. Sealed notes: may the sender retract before `opensAt`? Is a held note private data we may
   store for longer than a day?
4. Time zone: is it acceptable that the partner sees it, and is "their sky" worth storing it?
5. Doors: keep drawings two years, or delete each December's at the end of the year?
