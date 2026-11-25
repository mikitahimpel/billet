# Subscription and paywall

How Ourio sells a subscription, and where a paywall may and may not stand. Proposed and built
2026-11-25 behind the `plus` flag (off); [As built](#as-built) says where the build differs from
the proposal below. It sits beside
[payments.md](payments.md) (the coin packs, built, flag off) and [economy.md](economy.md) (the
policy for coins).

## Recommendation

**Sell one thing: Ourio Plus, a parcel every month for the two of you.** One subscription covers
the pair. Each paid month a parcel arrives in the room, and the pair opens it by choosing any one
piece in the Shop. What they choose is theirs for good. Nothing else in the app is locked, rented
or sped up.

| | |
| --- | --- |
| Price | **$3.99 a month, $29.99 a year** (placeholders for the owner, like the pack prices) |
| Who it covers | Both partners. Either one buys; the server gives it to the pair |
| Trial | **None.** The first parcel arrives at once; a month at $3.99 is the trial |
| What Plus gives | One parcel per paid month: any one room piece, ink, stamp, seal, window view or lighting from the Shop, kept for ever. A thank-you line from the cat |
| What stays free | Everything there is today, and every new game, story and mechanic |
| Where it is sold | One row in the Shop and one in Settings. Never on Home, in the Inbox, in a game, in onboarding, in a push or in a widget, and never as a screen that opens by itself |
| On cancel | Parcels stop coming. Every piece chosen and every parcel not yet opened stays |
| Coins | Untouched: Plus mints no coins and changes no earn rate. Packs stay as the one-off way to buy |
| Not offered to | Accounts that said they are 13 to 17 in onboarding, in the first version |

Why this and not a list of premium features:

1. **It is the only thing the app can honestly carry today.** Nothing in Ourio is gated, and
   nothing that is built would survive being gated without taking something from a couple. What
   is built and unsold is *things*: 43 bundled models, 15 window views, 6 lightings
   ([Audit](#1-audit)).
2. **It keeps every economy rule.** Every piece a parcel can hold is also sold for coins, so there
   is still "no item that is only for sale for money" ([economy.md](economy.md)).
3. **Nothing expires, so cancelling is not a loss.** The usual subscription rents features and
   takes them back. This one leaves a thing behind each month.
4. **It cannot fail "only for her".** The commonest support problem in couples apps is premium that
   unlocks for one partner. A parcel lies in the pair's shared room; there is no per-phone state to
   get wrong.

**Do not build it yet.** Three gates first, in this order:

1. The coin packs go on sale as [economy.md](economy.md) plans. They need the same owner steps
   (Paid Apps Agreement, bank, tax) and say within weeks whether any pair pays at all.
2. There are at least **1,000 paired pairs active in a month**. Below that the income does not pay
   for the weeks of work: at the benchmark payer rates about 1.5% of pairs subscribe, which is 15
   pairs and roughly $300 a year ([Expected numbers](#expected-numbers)).
3. The Shop gains pieces every month. A parcel a month empties today's catalogue of 26 unlocks in
   about two years with no play at all, and far sooner with it.

**Caveats, the ones that matter most.**

- **No usage numbers exist.** `SessionEnded` and the retention reads come only after the next
  TestFlight build. Every rate below is carried over from other apps. The places where this
  changes the answer are marked **(needs numbers)**.
- **Apple has never said in writing that one purchase may unlock a second, linked account.**
  Paired, Cupla and TwoGether do it on the App Store today; an App Review engineer asked the exact
  question in May 2026 answered only "sign up for a session with App Review". Ask before building.
- **The age rating may become 18+.** Apple's new "Dating and Relationships" descriptor gives a
  minimum of 18+, and it must be answered by 2027-01-12. If Ourio falls under it, the 13 to 17
  rules below still hold but apply to nobody.
- Facts dated after mid-2026 were read from Apple's and regulators' pages on 2026-11-25 by a
  research pass, not checked a second time. Each is in [Evidence](#evidence) with how it was read.

## As built

Shipped in one review with the coin packs, both behind flags that stay `off` until the owner turns
them on ([release-flags.md](release-flags.md)). Server and routes: [payments.md](payments.md#ourio-plus).

- **Products:** `com.ourio.app.plus.monthly` $3.99 a month and `com.ourio.app.plus.yearly` $29.99
  a year, group "Ourio Plus", no trial or introductory offer, Family Sharing off
  (`@billet/contracts-domain/plus`, `apps/ios/Ourio.storekit`, `coin-packs.json`; a sync test fails
  when they disagree).
- **Parcel ceiling: 320 coins, inclusive** (`parcelPriceCeiling`, tested on both sides). The Shop's
  room pieces cost 45 to 540; the two dearest, the Donut Bed (380) and the Cat Tower (540), are
  out, so a parcel is never a way round the pieces a pair saves up for longest, and everything up
  to the Armchair (320) is in. Free inks and starter pieces are never offered: they are owned
  already. Change the constant and the test together when the Shop's prices move.
- **Declared 13-17:** coin packs are sold to them; Plus is not. The server answers every
  `/v1/plus` route with a 404 for an account whose onboarding answer is `age-13-17`, on every
  stage, so the app hides the Shop row, the Settings row and the card, and a purchase or a grant
  cannot be made. An adult whose partner is a declared 13-17 may still subscribe; the partner sees
  no Plus anywhere, but the pieces chosen land in their shared room. **(owner to decide whether
  that is acceptable or the adult should be refused too.)**
- **Entries:** the Shop row (top of Today), the Settings row, and one card on Home after
  onboarding: on the World tab, over the pet controls, only when the pair is together, nothing
  from the partner is unread, no homecoming line shows and Plus is on offer. It is on screen at
  most once per phone (App Group `plus-welcome.json`), dismissible, and opens the sheet only on a
  tap. This is the owner's call over the "nothing on Home" rule of the proposal below.

Where the build differs from the proposal:

| Proposal | Built | Why |
| --- | --- | --- |
| `POST /v1/purchases` branches on the transaction type | separate `/v1/plus/*` routes | the flag, the age gate and the answer type differ; the coin path is untouched |
| `PlusState` with `paidBy` | `Active`/`Ending`/`Grace` for the payer, `Shared` for the partner | the partner never learns of a cancel, grace or refund |
| `ShopResponse` and `ShopChanged` carry Plus | `GET /v1/plus`, and `OpenParcelResponse` returns both | no change to the shop frame both phones read |
| `parcel_grants` written by a daily Cron | parcels derived from paid periods; only opened ones stored | nothing depends on a job running; ids are stable |
| a zero-amount `parcel` ledger entry | the open is stored in `plus_parcels`, the grant goes through the room | the minted line is not touched either way |
| `appAccountToken` binds the account | the first account to send a transaction keeps it; others get `SubscriptionTaken` | no token yet: add it with the In-App Purchase key |
| Inbox items for a parcel and for the partner's Plus | not built | the Shop and Settings rows show waiting parcels |
| Delete account warns a subscriber | built: the footer, the confirmation and a Manage subscription link | |
| Refund of an opened parcel's period | owed in coins (`refund:<parcelId>`), the piece stays | as packs; **(owner: check against "nothing earned is taken away")** |

## 1. Audit

Read from the code on this branch.

### What a pair gets free today

Everything.

| Area | Today | Limits found |
| --- | --- | --- |
| The cat | Three coats (grey, ginger, cream), chosen free in onboarding; no screen to change it later; no accessories exist | none |
| Rooms | Living room, bedroom, the corkboard; none sold (the `rooms` experiment may give a new pair one room) | 8 placed pieces a room, checked on the phone only |
| Notes, drawings, photos | Unlimited, kept for as long as the pair exists | 10 MiB an image, 16 KiB a note |
| Moments | Feed and a wall | 6 wall slots; a seventh unpins the oldest |
| Games | Four care games, Who knows who, Draw and guess, Pick tonight; Mischief, Cat school and the story behind flags, off | none costs coins |
| Widgets | 16 widget and control kinds, a Live Activity | none gated |
| Streak, lists, dates, wishes, calendar | All free | restore once in 30 days |
| The Inbox | Free | items older than 30 days are pruned |

### What costs coins

| What | Count | Price in coins |
| --- | --- | --- |
| Room pieces (`roomItems`, two of the 12 are starters) | 10 | 45 to 540 |
| Inks (graphite is free) | 6 | 60 to 120 |
| Stamps and seals | 10 | 30 and 45 |
| Treats | | 10 each |

About **3,225 coins buy everything** ([gameplay-vision.md](gameplay-vision.md)). A full day of play
earns 13. At the pack rates (100, 550 and 1,200 coins for $0.99, $4.99 and $9.99) the whole
catalogue costs about **$27**. That is the most a pair can ever spend, so the ceiling on income is
the size of the catalogue, whichever way coins are sold.

### Built, and neither shown nor sold

| What | Where | Could be |
| --- | --- | --- |
| 43 more room models (55 bundled, 12 sold) | `Resources/Shop` | Shop pieces, one or two a month |
| 15 window views | `Pet/WindowView.swift`; a release build always shows `suburb-night` | Shop pieces |
| 6 room lightings | flag `room-lighting` | Shop pieces |
| The Dusk look | `Design/Tokens/Look.swift`, Labs only | free, or a Shop piece |
| A shop piece that arrives wrapped for the partner | `ShopModel.buy(_:asGift:)`, no screen | how a parcel arrives |
| Labs | compiled in only with `BILLET_LABS` | stays out of release builds |

### The mock Plus that is already in the code

`FeatureShop/CoinStore.swift` holds a card shown only in a mock build: "Ourio Plus, for the two of
you, every month", $4.99, with five perks. Nothing is bought; it flips a local flag that also puts
a crown on the couple button on Home. Two contract fields say `plus` on shop items (`tower` and
`lantern` are seeded true) and nothing reads them.

Three of its five perks break rules the owner has since set, so the card must be replaced before
any build that sells shows it:

| Perk in the mock | Verdict |
| --- | --- |
| "Coins every day" | A daily drip. Dropped |
| "Double coins from games and care" | Pays to earn faster, and makes play a wage. Dropped |
| "Every ink" | Rented: gone on cancel, and it devalues inks other pairs bought. Dropped |
| "A new coat or accessory every month" | Kept, as the parcel: a piece each month, chosen, kept for ever |
| "A Plus badge on your avatars" | Dropped from Home: Home shows nothing about paying. A line in the Shop instead |

### What a subscription could add without breaking the product

The test for each candidate: is it still kind if the pair cancels, if only one partner cares, and
if they are fifteen?

| Candidate | Verdict | Why |
| --- | --- | --- |
| A piece every month, chosen, kept | **Yes** | Nothing is taken back; every piece is also sold for coins |
| Keepsakes: a printed or exported book of the room and the notes | Later | Honest and loved, but none of it is built (`gameplay-home.md`, mechanic 24). Viewing stays free; only the print or export is Plus |
| A vote on which piece is made next | Later | Cheap, and it is what supporters of a small app like |
| More coins, faster coins, a daily gift | No | The pacing test has no room and the rule is "no drips" |
| Paid streak slack (freezes, more restores) | No | It sells relief from a loss the app itself makes. The gameplay vision asks for a kinder streak for everybody, and US state suits against Snap name streaks |
| A longer Inbox or note history | No | Reads as paying for your own memories; Snapchat's 2025 storage cap drew exactly that anger |
| Question, word or date packs every month | No, for now | A promise of content each month from a team of two. If a month is missed, payers are the first to notice |
| Items only Plus can have | No | "No item that is only for sale for money" |
| Limits on notes, photos, widgets, games | No | These are the pair's connection |
| Labs as early access | No | App Review 2.5.19 wants every feature complete and described; Labs is neither |

## 2. Research

Sources and how each was read are in [Evidence](#evidence). The earlier notes outside the repo
("Ourio Plus for couples") were treated as leads: most of their numbers held, and the ones that
did not are listed there.

### What couples and cozy apps charge

| App | Monthly | Yearly | Covers both partners | Trial |
| --- | --- | --- | --- | --- |
| Between | $2.99 | $13.99 or $24.99 (listing disagrees with itself) | says "for you & your partner" | not found |
| Widgetable | $4.99 | $19.99 | not found | not found |
| TwoGether | $4.99 | $34.99 | yes: "One partner subscribes - Both get Premium" | 3 or 7 days |
| Cupla | $4.99 to $7.99 | $34.99 to $59.99 | yes: "one subscription per couple, not per person" | 14 days, yearly |
| SumOne | $5.99 | $29.99 | not found | not found |
| Pookie | $9.99 | $29.99 or $34.99 | yes: "One subscription covers both of you" | not found |
| Lovewick | $9.99 | $29.99 | not found | not found |
| Love8 | $9.99 | $39.99 "For 2 Users" | yes | none |
| Candle | $12.99 | $39.99 or $49.99 | not found | not found |
| Paired | $14.99 | $74.99 to $79.99 | yes, while paired | 7 days, yearly only |
| Neko Atsume 2 | "Cat's Club Support" at $0.99, $1.99, $2.99, $5.99 | | single player | none |
| Finch | Plus $9.99 (periods not shown on the listing) | $69.99 | single player | not found |

What this says:

- Two belts. Apps that sell coaching and question libraries charge $10 to $15 a month. Apps that
  sell widgets, pets and cosmetics charge $3 to $6. Ourio is in the second.
- **One pays, both get, is the norm**, done on the developer's server while the two are linked.
  Nobody uses Apple Family Sharing for it.
- Selling to the pair is itself the pitch: three listings lead with it.
- The cozy examples closest to Ourio's rules are **Neko Atsume 2**, whose subscription is called
  support and gates no play, and **Finch**, whose reviews call Plus fair because the free app is
  nearly the same. Finch also runs a Guardians programme in which supporters fund Plus for people
  who cannot pay (read from snippets only).

What reviews punish:

- A free limit that shrinks after launch. Lovewick went "from 10 free questions per day down to
  only 1".
- Being charged when a trial ends, and seeing only a yearly plan (Paired).
- Premium that works for one partner, and both being charged.
- Offers on every open (Love8, Pengu: "2-4 pop ups").
- Paid streak repair (noteit, Candle and Locket sell it; noteit's reviews say the app "became
  about streaks").

Paywall placement and what happens to content on cancel could not be read for any app without
installing it.

### Benchmarks

All from RevenueCat's State of Subscription Apps 2026 (115,000 apps) and Adapty's 2026 reports
(16,000 apps, 78,000 paywalls). None is for couples apps: no such figure is published anywhere.

| Question | Figure |
| --- | --- |
| Downloads that pay by day 35 | freemium 2.1%, hard paywall 10.7%; low-priced apps 1.4% |
| When people convert | 50.6% on install day; for freemium 23% come after six weeks |
| Where revenue comes from | 53% from paywalls seen in the first session; an onboarding paywall converts 0.85% of views against 0.23% later |
| Trials | 78 to 90% start on day 0. Trial to paid: 25.5% (4 days or fewer), 37.4% (5 to 9), about 43% (10 to 32); correlational |
| Trial cancellations on day 0 | 55.4% (3-day), 39.8% (7-day), 35.7% (14-day) |
| Yearly plans without a trial | renew better than those sold after a trial of 9 days or fewer |
| First renewal, monthly | 53 to 61% by category, **Social & Lifestyle lowest at 42%**; low-priced apps 60% |
| Still subscribed after a year | yearly 28% (low price 36%, high price 23%); monthly 8%; weekly about 1% |
| Yearly cancellations in the first month | 35% of them |
| Refunds | 2.7% at low prices, 4.5% at high; 7.7% in India and South-East Asia |
| Failed payments | 14 to 15% of App Store cancellations |
| Median prices | $10 a month, $34.80 a year |
| Lifestyle, median app | **$0.70 of revenue per install in a year**; the top 10% of apps take 97.9% of the category |
| Apps selling a subscription and consumables | 10.7% (2.5% also sell a lifetime unlock) |
| Regional price level | India 0.6, Turkey and Indonesia 0.7, Brazil 0.9, large EU countries 1.2 of the US price |

What this says for Ourio:

- **A two-person app cannot use the thing that converts.** Half of all conversions and half of
  the revenue come from a paywall in the first session. Ourio's second partner must come in and
  pair for nothing, and the owner's rule keeps selling inside the Shop. Expect about half the
  freemium median or less.
- **Low price keeps people.** At low prices a yearly plan holds 36% after a year, against 23%.
- **A trial is weaker here than the averages suggest.** Its strength is the first-session
  paywall, which Ourio will not have. Half of short-trial users cancel the same day.
- **Social & Lifestyle keeps monthly subscribers worst of all categories.** A reason to return
  each month matters more than the offer.
- Nothing was found on payer rates among teenagers, on Ask to Buy, on tip jars, or on whether a
  subscription eats pack sales.

### One subscription, two people

| Way | Verdict |
| --- | --- |
| **The server gives Plus to the pair of whoever paid** | **Use this.** The category norm. No guideline forbids it; none allows it in words |
| Apple Family Sharing | No. It cannot be switched off once on, reaches up to five other family members, and needs both in one Apple family, which long-distance pairs often are not |
| Apple Group Purchases (seats with invitations) | Not yet. Announced at WWDC26, on sale to customers "this winter"; the seat endpoints work in the sandbox only. Each seat sells at full price by default, and its developer-run invitations need the In-App Purchase key and the Declared Age Range API. Look again when it is live |
| Each partner pays | No. It is the complaint, not the model |

Gifting: Apple has no way to give an auto-renewable subscription to another Apple Account, and
offer codes may not be sold (Schedule 2, 3.13(c)). So "gift Plus to your partner" is simply what
buying is: one partner pays and both have it. The app should say it that way.

### Apple's rules that shape the design

- **3.1.2(a)**: a subscription gives "ongoing value", runs at least seven days, and may "include
  consumable credits, gems, in-game currencies". The subscriber gets it "without performing
  additional tasks, such as ... checking in to the app a certain number of times". So a parcel
  arrives because the month was paid, never because someone opened the app.
- **3.1.2(a)**: an app moving to subscriptions "should not take away the primary functionality
  existing users have already paid for". Nothing bought with coins changes.
- **3.1.2(b)**: nobody should "inadvertently subscribe to multiple variations of the same thing".
  A pair that has Plus is never offered it again.
- **The purchase screen** shows the name, the length, what is included, and the full price as "the
  most prominent pricing element", with a way to restore and links to the Terms and the Privacy
  Policy, both in the app and in the App Store metadata.
- **A trial toggle is rejected** since January 2026. There is none here.
- **3.1.1**: bought currency "may not expire". Parcels do not either.
- **2.5.19 and 2.3.1**: no dormant features, and what a remote flag can switch on must be in the
  reviewed build and described in the review notes.
- **4.5.4**: no promotional push without opt-in. Plus sends none.
- **5.6**: no manipulative practices.
- **Account deletion**: the app must tell a subscriber that Apple keeps billing and ask them to
  cancel first.
- **Small Business Program**: 15% instead of 30% under $1M a year. On $3.99 Apple keeps $0.60;
  in the EU, VAT comes off first. The standard rate also falls to 15% after a subscriber's first
  paid year.

### Thirteen to seventeen

- The Kids Category rules (1.3) apply only to apps in that category. No guideline covers minors'
  purchases in a general app.
- Ourio asks an age range in onboarding and stops under 13. The answer can be skipped, and the
  server does not yet store the band (`targeting.ts` says so).
- **Texas SB 2420** has been in force since 2026-06-04: Apple asks a parent's consent for
  downloads, purchases and "significant changes" for minors with new Apple Accounts there. Law
  firms read adding monetization as a significant change. Utah follows in May 2027; California in
  January 2027.
- **Ask to Buy** leaves a purchase pending; the app must wait calmly and deliver later. The coin
  machine already has that state.
- **EU**: the consumer authorities' 2025 principles for in-game currency ask for prices in real
  money and design "respectful of different consumer vulnerabilities". The Digital Fairness Act,
  proposed on 2026-11-11 and not law, would require a reminder and express consent before a trial
  becomes paid. The minors guidelines under the Digital Services Act ask for streaks and pushes to
  be off by default for minors (they exempt small enterprises, and are voluntary).
- **US**: the FTC's cases (Epic, Genshin, Amazon Prime) are about purchases nobody meant to make
  and cancelling made hard. The click-to-cancel rule was struck down in 2025; a new one is in
  preparation.

A subscription with no trial, one price shown in real money, no currency in between and a cancel
line on the purchase screen is on the safe side of every one of these.

## 3. Options

Five complete models. Scores are judgments from 1 to 5.

| | 1. Coins only | 2. Coins and Plus parcel | 3. Coins and Plus comforts | 4. Plus only | 5. Supporters |
| --- | --- | --- | --- | --- | --- |
| Free | everything | everything | everything; streak and history get paid extras | everything | everything |
| Sold | packs | packs; a parcel a month | packs; streak slack, long history, monthly packs of questions | a parcel a month; no packs | three tiers that give nothing but thanks |
| Price | $0.99, $4.99, $9.99 | $3.99 a month, $29.99 a year | $4.99 a month, $29.99 a year | $3.99 a month, $29.99 a year | $0.99, $2.99, $5.99 a month |
| Kind | 4 | 5 | 2 | 5 | 5 |
| Income | 2 | 3 | 3 | 2 | 1 |
| Work | done | 3 to 4 weeks | 8 weeks or more, then content each month | 3 to 4 weeks | 1 to 2 weeks |

### 1. Coins only

What [economy.md](economy.md) plans today. Packs shorten the wait for a piece.

- Paywall: the Coins sheet, opened from the Shop.
- For: built; no recurring charge; nothing to explain.
- Against: a pair can spend $27 in its whole life. Coins are a currency between the price and the
  thing, which is what EU consumer authorities ask games to make plain, and what parents like
  least.
- Economy: packs move the minted line, not the pricing.

### 2. Coins and the Plus parcel (recommended)

Packs for one piece now; Plus for a piece every month.

- Paywall: one row in the Shop, one in Settings.
- For: keeps every rule; nothing rented; one mechanism, so little can go wrong; reuses the
  catalogue and the wrapped-gift code.
- Against: its worth is the Shop's depth, so it needs one or two new pieces a month. It will take
  some pack sales, since a parcel is the cheaper way to a top piece. It is less exciting than
  "premium".
- Economy: mints nothing. A parcel is a piece granted at no coin cost, written to the ledger as
  its own kind so the economy report can show it apart. The pacing test is untouched.

A variant, **a coin allowance** (300 coins each paid month instead of a parcel), is simpler to
build and Apple allows it. It is not recommended: it is a drip in everything but its period, it
moves the minted line, and "coins" is a weaker gift than "choose something together".

### 3. Coins and Plus comforts

The earlier notes' proposal: streak holidays and extra restores, a long "chronicle" of the pair
with "a year ago today", a monthly story of the pair, and monthly packs for the games.

- For: these are what the category sells, and streak slack has the best retention evidence of
  anything here.
- Against: it charges for relief from the streak's own loss, when the gameplay vision asks to
  remove that loss for everyone. It puts memories behind a price. It promises content monthly.
  Almost none of it is built. And each comfort ends on cancel, so the pair loses something.

### 4. Plus only

Take the packs away; coins are only earned; Plus is the one thing sold.

- For: the simplest story for a parent or a regulator: no bought currency at all. One product.
- Against: throws away built and tested code, and the one-off buyer who wants one piece and no
  subscription. Worth returning to if packs sell badly or draw complaints **(needs numbers)**.

### 5. Free, with supporters

Like Neko Atsume 2: "support Ourio" at three prices, all giving the same thank-you.

- For: the kindest; a week of work.
- Against: Apple requires "ongoing value", so a pure thank-you needs something attached, and then
  it is model 2 with a smaller gift. No figures were found for what supporter tiers earn.

**A lifetime price** (one payment, about the yearly price) fits "nothing expires" best and is
safest for young users. 14% of apps offer one. It is left out of the first version because a
parcel a month for ever is an open promise; it can be added as "36 parcels, paid once" when the
catalogue is deep enough.

## 4. Paywall design

### Where it stands

| Place | What is there |
| --- | --- |
| Shop | One row, "Ourio Plus", under the balance. Tapping it opens the Plus sheet |
| Settings | One row, "Ourio Plus", with the state; opens the same sheet |
| Inbox | One item when a parcel arrives, and one when the partner sets Plus up. Neither sells |
| Everywhere else | Nothing |

Rules, each one testable:

- **The Plus sheet opens only from a tap on one of the two rows.** No event, timer, launch, push,
  deep link from a notification or empty balance opens it. This one rule is what keeps it out of
  every bad moment: a partner waiting on a note, a game turn, a streak that just broke, an
  unpairing.
- Never on Home, in the room, in onboarding, in pairing, in a game, in the composer, in a widget.
- Never in a push. Plus sends no promotional notification at all.
- No price outside the Plus sheet. The Shop row says "Ourio Plus" and nothing about money.
- No countdown, no "limited", no "last chance", no crossed-out price, no "most popular", no
  preselected yearly plan made to look like the only one, no "No thanks, I don't care" button.
- A pair that has Plus sees no offer anywhere.
- No "ask your partner to pay" button. One partner must never be nudged to bill the other.
- When the balance is short of a piece, the Shop says what it says today. It adds no line about
  Plus.

### Copy

Plain and warm, about the two of them, in the cat's world. It says what happens with money in the
same size as everything else.

| Say | Never say |
| --- | --- |
| "A parcel every month, for the two of you." | "Unlock", "premium", "upgrade", "pro" |
| "Choose any one thing in the Shop. It's yours to keep." | "Don't miss out", "only today" |
| "One of you pays. You both have it." | "Your partner is waiting", "treat them", "show you care" |
| "$3.99 a month. Cancel any time; what you chose stays." | "Free" for anything that later bills |
| "Mochi says thanks." | Any line that says the cat is sad, hungry or waiting |

### Screens

The Shop row, with and without Plus:

```
┌──────────────────────────────────────┐   ┌──────────────────────────────────────┐
│  Shop                        128 ◎   │   │  Shop                        128 ◎   │
│ ┌──────────────────────────────────┐ │   │ ┌──────────────────────────────────┐ │
│ │ ✉  Ourio Plus                  › │ │   │ │ ✉  A parcel is here            › │ │
│ │    A parcel every month          │ │   │ │    Choose something together     │ │
│ └──────────────────────────────────┘ │   │ └──────────────────────────────────┘ │
│  This week's set                     │   │  This week's set                     │
```

The Plus sheet, for a pair without it:

```
┌──────────────────────────────────────┐
│                 ✕                    │
│          [ a wrapped parcel ]        │
│                                      │
│            Ourio Plus                │
│  A parcel every month, for the two   │
│  of you.                             │
│                                      │
│  ✉  Each month, choose any one thing │
│     in the Shop. It's yours to keep. │
│  ♥  One of you pays. You both have   │
│     it.                              │
│  ∞  Nothing runs out. If you stop,   │
│     everything you chose stays.      │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ ○ Monthly      $3.99 a month     │ │
│ │ ○ Yearly       $29.99 a year     │ │
│ └──────────────────────────────────┘ │
│ ┌──────────────────────────────────┐ │
│ │      Start for $3.99 a month     │ │
│ └──────────────────────────────────┘ │
│ Renews each month until you cancel.  │
│ Cancel any time in Settings > your   │
│ name > Subscriptions.                │
│                                      │
│ Restore purchase · Terms · Privacy   │
└──────────────────────────────────────┘
```

- Monthly is selected first: it is the smaller promise. The yearly row shows its full price, not a
  price per month, and no "save 37%" badge.
- The button repeats the price of the selected plan, so the amount billed is the largest price on
  the screen.
- The whole Shop is still free to browse behind it; the sheet is a `BilletSheet` with one
  `PrimaryButton`, as the design system asks.

The same sheet for the partner who paid, and for the one who did not:

```
┌──────────────────────────────────────┐   ┌──────────────────────────────────────┐
│            Ourio Plus                │   │            Ourio Plus                │
│  You set this up for you and Mia.    │   │  Leo set this up for the two of you. │
│                                      │   │                                      │
│  Parcels so far            4         │   │  Parcels so far            4         │
│  Waiting to be opened      1         │   │  Waiting to be opened      1         │
│  Next parcel               12 Dec    │   │  Next parcel               12 Dec    │
│  Monthly, $3.99                      │   │                                      │
│                                      │   │  Leo looks after the subscription.   │
│  [ Open the parcel ]                 │   │  [ Open the parcel ]                 │
│  Manage subscription ›               │   │                                      │
│  Cancelling keeps everything you     │   │                                      │
│  both chose.                         │   │                                      │
└──────────────────────────────────────┘   └──────────────────────────────────────┘
```

- The partner sees no price, no manage link and no buy button.
- Either partner can open a parcel. The other finds the piece wrapped in the room, with who chose
  it, through the gift path that exists.

Opening a parcel:

```
┌──────────────────────────────────────┐
│  Choose one thing                    │
│  It's a gift: no coins needed.       │
│                                      │
│  [tower]   [donut bed]   [rainy      │
│                           window]    │
│  [plum ink] [rose seal]  [yarn]  …   │
│                                      │
│  Not now  (the parcel waits)         │
└──────────────────────────────────────┘
```

### States, as the pair sees them

| State | The one who pays | The partner |
| --- | --- | --- |
| Just bought | "Mochi says thanks. Your first parcel is here." | Inbox: "Leo set up Ourio Plus for the two of you. A parcel is waiting." |
| Ask to Buy pending | "Waiting for a parent to say yes. Nothing to do here." | nothing |
| A month renews | Inbox: "A parcel arrived." | the same |
| Payment failed, grace period | A quiet line in the Plus sheet: "Apple couldn't take the payment. Check it in Settings." Parcels keep coming | nothing |
| Cancelled, period not over | "Plus runs until 12 Dec. Everything you chose stays." | nothing |
| Ended | The Shop row is "Ourio Plus" again. Unopened parcels still open | the same; **no message that the partner stopped** |
| Refunded | The parcel from the refunded month goes if unopened; if opened, its price is owed in coins, as a pack refund works today | the balance line, as today |
| Both paid | "You both have Plus, so two parcels come each month. One is enough: either of you can cancel." with the manage link | the same on their phone |
| Unpaired | Plus goes with the one who pays, to their next pair | A plain line that parcels came from the partner's Plus; nothing chosen is lost |

The partner is never told that the other cancelled, was refunded or failed to pay. That is a
conversation for the two of them, not for the app.

### Restore and manage

- **Restore purchase** on the Plus sheet runs `AppStore.sync()` and sends what it finds to the
  server. A subscription already tied to another Ourio account stays with that account; the sheet
  says "This subscription belongs to another Ourio account on this Apple Account."
- **Manage subscription** opens Apple's sheet (`showManageSubscriptions`). The app has no cancel
  flow of its own, no "are you sure", no offer on the way out.
- **Settings > Delete account** tells a subscriber that Apple keeps billing until they cancel,
  with the same link, before it deletes.
- **Refund**: a "Request a refund" row under Manage (`beginRefundRequest`). Apple decides.

## 5. Recommendation in detail

### The product

| | |
| --- | --- |
| Group | `Ourio Plus`, one level |
| Products | `com.ourio.app.plus.monthly` ($3.99), `com.ourio.app.plus.yearly` ($29.99) |
| Introductory offer | none |
| Family Sharing | off (it cannot be undone) |
| Multiseat purchases | opted out at creation (it is on by default for new subscriptions) |
| Billing grace period | 16 days, all renewals |
| Offer codes | a few one-time codes for support and for the couples beta; never sold |
| Win-back offers | none at first. If used later: one parcel's worth, shown by Apple in its own places, never by a push |

**Parcels.**

- One per paid month. Monthly: one at purchase and one at each renewal. Yearly: one at purchase
  and one on the same day of each following month, twelve in all, whether or not anyone opens the
  app.
- A parcel holds a choice of any one piece the Shop sells for coins that the pair does not own.
  Treats are not in it.
- Parcels wait for ever and pile up. They survive cancelling. On an unpairing, unopened ones go
  with the partner who paid; opened pieces follow the kept-purchases rule both partners have today.
- A pair that owns everything keeps its parcels for the next new piece. The Plus sheet says so
  before purchase when fewer than three pieces are left to choose.

**Prices.** $3.99 is under every couples app found but Between, and low prices keep subscribers
best. $29.99 is the commonest yearly price in the category and 37% under twelve months. A parcel
can hold a 540-coin piece, about $4.50 in packs, so Plus is the better deal for a pair that would
buy every month, and a pack is still the way to buy once.

**Regional prices.** Take Apple's automatic prices from the US price, then lower by hand where
the benchmark price level is far below: India and Pakistan to about 0.6, Turkey, Indonesia, Egypt
and Vietnam about 0.7, Brazil and Mexico about 0.9. Expect more refunds there (7.7% against 3.4%).
Do the same for the packs so the two stay in step.

**No trial**, because:

- a parcel is a kept thing, and each partner's Apple Account has its own trial, so a pair could
  take two top pieces free;
- trials are where the complaints and the new rules are (charged after trial; the EU's proposed
  reminder and consent);
- half of short trials are cancelled the day they start, and yearly plans sold with no trial
  renew better than those after a short one;
- the app has no first-session paywall, which is where trials do their work.

What it costs: some pairs who would have tried will not. If the payer rate is under target after
three months, test a 14-day trial on the yearly plan, for adults, with the first parcel on the
first payment.

**Thirteen to seventeen.** In the first version an account that answered "13 to 17" sees no Plus
row (and, by the same reasoning, the owner may want the same for packs). Skipped answers see it;
Apple's own parental consent and Ask to Buy then apply. This needs the age band stored on the
server, which it is not today.

### Expected numbers

Nothing here is measured. Each line is a benchmark moved to Ourio's case.

| Step | Figure | From |
| --- | --- | --- |
| Paid by day 35, freemium, low price | 1.4% of downloads | RevenueCat 2026 |
| No first-session paywall | about half of that | Adapty: 53% of revenue from first-session paywalls |
| Per paired pair (two downloads, and only pairs that formed) | **0.5 to 2% of pairs by day 90** | a guess |
| Mix | half monthly, half yearly | RevenueCat: 42% and 34% of subscriptions sold |
| A monthly subscriber stays | about 4 paid months | first renewal 42 to 60% |
| Gross from a paying pair, first year | about $23 | $16 monthly, $30 yearly |
| After Apple's 15% | about $19.50, less VAT in the EU | Small Business Program |
| **Per paired pair, first year** | **$0.10 to $0.40** | |

| Paired pairs | Paying pairs at 1.5% | Income a year |
| --- | --- | --- |
| 1,000 | 15 | about $300 |
| 10,000 | 150 | about $2,900 |
| 100,000 | 1,500 | about $29,000 |

So Plus is not what makes Ourio pay at today's size, and nothing sold in a Shop that few pairs
open will be. What decides the income is how many pairs form and stay. **(needs numbers:**
pairs formed a month, both-active on day 30, and the share of active pairs that open the Shop
at all; if `ShopOpened` is rare, a Shop-only paywall reaches almost nobody and the owner should
decide whether the Settings row is enough or the rule needs one more quiet place.**)**

### The first slice

One engineer, three to four weeks, behind a new remote flag `plus` (`off`, `on`; default `off`,
`draft`), separate from `payments`. Docs only for now; this is the design to build from.

**Contracts** (`packages/contracts`):

- `domain/src/plus.ts`: the two products, the group, and `parcelChoices` (derived from the Shop
  catalogue).
- A wire type `PlusState`, an enum with associated values and no optional that means a mode:
  `none`, `active {plan, renewsOn, paidBy: "me" | "partner"}`, `ending {until, paidBy}`,
  `grace {paidBy}`, `ended`.
- `ShopResponse` and `ShopChanged` gain `plus: PlusState` and `parcels: [{id, arrived}]`, so both
  phones learn of a parcel through the socket they already hold.
- Golden fixtures for each. `coin-packs-sync.test.ts` is split: it asserts today that every
  StoreKit product is a consumable pack, and gains a twin for the subscription group.

**Server** (`packages/backend/payments`, `platform`):

- `POST /v1/purchases` branches on the signed transaction's `type`. `Auto-Renewable Subscription`
  goes to a new `subscribe` path; consumables are untouched.
- A D1 table `subscriptions`, one row per `originalTransactionId`: the **payer's account id**,
  product, state, `expires_at`, `grace_expires_at`, whether it renews, environment. A table
  `parcel_grants` with ids `parcel:<originalTransactionId>:<n>`, written once each.
- The payer is the account, not the pair, so Plus follows the person through an unpairing. The app
  passes the account's UUID as `appAccountToken`; the server refuses a transaction whose token is
  another account's, and binds one with no token to the caller.
- A pair has Plus while either member has a row that is `active`, `ending` or `grace`.
- Notifications V2: handle `SUBSCRIBED`, `DID_RENEW` (with `BILLING_RECOVERY`),
  `DID_CHANGE_RENEWAL_STATUS`, `DID_FAIL_TO_RENEW` (with `GRACE_PERIOD`), `GRACE_PERIOD_EXPIRED`,
  `EXPIRED`, `REFUND`, `REFUND_REVERSED`, `REVOKE`; record the rest. The handler must decode
  `signedRenewalInfo`, which it ignores today. The route stays outside the flag, as now.
- `PairRoom`: commands `GrantParcel {id}` and `OpenParcel {id, offer}`. Opening reuses the order
  path at price 0 and the grants that exist (`GrantItems`, `GrantInks`, `GrantPostage`), and writes
  a ledger entry of a new kind `parcel` with amount 0, so the economy report shows parcels apart
  and the minted line does not move.
- Yearly parcels: a daily Cron Trigger grants what is due. Nothing depends on a phone.
- Refund: an unopened parcel of the refunded period is removed; an opened one is entered as
  `refund:` for the piece's price, the rule packs already follow. Nothing else is taken back.
- Routes are a 404 while `plus` is off for the pair, like the purchase routes.
- With no In-App Purchase key the server can do all of the above from the phone's signed
  transaction and Apple's signed notifications. The key is needed to reconcile after missed
  notifications, to bind a subscription redeemed outside the app (offer codes), and to answer
  refund questions. Get the key before launch; it is already step 3 of the owner's payments list.

**App** (`packages/ios/payments`, `features`):

- `Payments` gains `plusProducts()`, `subscribe(_:)` and `plusEntitlement()`; `StoreKitPayments`
  stops ignoring products outside the coin catalogue; `MockPayments` gets switches for renew,
  fail, grace, refund and expire.
- `FeatureShop`: a `PlusMachine` (`loading`, `offered`, `buying`, `waiting` for Ask to Buy,
  `delivering`, `mine`, `partners`, `unavailable`) with its transition table tested, rejected
  events included; a `ParcelMachine` for the choosing.
- The Plus sheet in the design system's own parts, not `SubscriptionStoreView`, so it looks like
  Ourio and carries every line Apple requires.
- Remove `PlusPass`, `PlusHero`, the `plus.mockOn` flag, the crown on the couple button and the
  unused `plus` field on shop items.
- No StoreKit in a `none` build, as today; `check-archive.sh` keeps guarding that.

**Before the slice, in the Shop:** window views and lightings become Shop pieces, and a habit of
one or two new pieces a month starts. That is worth doing with or without Plus: it is the sink
[economy.md](economy.md) asks for.

### App Store Connect steps

Only the owner can do the ones marked **owner**; agents never touch the account.

| Step | Who |
| --- | --- |
| Ask App Review (a consultation session) whether one subscription may cover a linked partner's account | **owner** |
| Sign the Paid Apps Agreement; add bank details; file the US tax form (W-8BEN for a person outside the US) | **owner** |
| Declare trader status for the EU Digital Services Act (an address, phone and email shown on the product page) | **owner** |
| Ask an accountant whether App Store income fits unregistered activity in Poland or needs a registered business | **owner** |
| Enrol in the Small Business Program (it takes effect 15 days after the fiscal month in which it is approved) | **owner** |
| Answer the new age-rating questions, "Dating and Relationships" among them, by 2027-01-12; change "In-app purchases" to yes | **owner** |
| Create the In-App Purchase key; put it in Proton Pass, vault Agents | **owner** |
| Create the subscription group and both products; names, descriptions and a review screenshot for each; prices by storefront | **owner**, from a list an agent prepares |
| Leave Family Sharing off; opt out of multiseat purchases; set the grace period to 16 days | **owner** |
| Set the Server Notifications V2 URLs ([payments.md](payments.md)) | **owner** |
| Add the Terms link to the App Store description or set a custom licence agreement; check the Privacy Policy URL | **owner** |
| Create a sandbox tester | **owner** |
| Write the review notes: what Plus is, that it covers both linked partners, that the `plus` flag switches it on, a test pair | agent drafts, **owner** submits |
| Submit the first subscription together with a new app version built with `BILLET_PAYMENTS=storekit` | **owner** approves |

### Test plan

**StoreKit configuration.** Add the group and both products to `apps/ios/Ourio.storekit`. Run
`xcodebuild test` with `SKTestSession` on a runtime before iOS 26.3: the 26.4 and 26.5 Simulators
do not load `.storekit` files from `xcodebuild`.

| Case | How | Expect |
| --- | --- | --- |
| Buy monthly | `buyProduct` | `mine` on the buyer, `partners` on the other phone, one parcel, one Inbox item each |
| Renew | `forceRenewalOfSubscription`, or `timeRate` | a second parcel, granted once however many times the notification comes |
| Yearly | buy, then move the server clock | a parcel a month, twelve, none after |
| Ask to Buy | `askToBuyEnabled` | `waiting`; approve gives `mine`; decline goes back to `offered` with no error tone |
| Paid, server down | block the route | `delivering`; settles on the next foreground; never charged twice |
| Payment fails | `shouldEnterBillingRetryOnRenewal`, `billingGracePeriodIsEnabled` | `grace`, parcels continue; after grace, `ended` |
| Cancel | `expireSubscription` | `ending`, then `ended`; all pieces and unopened parcels stay |
| Refund | `refundTransaction` | unopened parcel gone; opened one owed in coins; the partner told nothing |
| Both buy | two accounts in one pair | two parcels a month; the "one is enough" line |
| Restore on a second account | `AppStore.sync()` | stays with the first account |
| Unpair, pair again | | Plus and unopened parcels follow the payer; pieces follow the kept rule |
| A pair that has Plus | open the Shop on both phones | no offer, no price anywhere |
| Age band 13 to 17 | | no Plus row |
| The sheet | a UI test that walks Home, the Inbox, a game, the composer, onboarding | the Plus sheet never appears without a tap on its row |

Server: unit tests for each notification type and for the same notification twice, built with
`test/app-store-signer.ts`; the pacing test and the economy report unchanged by a parcel.
Sandbox: a tester set to renew every 5 minutes covers twelve renewals in an hour. TestFlight
renews once a day, six times. Then one real purchase on the owner's own account, refunded.

### Success, and when to stop

Read at 90 days from the day `plus` is `on` for new pairs, with at least 300 pairs that saw the
Shop row. With fewer, read the direction and talk to couples; do not call it
([experiments.md](experiments.md)).

| | Works | Stop |
| --- | --- | --- |
| Paying pairs per 100 paired pairs | 1.5 or more | under 0.5 |
| Monthly subscribers who renew once | 55% or more | under 35% |
| Parcels opened within 14 days | 70% or more | under 40%: the gift is not wanted |
| Refunds | under 4% | over 8% |
| "My partner can't see it", charged twice | none | any that repeats: each is a defect |
| Both partners active on day 14, `on` against `off` | not lower | lower: the offer harms the product |
| Coins minted per pair | unchanged | changed: Plus became a faucet |
| Pack income per pair | not much lower | read, not a stop: packs may give way to Plus |
| Reviews that mention price or paywall | few | a pattern |

Stopping means: no new sales (the row goes for pairs without Plus), every subscriber keeps Plus
until they cancel, and they are told in the Plus sheet. Nothing chosen is taken back.

Also count, for the questions this document could not answer: which row sold (Shop or Settings),
pairs where the second partner paid after the first lapsed, and what parcels are spent on.

### Legal and privacy checklist

Not legal advice; a list of what changes. A lawyer should read the terms before real money.

**`docs/legal/terms.md`**

- Replace the placeholder under Coins. Add a Purchases section: Apple sells and bills; prices are
  shown before purchase; refunds are Apple's to give, at reportaproblem.apple.com.
- Ourio Plus: what it is; that it renews until cancelled; how to cancel; that it covers the buyer
  and the partner they are paired with; that it follows the buyer if the pair ends; that chosen
  pieces and unopened parcels are kept.
- That a refund takes back the parcel or its price in coins.
- Minors: under the age of majority, a parent or guardian must agree to a purchase.
- The EU right of withdrawal is handled by Apple as the seller.

**`docs/legal/privacy-policy.md` and `docs/privacy.md`**

- New data: for a subscription, the account that paid, the product, Apple's transaction id, and
  when it ends. The coin ledger stores no account today, so this is a change. Still no Apple
  Account, name, email or card.
- Why: to give the pair what was bought. How long: while the account exists, then as accounting
  rules require.
- The partner learns that the other set Plus up. Say so.
- Deleting an account does not cancel the subscription.

**`docs/legal/app-privacy-labels.md`**: add **Purchases > Purchase History**, linked to the user,
for App Functionality.

**`docs/legal/age-rating.md`**: "In-app purchases" becomes yes; add the row for the Dating and
Relationships descriptor and the owner's answer.

**`docs/legal/app-store-listing.md`**: the Terms and Privacy links in the description; the
subscription's name, length and price as Apple asks.

**Elsewhere**

- [analytics.md](analytics.md): new events (`PlusOpened` with the row it came from, `PlusBought`,
  `ParcelOpened`), with pair-level counts only.
- [release-flags.md](release-flags.md) and [experiments.md](experiments.md): the `plus` flag.
- Texas and the states that follow: adding purchases is a "significant change"; follow Apple's
  guidance for it when the build is submitted.
- Watch: the EU Digital Fairness Act, the UK subscription rules due in 2027, Apple Group Purchases.

## Open questions for the owner

1. Is a parcel that holds *any* piece right, or should the dearest pieces be left out?
2. Should accounts aged 13 to 17 be offered Plus at all, and the packs?
3. Is the Shop row enough, given the Shop may be rarely opened, or may Settings and one more quiet
   place carry it? **(needs numbers)**
4. Packs first and Plus later, as recommended, or both in one review to spare a second round of
   owner steps?
5. How will Ourio answer Apple's "Dating and Relationships" question?

## Evidence

How each source was read on 2026-11-25: **opened** (the page was fetched and read), **snippet**
(seen in search results only), **weak** (vendor marketing, an estimate, or an aggregator).
Reports were read through a summarising fetch, so check a figure's wording before quoting it
outside this document.

### Benchmarks

- RevenueCat, State of Subscription Apps 2026 and its two insight posts, opened
  ([report](https://www.revenuecat.com/state-of-subscription-apps-2026/),
  [part 2](https://www.revenuecat.com/sosa-2026-insights-part-2)); trial length, opened
  ([post](https://www.revenuecat.com/blog/growth/free-trial-length)).
- Adapty, State of In-App Subscriptions 2026 and State of Paywalls 2026, opened
  ([subscriptions](https://adapty.io/blog/mobile-app-monetization-2026),
  [paywalls](https://adapty.io/state-of-paywalls/report/)).
- Corrections to the earlier notes: "23% convert after six weeks" is freemium only (19.2%
  overall); "14-day trials convert 43% against 33%" compares length buckets, not a test; monthly
  retention at a year is 6 to 14%, not 8 to 17%; the 3 to 4% refund figure is RevenueCat's, not
  Adapty's; Social & Lifestyle's first monthly renewal is 42%, below the 53 to 61% quoted.
- The report disagrees with itself on day-0 conversions (50.6% in one section, "a third" in
  another).
- Not found: payer rates for couples apps or teenagers, the effect of Ask to Buy, refund rates for
  consumables, results of win-back offers, tip-jar income, cannibalisation between packs and a
  subscription.

### Competitors

- App Store US listings, opened, for every app in the table; prices are from the In-App Purchases
  list, which shows no periods, so a period is given only where the label names one.
- Paired ([FAQ](https://www.paired.com/frequently-asked-questions),
  [partner access](https://support.paired.com/en/articles/164624-does-my-partner-have-to-pay-to-use-paired-premium-as-well)),
  Cupla ([help](https://www.cupla.app/help/en/articles/15051409-how-does-my-subscription-work)),
  opened.
- Snapchat's storage cap, opened
  ([TechCrunch](https://techcrunch.com/2025/09/29/snapchat-caps-free-memory-storage-launches-paid-storage-plans));
  the "#DeleteSnapchat" hashtag in the earlier notes could not be confirmed.
- Finch's Guardians programme and gifting: snippet (its help pages refused the fetch).
- Corrections to the earlier notes: Pookie is $9.99 a month and $29.99 or $34.99 a year, not $4.99
  and $24.99; "Paired's streaks broke when the daily question was paywalled" was not found.
- Revenue estimates for Finch, Paired and Candle exist only as weak vendor estimates and are not
  used here.

### Apple

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), last updated
  2026-10-16, opened; quotes above are verbatim.
- [Auto-renewable subscriptions](https://developer.apple.com/app-store/subscriptions/) and the
  licence agreement's Schedule 2, 3.8(b) and 3.13(c), opened.
- [Family Sharing cannot be turned off](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/turn-on-family-sharing-for-in-app-purchases),
  opened.
- Group Purchases: [What's New](https://developer.apple.com/app-store/whats-new/),
  [WWDC26 session 391](https://developer.apple.com/videos/play/wwdc2026/391/), and the StoreKit and
  App Store Server API pages, opened.
- One purchase for a linked account: no statement found; the staff reply is in
  [forum thread 826027](https://developer.apple.com/forums/thread/826027), opened.
- [Account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/),
  [Small Business Program](https://developer.apple.com/app-store/small-business-program/),
  [age ratings](https://developer.apple.com/help/app-store-connect/reference/age-ratings-values-and-definitions/),
  [age assurance](https://developer.apple.com/support/age-assurance/), opened.
- Trial toggles rejected: [RevenueCat](https://www.revenuecat.com/blog/growth/rip-toggle-paywall),
  opened, secondary.
- StoreKit tests on the 26.4 and 26.5 Simulators:
  [forum thread 826971](https://developer.apple.com/forums/thread/826971), opened.
- Notifications, grace period, offers, sandbox and TestFlight renewal rates: Apple's documentation
  and App Store Connect help, opened.
- EU commission terms from 2026-10-01 (15% for Small Business Program members): Apple's newsroom,
  opened; the exact effect on a subscription's second year was not found.

### Law and regulators

- Texas SB 2420: [Apple's notice](https://developer.apple.com/news/?id=sg176nne), opened; that
  adding monetization is a significant change is law firms' reading, secondary.
- Utah, Louisiana, California dates: secondary, and Louisiana's sources disagree.
- EU minors guidelines: the Commission's summary page, opened; the full text was not read.
- EU principles on in-game currency, the Digital Fairness Act proposal, the UK subscription
  rules' date: law-firm summaries, secondary.
- FTC: Genshin, Epic and Amazon Prime, opened on ftc.gov; the click-to-cancel rule's status,
  secondary.
- Apple as seller, VAT and refunds: Schedule 2 and Apple's Polish terms, opened.
- Polish unregistered activity: the tax office's guide, opened; whether it fits App Store income
  is not settled there.

### Code and docs read

`packages/ios/features` (FeatureShop: `CoinStore.swift`, `CoinsSheet.swift`, `ShopModel.swift`),
`packages/ios/payments`, `packages/backend/payments` (`payments-service.ts`,
`payments-repository.ts`), `packages/backend/platform` (`directory-schema.ts`,
`pairing-observer-live.ts`, `kept-purchases.ts`), `packages/backend/flags`
(`experiments.ts`, `targeting.ts`), `packages/contracts/domain` (`shop.ts`, `inks.ts`,
`postage.ts`, `coins.ts`, `coin-packs.ts`), `apps/ios/Ourio.storekit`, `docs/legal`, and
[payments.md](payments.md), [economy.md](economy.md), [gameplay-vision.md](gameplay-vision.md),
[gameplay-home.md](gameplay-home.md), [love-streak.md](love-streak.md),
[experiments.md](experiments.md), [release-flags.md](release-flags.md).
