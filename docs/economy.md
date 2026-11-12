# Economy

How Ourio's coins are meant to work, so they can be sold later without inflation or refund
problems. The mechanics (routes, ledger, flag) are in [payments.md](payments.md); this is the
policy behind them and the plan for turning sales on. Every number here is the owner's to set, and the metrics below are how it gets set.

## One currency

There is one currency, **coins**, and one signed balance per pair, kept in the pair's `PairRoom`
wallet. Earned, bought and given coins are the same coin in the same wallet. There is no second
currency, no per-partner balance and no item that is only for sale for money. Every entry in the
ledger carries a `kind` (`earn`, `purchase`, `refund`, `gift`, `bonus`, `admin`, `spend`), so what
a coin was for can always be told apart without reading ids.

## Earning is slow on purpose

Rewards for play are **very small against the shop's prices**, and items are hard to earn. Coins
are a thank-you for doing things together, not a wage: nothing is worth playing for the coins.
Every number lives in one place, in this table, and in the contracts that the server and the app
share (`packages/contracts/domain/src/coins.ts` and `shop.ts`, the riddle's in
`pair-room/src/riddle-rules.ts`). `coin-pacing.test.ts` fails if an edit makes earning faster than
the targets below.

| What | Coins | Limit |
| --- | --- | --- |
| Care for the cat (feed, pet, play, water) | 1 each | 2 a day (`earn.care`) |
| A text note / a photo | 1 / 2 | 3 a day together with moments (`earn.notes`) |
| A moment | 2 | in the same `earn.notes` cap |
| A game won / lost | 3 / 1 | 4 a day (`earn.games`) |
| Draw & guess: a solve (each hint takes 1, floor 1) / a give-up | 3 / 1 | in the same `earn.games` cap |
| Ticking off a list item | 1 | 1 a day (`earn.lists`) |
| A wish received / a date matched / a date rated | 5 / 2 / 6 | once per thing, no daily cap (`earn.other`) |
| A guess hit / a round played in Who knows who | 1 / 2 | once per thing (`earn.other`) |
| The love streak: a lit day / milestones | 1 / 5-20 | one a day; milestones at 7, 30, 100, 365 days |
| The daily gift | 1 or 2 | once a day; one day in ten it is a cheap piece instead |
| A finished collection | 40 / 25 | once ever per collection |
| Welcome coins | 60 | once, when the room opens |
| Packs (when `payments` is on) | pack size | money is the limit |

The caps reset at the couple's midnight. A fully active day earns about **13 coins** (every cap,
the gift at its best, a lit streak day). Prices are unchanged: a mouse costs 45, a yarn 60, mid
pieces 90 to 320, the donut bed 380 and the tower 540. So:

- the cheapest items take **3 to 4 days** of full play (the welcome 60 buys one on day one, and
  never a big one);
- mid items take **1 to 3 weeks**;
- the top items take **4 weeks or more**.

Existing pairs keep the balance they have: the new rates apply to what is earned from now on, and
nothing already held or bought is reduced.

## Faucets and sinks

**Faucets** (coins in) are the rows above, all paid by the server and never by the phone, plus
`purchase` and `admin` (support credit). The daily caps are per source: playing more than the cap
earns nothing more, so there is no reason to play for coins.

**Sinks** (coins out), all `spend`: the shop's room pieces, bundles and sets, ink colours for
notes, treats for the cat, and the week's featured set (sold at half price). Seasonal items are
sinks that leave the catalogue, so they keep demand without making old items cost more.

Coins are never traded between players and never cashed out: a pair can only spend them in its
own shop, and there is no way to turn them back into money except the App Store refund below. So
inflation is a **pacing** question (how fast a pair earns against what the shop asks), not a
market one. There is no price set by other players to run away, and nothing a pair holds is worth
more or less to anyone else.

## The pricing anchor

Price against **time to the next desired item**, for a pair that plays normally and pays nothing:

- a first piece for the room: about **3 to 4 days** (2 to 3 days in the first week, helped by the
  welcome coins);
- a premium piece, a set or a rare item: about **4 weeks or more**.

