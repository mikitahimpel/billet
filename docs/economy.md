# Economy

How Ourio's coins are meant to work, so they can be sold later without inflation or refund
problems. The mechanics (routes, ledger, flag) are in [payments.md](payments.md); this is the
policy behind them and the plan for turning sales on. Every number here is a placeholder the owner
sets, and the metrics below are how it gets set.

## One currency

There is one currency, **coins**, and one signed balance per pair, kept in the pair's `PairRoom`
wallet. Earned, bought and given coins are the same coin in the same wallet. There is no second
currency, no per-partner balance and no item that is only for sale for money. Every entry in the
ledger carries a `kind` (`earn`, `purchase`, `refund`, `gift`, `bonus`, `admin`, `spend`), so what
a coin was for can always be told apart without reading ids.

## Faucets and sinks

**Faucets** (coins in), all paid by the server, never by the phone:

| Faucet | Source | Limit |
| --- | --- | --- |
| Looking after the cat (feed, pet, play, water) | `earn.care` | 10 coins a day |
| Notes and photos, moments | `earn.notes` | 30 coins a day |
| Games (Who knows who, Draw & guess, cat games) | `earn.games` | 40 coins a day |
| Ticking off lists | `earn.lists` | 15 coins a day |
| Once-per-thing earns: a wish received, a date matched or rated, a guess, a round | `earn.other` | once per ref, no daily cap |
| The daily gift, welcome coins, a finished collection | `gift`, `bonus` | once a day, once ever |
| Packs, once `payments` is on | `purchase` | none: money is the limit |
| Support credit | `admin` | by hand |

The daily caps are per source and reset at the couple's midnight (the cat's local day). They are
what keeps the faucet a pace and not a grind: playing more than the cap earns nothing more, so
there is no reason to play for coins.

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

- a first piece for the room: about **2 to 3 days**;
- a premium piece, a set or a rare item: about **2 to 4 weeks**.

Packs only shorten that wait. They never unlock something that play cannot, nothing is pay-to-win,
and everything for sale is cosmetic (room pieces, inks, the cat's look). A pair that never buys a
pack can still own every item; a pair that buys a pack owns it sooner. When a price or a reward is
changed, check it against these two waits first.

With today's placeholders a caring day earns on the order of 50 to 90 coins, a first piece costs
45 to 140 and a premium one 380 to 540: that reads as a few days and a few weeks, which is the
target. The metrics below say whether real pairs agree.

## Never devalue what a buyer holds

The coins a pair holds, bought or earned, keep their worth. When the economy needs tuning:

- **Do** lower earn rates or caps for new earning, and add sinks (new items, seasonal sets, new
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
