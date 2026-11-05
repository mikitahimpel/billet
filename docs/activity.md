# The activity Inbox

The home screen's Inbox lists what happened in the pair lately: "Anya fed Mochi 40 g", "Dima sent
you a drawing", "You bought the Rainy Evening set". The server keeps the list. The phone writes the
lines in its own language from each item's kind and payload, and opens each item's target.

## Where items come from

Each couple's `PairRoom` keeps one `activity` table. Every item is written **in the same commit as
the row it reports**, so an item exists exactly when its source does. A pure `activityFor` per
source turns the row into its item:

| Source | Item | Written by |
| --- | --- | --- |
| Cat journal entry (except `NoteShared`) | `CatFed`, `CatPetted`, `CatPlayed`, `CatGamePlayed`, `CatSlept`, `CatShooed`, `PlantWatered` | the room, with the `CatEntry` |
| Adopting or renaming the cat | `CatAdopted`, `CatRenamed` | the room, with the profile |
| A note | `NoteSent` | the room, with the note |
| A shop buy, the daily gift, a set bonus | `Purchased`, `GiftClaimed`, `BonusEarned` | the room, with the wallet's coin row (billet-pay) |
| Coins bought with money, an App Store refund | `CoinsBought`, `Refunded` | the room, with the `CreditCoins` / `RevokeCoins` row that mirrors the D1 purchase into the wallet |
| A streak milestone | `StreakReached` | the room, when the streak rules (#20) move `streakDays` |

A note does not also appear as cat care: `NoteShared` journal entries make no item of their own.
Coins earned do not appear either, since they would double every cat row. A shop Undo deletes the
`Purchased` item in the same commit as it takes the coins back.

## The item

```ts
ActivityItem = { id: ActivityId, at: EpochMillis, actor: ActivityActor, event: ActivityEvent,
                 target?: ActivityTarget, cursor: ActivityCursor }

ActivityActor  = Me | Partner | Cat | Store        // relative to the caller
ActivityEvent  =
  | CatFed { grams } | CatPetted | CatPlayed | CatGamePlayed { game, score, won }
  | CatSlept | CatShooed | PlantWatered { plant? }
  | CatAdopted { name } | CatRenamed { name }
  | NoteSent { note, kind: "Drawing" | "Photo" | "Text" }
  | Purchased { offer?, items: ShopItemId[], coins } | GiftClaimed { coins }
  | BonusEarned { collection, coins } | CoinsBought { productId, coins }
  | Refunded { productId, coins }
  | StreakReached { days }
ActivityTarget =
  | Note { note } | Moments { note } | Cat | Plant { plant } | ShopItem { id } | ShopOffer { id }
```

- `id` is the source row's own id (`cat:<entry id>`, `note:<note id>`, the coin entry's id), so a
  repeated write is one item, and the item is found again when its source goes.
- The server stores the acting user and returns `actor` relative to whoever asks: `Me`, `Partner`,
  `Cat` (things the cat did on its own), or `Store` (an App Store refund, which names no user).
- `Refunded` is the only `Store` item. A reversed refund makes no item.
- The phone builds the line from `event` and localises names by id (shop titles, games, plants).
- Targets: a text note opens the note, a drawing or a photo opens Moments, cat care opens the cat,
  a plant opens its card, a buy opens the item, or the offer when it had several.

## API

| Route | Body | Answer |
| --- | --- | --- |
| `GET /v1/activity?before=&limit=` | – | `ActivityResponse { items, next?, head?, unread }`, newest first, at most 50 a page |
| `POST /v1/activity/read` | `MarkActivityReadRequest { upTo: ActivityCursor }` | `ActivityUnreadResponse { unread }` |

- `before`, `next`, `head` and each item's `cursor` are opaque `ActivityCursor` strings: the phone
  only hands them back, never builds one. Items are ordered by `at`, then `id`.
- `head` is the newest item's cursor in the whole list, on every page, and absent while it is
  empty. Sending it as `upTo` marks everything read; an item's own `cursor` marks up to it.
- **Read state is per user.** Each member has a read mark. Items the reader made themselves are
  never unread. `unread` counts the partner's, the cat's and the store's items above the mark.
  Marking read only moves the mark forward.
- The pair comes from D1, never from the client. A caller with no pair gets 404.

## Realtime

`ClientMessage.Resume` gains an optional `activity: true`. A socket that sends it gets
`ServerMessage.ActivityUnread { unread }` whenever its user's count changes: when the partner adds
an item, or when the user reads on another device. An older build never sees the frame.

## Keeping and deleting

- Items older than 30 days are pruned whenever an item is written.
- Ending the pair, as account deletion and unpairing do, deletes the room's activity and both read
  marks, with the cat and the leaving user's notes.
- An item carries only what the pair already shares: ids, counts, a cat name, a game score.
