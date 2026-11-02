# Sharing the shop between partners

Design only. Today the shop state (`ShopState` in `Pet/Shop`) lives on one phone, in
`UserDefaults`. Nothing here is built, and the backend deploy is on hold. Field-level contract,
replies and the room's tables are in [play-frames.md](play-frames.md).

## What is shared

One wallet, one closet and one room layout per pair: the whole of `ShopState`. The catalog is
static and ships with the app, so frames carry item IDs only.

## Frames

Each rides the room's existing `play` frame and carries the fields every `play` frame has:
`id` (a UUID, the same string the sender used as the local transaction ID), `kind` and `at`.
The room orders frames and applies each `id` once, which is the rule `ShopState` already follows.

| `kind` | Extra fields | Effect |
| --- | --- | --- |
| `buy` | `item` | Writes the ledger entry `spend:<id>` for the item's price and adds one to the closet. |
| `place` | `item`, `x`, `z`, `yaw` | Takes one from the closet and adds a placement named `placed-<id>`. |
| `unplace` | `placement` | Removes the placement and adds one to the closet. |
| `move` | `placement`, `x`, `z`, `yaw` | Moves a placement. Last frame wins. |
| `paint` | `item` | Sets the wall or floor material. The surface comes from the item. |
| `spend` | `item` | Uses one consumable from the closet, and both scenes show the cat's reaction. |

`spend` is the use of a treat. Stamps leaving the wallet are the ledger entry `buy` writes. If the
owner meant a separate frame for stamps, `buy` splits into `spend` of stamps plus a closet grant.

Later, `purchase` adds a `purchase:<store transaction id>` ledger entry. The grant stays one
entry, `grant:demo`, written by the room when it is created and never by a phone.

## Order and conflicts

- The room is the referee. It applies frames in arrival order and answers the sender with
  `applied`, `duplicate` or `rejected(reason)`, using the `ShopError` cases as reasons.
- Two partners buying at once can overspend by one buy. The later frame is rejected for
  `notEnoughStamps` and its sender rolls back the optimistic change.
- Both phones placing into the same spot are not a conflict: spots are only a default, and a
  placement carries its own coordinates.
- A phone applies its own change at once and keeps the frame until the room answers. Reconnecting
  resends unanswered frames, which is safe because the room applies an `id` once.
- On connect the room sends its full state (ledger entries, closet, layout). The phone replaces its
  own, then replays frames the room has not answered.

## Needed first

- A `shop` table in the room's durable object: ledger entries, closet counts, placements.
- `parsePlay` accepting the kinds above, with a catalog ID check on the server.
- A rejection reply on `play` frames, which only `name` and `react` could use so far.