Packs only shorten that wait. They never unlock something that play cannot, nothing is pay-to-win,
and everything for sale is cosmetic (room pieces, inks, the cat's look). A pair that never buys a
pack can still own every item; a pair that buys a pack owns it sooner. When a price or a reward is
changed, check it against these waits first. The metrics below show the real "days to first item".

## Never devalue what a buyer holds

The coins a pair holds, bought or earned, keep their worth. When the economy needs tuning:

- **Do** change earn rates or caps for new earning only, and add sinks (new items, seasonal sets, new
  inks) for pairs to spend on.
- **Do not** raise the price of what is already in the shop to burn a balance, shrink a balance,
  expire coins, or change what a pack grants after it is sold.

A price rise on an existing item is only for the item's own sake (a sale ending), never to drain
holdings. **Coins never expire**, which App Store guideline 3.1.1 also requires of purchased
currency.

## Refunds

An Apple refund (App Store Server Notification `REFUND` or `REVOKE`) writes a negative `refund`
entry for **exactly the coins that purchase credited**, however many of them the pair has spent
since.

- The balance may go below 0, and **only a refund can do that**.
- Spending needs a balance of at least the price, so a negative balance **blocks spending**. The
  server answers `409 NotEnoughCoins {needed, have}` with a negative `have`; the app does not even
  send the order.
- **Earning continues**, and every coin earned pays the debt down automatically: the debt is just
  the signed balance, with no separate counter to keep in step.
- Nothing else is taken back: not earlier earnings, not items already bought, not the daily counts.
- A refund Apple later reverses (`REFUND_REVERSED`) gives the same coins back under its own entry.
- The coins sheet says it plainly when the balance is negative: "A refund took back N coins. New
  coins you earn cover it first", with the amount still owed in place of the balance.
- The refunded purchase is `flagged` in the admin's Purchases view when its refund left the wallet
  below 0, so refund abuse can be seen.

The refund's entry id (`refund:<transaction>`) is unrelated to the shop's five-second Undo, which
puts a shop spend back before it is charged; the `kind` field, not the id, tells them apart.

## Metrics

The economy is tuned from numbers, not guesses. The pair's room reports every coin change to two
D1 tables (see [analytics.md](analytics.md#where-it-is-kept)), and one read-only admin route reads
them:

```sh
PROTON_PASS_AGENT_REASON="read economy" pp run --env-file .env.pass.agents -- \
  scripts/admin-read.sh 'economy?range=30&hold=14'
```

For the last `range` days (default 30) it gives, per UTC day and per source:

- coins **minted** (every credit but a kept wallet moving to a new pair) and **spent**, plus coins
  taken back by refunds, split by source;
- the **median and p90 pair balance**, and how many pairs are in debt;
- the share of pairs holding **more than N days of earnings** (a pair's typical day is the mean it
  earned on the days it earned; `hold` is N, 14 by default): a rising share means the sinks do not
  keep up;
- the **daily-cap hit rate** per capped source: the share of the pairs that earned that day who
  reached the cap. A rate near 0 means the cap is too high to matter; near 1 means every pair
  hits the pace and the faucet is the whole story.

These are pair-level aggregates: a pair id and numbers, never a person, a note or an item. Any
figure over fewer than 5 pairs is left out, as in the rest of the admin.

How to read them: minted much above spent for weeks, with a growing hoarding share, is inflation
(add sinks or lower earn rates); a median balance that never reaches a first item's price in 2 to
3 days is a faucet that is too slow.

## Plan

1. **Ship with `payments` off.** The first release has no packs, no StoreKit and the server flag
   off ([release-flags.md](release-flags.md)). Coins are earned and spent only.
2. **Collect the metrics for 2 to 4 weeks** on real pairs.
3. **Tune.** Move earn rates, caps and prices (never what buyers hold, see above) until the two
   waits in the pricing anchor hold and the hoarding share is stable.
4. **Then turn `payments` on**, for a test pair first (an override in the admin's Flags), then for
   everyone, with the packs set up in App Store Connect ([payments.md](payments.md#coin-packs)).
5. Keep reading the same numbers after: a pack should move the minted line, not the pricing.
