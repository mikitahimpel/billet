# Payments

Ourio's **coins** are billet's one currency (owner decision, 2026-11-05). Stamps, the old app's
paid-only currency, are gone. Coins are earned in play (mini-games, feeding, notes) and, once
payments are on, also sold in packs as consumable in-app purchases through StoreKit 2. The server
keeps a ledger of the coins each pair has bought.
How coins are priced, tuned and refunded, and the plan for turning sales on, is in
[economy.md](economy.md).

**The first release ships without payments:** the app is built with `BILLET_PAYMENTS=none`, App
Store Connect has no in-app purchases, and the server's `payments` flag is off, so every
`/v1/purchases*` route answers 404 outside the dev stage. The packs and the ledger are already coins in the contract,
so turning payments on later needs no redesign.

## The `payments` flag (`payments.enabled`)

`payments` is a remote flag in the server's registry (`packages/backend/flags/src/experiments.ts`;
keys can't hold a dot, so `payments.enabled` is the key `payments`), with variants `off` and `on`:

| | |
| --- | --- |
| Default | `off`, status `draft`, on every stage: nobody gets `on` (the dev stage sells anyway, below) |
| Turn it on for a test pair | an override `payments = on` for that pair in the admin panel (Flags) |
| Turn it on for everyone | weight `on`, set it as the default and start it, once purchases exist in App Store Connect |
| Kill switch | kills it: every pair is off again at once |

While it is off for the caller's pair, `POST /v1/purchases`, `POST /v1/purchases/mock` and
`GET /v1/purchases` answer `404 NotFound`, before the body is read, exactly like a path that does
not exist. A caller with no session still gets the `401` first. A demo room has no pair, so it is
always off. `PaymentsSwitch` (`@billet/backend-payments/payments-switch`) asks the question;
`platform` answers it from `FlagsService` (`payments-switch-live.ts`), and tests use
`PaymentsSwitch.on` and `.off`. The mock route is still registered on the dev stage only. The App
Store notifications route is not behind the flag: Apple must always get its 200.

The dev stage ignores the flag: its purchase routes are on for every pair and demo room, so packs
can be tried there before the flag is on anywhere. `stage` and `prod` follow the flag.

The app reads the same flag from `GET /v1/flags` and never offers to buy coins while it is not
`on`, whichever store it was built with: a mock build on dev shows packs only for a pair with the
override `payments = on` (`CoinPacksModel.sells`).

## Coin packs

The canonical list is `coinPacks` in `@billet/contracts-domain/coin-packs`. The amounts and prices
are **placeholders** until the owner sets them:

| Product id | Coins | Price (USD) |
| --- | --- | --- |
| `com.ourio.app.coins.100` | 100 | 0.99 |
| `com.ourio.app.coins.550` | 550 | 4.99 |
| `com.ourio.app.coins.1200` | 1200 | 9.99 |

They belong to the Ourio app record in App Store Connect (`com.ourio.app`, SKU `ourio`), where the
owner creates them as consumables.

The app's copy (`packages/ios/payments/Sources/Payments/Resources/coin-packs.json`) and the Xcode StoreKit
configuration (`apps/ios/Ourio.storekit`) must sell
exactly these. A test in `contracts-fixtures` (`coin-packs-sync.test.ts`) fails if an id, a number
of coins or a price differs, or if a StoreKit product is not a consumable.

## Ink colours

Ink colours for text notes are sold one by one for coins (owner decision, 2026-11-05). One ink,
`ink-graphite`, is free and every pair owns it. Colours belong to the pair: one partner's purchase
is both partners'.

- **Catalog:** `inks` in `@billet/contracts-domain/inks`, with `{id, name, light, dark, price}`.
  `light` and `dark` are the hex colours on light and dark paper, and `price` is in coins. The
  colours and prices are placeholders the owner sets. An id is never reused.
- **The note:** `Note.Text` and `SendNoteRequest.Text` carry `ink`. A note written before inks has
  none and decodes as `ink-graphite`; the server always writes it out.
- **Owned inks:** the pair's `PairRoom` keeps the ones it bought (`owned_ink`, in the order it got
  them). A buy (below) adds one in the same commit as the coins it takes. `GrantInks` adds inks
  without coins, for bundles to come.
- **The check:** the room refuses a text note in an ink the pair does not own, with
  `400 {"_tag":"InkNotOwned","ink":…}`, and stores nothing. An ink the catalog does not sell is a
  `400 InvalidRequest`.
- **`GET /v1/inks`:** answers `InksResponse {inks, owned}` (session, paired; `no-store`), with the
  free ink first in `owned`.

## The pair wallet

Coins are the pair's, like inks, and live in its `PairRoom`: a `wallet` row (the balance, and what
care earned today against each daily cap) and the `coin_entry` ledger, one row per id. Nothing on
the phone adds coins.

- **Earning:** each cat journal entry the room stores earns its reward in the same commit, as the
  entry `earn:<cat entry id>`. Rewards and caps are in `@billet/contracts-domain/coins` and are
  placeholders until the owner sets them: feeding, petting, playing and watering 1 each (care, 10
  a day), a note 5 and a photo 10 (notes, 30 a day), a game won 10 and lost 3 (games, 40 a day);
  sleep and shooing earn nothing. The entry that crosses a cap is cut to what is left. The day is
  the cat's local day (`utcOffsetSeconds`), so the caps reset at the couple's midnight. A note
  sent before the cat is adopted is not journalled but earns all the same, as `earn:<note id>` on
  the UTC day.
- **Buying:** `POST /v1/shop/buy {id, item[, expectedPrice]}` (session, paired) buys one ink at the server's
  catalog price; `expectedPrice` is what the buyer saw, only a cap (`409 PriceChanged {price}` when
  the price rose, nothing charged; a lower price is charged). The room takes the coins (`spend:<id>`, a negative amount) and
  adds the ink in one decision, and answers `BuyResponse {entry, balance, granted, owned}`. A retry
  with the same `id` answers with the first buy and charges nothing. `409 NotEnoughCoins {needed,
  have}` and `409 AlreadyOwned {itemId}` (also for the free ink) refuse it; an ink the catalog
  does not sell is a `400 InvalidRequest`.
- **The shop:** the furniture catalog (`roomItems`, `bundles`, `featuredSets`, `treatPrice`) is in
  `@billet/contracts-domain/shop`; every room starts with `starterItems`. `GET /v1/shop` answers
  `ShopResponse {balance, inks, items, wishlist}`. `POST /v1/shop/orders {id, offer}` buys an ink,
  a room piece, a set's missing pieces at the set price, or a treat; the room prices it, takes
  `spend:<id>`, adds what was bought, drops it from the wishlist and answers `OrderResponse {entry,
  shop}`. The week's featured set sells at half price, and its week is read 12 hours either side of
  the order so a couple in any time zone gets the week they see. A set with nothing missing or an
  item already owned is `409 AlreadyOwned {itemId}`, a set that is not on sale this week `409
  NotOffered`. `PUT /v1/shop/wishlist {item, wished}` answers the new `ShopResponse`. All are
  `no-store`. A paired app mirrors the room in its wallet file and earns nothing on the phone.
- **Live shop:** a socket whose `Resume` carries `shop: true` gets `ShopChanged {shop}` (the same
  shape as `ShopResponse`) at once, and again after every decision that enters coins, grants inks
  or pieces, or changes the wishlist: either partner's order, wish, note or cat event. The app's
  Inbox socket follows it, so a partner's buy shows without a refresh.
- **`GET /v1/coins?after=<entry id>&limit=<1-100>`:** `CoinsResponse {balance, entries}`, oldest
  first, `no-store`.
- **Bought coins** are in this wallet. A verified purchase is entered in the room as
  `purchase:<originalTransactionId>` (kind `purchase`) after the `coin_ledger` in D1 commits it, once per id, so
  a retry or a transaction sent again credits nothing twice. The wallet is the one signed balance
  the app shows and spends from; `coin_ledger` stays the record of what Apple sold and is what
  `GET /v1/purchases` and the admin read. A demo room has no pair and keeps only the ledger.
- **Entry kinds.** Every entry carries `kind`, apart from the id's prefix: `earn`, `purchase`,
  `refund`, `gift`, `bonus`, `admin` or `spend` (`buy` is only how `purchase` was once written and
  still decodes). A `refund:` id is an Apple refund; the shop's five-second Undo is not an Apple
  refund and never takes that kind.
- **Refunds and debt.** An App Store `REFUND` or `REVOKE` writes `refund:<originalTransactionId>`
  for exactly the coins that purchase credited, whatever the pair has spent since, so the balance
  can go below 0, and only a refund can do that. Nothing else is taken back. While it is negative a
  spend is refused (`409 NotEnoughCoins {needed, have}` with a negative `have`: spending needs a
  balance of at least the price), and earning goes on and pays the debt down: the debt is the
  signed balance, with no second counter. `REFUND_REVERSED` gives the coins back as
  `restore:<originalTransactionId>`. Coins never expire. The purchase is `flagged` when its
  refund left the wallet below 0. The whole policy is in [economy.md](economy.md#refunds).
- **Still to come:** daily deals, the daily gift, collection bonuses, undo, and Inbox items for buys.

## Three builds: none, mock and StoreKit

Which store the app carries is chosen when it is built, with one variable:

| `BILLET_PAYMENTS` | Store | Server path | Use |
| --- | --- | --- | --- |
| `none` | none: no store linked, no "buy coins" anywhere (`NoPaymentsBuild`) | none | The TestFlight default and the first App Store release |
| `mock` (default) | `MockPayments`: packs and prices from `coin-packs.json`, no StoreKit, no network to Apple | `POST /v1/purchases/mock` (dev only) | Simulator and UI work; never uploaded |
| `storekit` | `StoreKitPayments`: StoreKit 2 | `POST /v1/purchases` with the signed transaction | Xcode/Simulator with `Ourio.storekit`, TestFlight sandbox, the App Store |

Set it in the **environment**, never as an `xcodebuild` argument: `Package.swift` reads it to link
only that store into `PaymentsLive`, and the app target reads the same variable as a build setting
(`BILLET_PAYMENTS_MODE`, then the compile condition `PAYMENTS_MOCK`, `PAYMENTS_STOREKIT` or
`PAYMENTS_NONE`). The two can't disagree silently: each mode of `PaymentsLive` has a type the others
lack (`MockPaymentsBuild`, `StoreKitPaymentsBuild`, `NoPaymentsBuild`) and
`apps/ios/Nooki/Server/AppPayments.swift` names the one for its condition, so a mix fails to
compile. The mock build contains no StoreKit purchase path, the StoreKit build no mock, and the
`none` build neither: `check-archive.sh` checks the archive's binary for the other stores' names
and its `BilletPayments` Info.plist value.

```sh
# Simulator or device builds
BILLET_PAYMENTS=mock     xcodebuild build -project apps/ios/Billet.xcodeproj -scheme Billet ...
BILLET_PAYMENTS=storekit xcodebuild build -project apps/ios/Billet.xcodeproj -scheme Billet ...

# TestFlight: no store unless asked for; Labs compiled out unless asked for
gh workflow run testflight.yml --ref main                      # BILLET_PAYMENTS=none
gh workflow run testflight.yml --ref main -f payments=storekit # sandbox purchases
```

Local StoreKit testing needs no App Store Connect, agreement or bank: the `Billet` scheme's Run
action uses `apps/ios/Ourio.storekit`, so a `storekit` build run from Xcode buys from that file, and
Xcode's Debug > StoreKit > Manage Transactions refunds, approves Ask to Buy or deletes a purchase.
Its transactions are signed by Xcode and say `Xcode`, which only the dev stage credits. Use a
runtime before iOS 26.3 for `xcodebuild test` with `SKTestSession`: 26.4 and 26.5 Simulators don't
load `.storekit` files there.

After switching modes in Xcode, quit Xcode and reopen it from a shell with the variable set (or
`launchctl setenv BILLET_PAYMENTS storekit`), and resolve packages again, since Xcode caches the
package manifest.

The TestFlight workflow builds with `BILLET_PAYMENTS=none` unless its `payments` input is
`storekit`, because the binary it uploads is the one App Review and the App Store get. It never
builds the mock. `check-archive.sh` reads the same choice (`EXPECT_PAYMENTS`) and fails the upload
when `BilletPayments` differs, when the binary carries `MockPaymentsBuild`, or when a `none` build
carries `StoreKitPayments`. Turning sales on is then: a `storekit` build through review, the packs
in App Store Connect, and the `payments` flag.

## The app

The Swift package types still carry the old `Stamp` names (`StampPack`, `StampCredit`, …); they
count coins (decoding maps `coins`).

- `Payments` (no StoreKit): the `Payments` protocol (`products()`, `purchase(_:)`, `restore()`,
  `settleUnfinished()`, `updates()`), plain value types (`StampPack`, `PurchaseResult`,
  `StampCredit`, `StampLedger`, `PaymentsError`), the pack list (`StampPackCatalog`, from
  `Resources/coin-packs.json`) and `PaymentsServer`, the server half as closures.
- `PaymentsMock`: `MockPayments` and its switches (`MockSwitches`): the next purchase succeeds, is
  cancelled, fails or waits for Ask to Buy; approving, declining and refunding the last purchase
  go through the mock route.
- `PaymentsStoreKit`: `StoreKitPayments`. `Product.products(for:)` for the prices; `purchase()`;
  the JWS of a verified transaction goes to the server and the transaction is finished **only after
  the server answered**. Once Apple has charged, a server that can't be reached is not a failed
  purchase: `purchase(_:)` answers `awaitingCredit` and the transaction stays unfinished.
  `Transaction.updates` (listened to from launch, which also hands over every unfinished
  transaction) and `settleUnfinished()` (run when the app comes back to the front, and when the
  Coins sheet opens on a pack still on its way) send it again, and the credit is announced on
  `updates()`. A refunded transaction seen on the device is finished and the ledger read again;
  the refund itself reaches the server from Apple.
- `PaymentsLive`: the one store this build carries, or none (see above).
- `FeatureShop.CoinPacksModel`: the Coins sheet's packs, on two machines. `CoinShelfMachine` is
  what is on sale (`loading`, `ready`, `unavailable`); `CoinPurchaseMachine` is the one buy on its
  way (`idle`, `buying`, `waiting` for Ask to Buy, `delivering` while paid but not credited,
  `bought`, `failed`). A credit or a changed ledger from `updates()` reads the wallet again, and
  finishes a `waiting` or `delivering` buy. The sheet sells only while `payments` is `on` for the
  pair (`CoinPacksModel.sells`), shows the wallet's signed balance, and below 0 says what the refund
  took and that new coins cover it first (`CoinDebt`). Ourio Plus is shown in a mock build only.

## Backend

`packages/backend/payments` holds the logic on an injected `PaymentsRepository`, which `platform`
provides on D1 (`payments-repository-live.ts`). The routes are in `@billet/contracts-http-api/routes`
and the wire types in `@billet/contracts-http-api/purchase`, with golden fixtures for each.

### Routes

| Route | Caller | Answer |
| --- | --- | --- |
| `POST /v1/purchases` `{signedTransaction}` | session, paired | `PurchaseResponse` |
| `POST /v1/purchases/mock` `{productId, transactionId, kind}` | session, paired; **dev only** | `PurchaseResponse` |
| `GET /v1/purchases` | session, paired | `PurchasesResponse` (the bought-coins ledger) |
| `POST /v1/appstore/notifications` `{signedPayload}` | Apple, no session | `200 {}` |

The first three routes are behind the `payments` flag: off for the caller, they are a 404 (see
above).

- `PurchaseResponse` is `{transactionId, productId, coins, balance, duplicate}`. `coins` is what
  the transaction credited (or what a mock refund took back, as a positive number). `balance` is
  the pair's wallet after it, the `GET /v1/coins` balance (a demo room's: its bought coins).
  `duplicate` is true when the transaction was already credited: nothing changed and `balance` is
  the current one.
- `PurchasesResponse` is `{balance, entries}`, entries oldest first:
  `{id, kind: "purchase" | "refund", amount, productId, at}` with `at` in ISO 8601 UTC. Ids are
  stable, so the app merges its local ledger by them.
- A refused transaction or notification (signature, chain, bundle, environment, product, type,
  revoked) is `400 {"_tag":"InvalidPurchase"}`. A caller with no pair is `404 NotFound`, as on the
  notes routes; no session is `401`, storage trouble `503 Unavailable`.
- `POST /v1/purchases` and the mock route share a rate-limit group (30 a minute per address).

### Verifying a signed transaction

StoreKit 2 hands the app `Transaction.jwsRepresentation`, a JWS that Apple signs. The Worker checks
it the way Apple's App Store Server Library does, without the library's online (OCSP) checks:

1. The header is `ES256` and carries the certificate chain in `x5c`: leaf, intermediate, root.
2. The root is byte for byte Apple Root CA - G3 (embedded in `apple-root-certificates.ts`; a test
   checks its SHA-256 fingerprint).
3. The intermediate is a CA signed by the root, the leaf is signed by the intermediate, and each
   issuer name matches its parent's subject.
4. The leaf has Apple's App Store marker `1.2.840.113635.100.6.11.1`, the intermediate the WWDR
   marker `1.2.840.113635.100.6.2.1`.
5. Every certificate is valid at the payload's `signedDate`.
6. The leaf's P-256 key verifies the JWS with Web Crypto.

Node's `X509Certificate` does not exist in a Worker, so `x509.ts` reads the few DER fields this
needs by hand, and the signatures go through `effect/crypto`. The trusted roots are a parameter
(`PaymentsConfig`), so tests build their own chains (`test/app-store-signer.ts`), shaped like
Apple's.

Then the payload must name the bundle `com.ourio.app`, a known pack, type `Consumable`, no
`revocationDate`, and an environment the stage accepts.

Until the owner retires it, the first App Store app is accepted as well: bundle
`com.mikitahimpel.billet`, products `com.mikitahimpel.billet.coins.<n>`. Such a product credits the
same pack, under its `com.ourio.app` id. `legacyBundleId` in `contracts-domain/coin-packs.ts` is
the one place to remove.

### Stages

| Stage | Environments credited | Dev extras |
| --- | --- | --- |
| `dev` | `Sandbox`, `Xcode` | yes |
| every other (`prod`, `stage`, unset) | `Production`, `Sandbox` | no |

TestFlight buys in the sandbox, so prod accepts `Sandbox`. The stage comes from the `STAGE` binding
that `alchemy.run.ts` sets, and `settingsForStage` turns it into `PaymentsConfig`. The dev extras
exist only when `STAGE` is exactly `dev`, so a missing or unknown stage is closed:

- **Xcode StoreKit testing.** Xcode signs with a self-signed certificate of its own, so its JWS
  carries one certificate. On dev that certificate verifies the JWS, and the payload must say
  `Xcode`; a single-certificate JWS anywhere else is refused, and Apple's chain may never claim
  `Xcode`.
- **Mock purchases.** `POST /v1/purchases/mock` is registered only on dev; elsewhere it is the
  router's 404, like any unknown path. `kind: "purchase"` credits the pack under the given
  `transactionId` (`mock-…`), environment `Mock`; `kind: "refund"` takes it back like an App Store
  refund. Refunding a mock transaction the caller never bought is a 404.
- **Demo rooms.** The app's demo mode has no session and no pair. On dev only, the purchase, mock
  and coins routes take a request with no `authorization` header and an `x-billet-demo-room`
  header (`demoRoomHeader`, 1 to 64 of `A-Z a-z 0-9 _ -`); its ledger is `demo:<code>`. A session
  always wins, and every other stage ignores the header (no session is a 401).

### The ledger

Coins belong to the pair: both partners share one balance, and pairing again starts from none.
Three D1 tables (`directory-schema.ts`) hold it:

- `purchases`: one row per `originalTransactionId`, with the owner (pair id or `demo:<code>`),
  pack, coins, environment, `status` (`credited` or `refunded`), how many times it was refunded,
  a `flagged` bit and dates. No user, Apple account or receipt is stored.
- `coin_ledger`: every change, `purchase:<id>`, `refund:<id>`, `restore:<id>` (then `:2`, `:3` for
  later rounds). The balance is the sum of `amount`.
- `app_store_notifications`: each notification handled, by `notificationUUID`, with what was done.

Crediting is one D1 batch: insert the purchase if its `originalTransactionId` is new, write the
`purchase:` entry only for the owner the stored row names, and read the balance. A transaction sent
again, by the same pair or another, credits nothing and answers `duplicate: true`.

A refund is one batch too. It takes back the whole pack, however little is left, so the ledger's
balance can go below 0, and so can the wallet's. If the wallet ended below 0, the purchase is flagged
for the admin (the Purchases page). Each step only applies to the purchase in the state it was read
in, so two copies of the same refund apply once.

This D1 ledger counts only bought coins. The pair's wallet (coins earned in play plus coins bought,
minus coins spent in the shop) is in the pair's `PairRoom`, next to the cat's journal; a phone
with no partner keeps its own. Every purchase, refund and restore is entered there too
(`CreditPurchase`, through `PairWallet`), under the same entry id, kind `purchase` or `refund`: once
per id, so the server always calls the room again for a repeated transaction or a retry. A credit
goes to the room after D1, a refund or restore before it (D1 records the notification, which stops
Apple's retries). A refund in the room takes exactly what the purchase credited, below 0 if the
coins are spent already; a restore gives back what that refund took. A demo room has no wallet
and keeps only the D1 ledger.

### App Store Server Notifications

Apple posts V2 notifications to `/v1/appstore/notifications` (set the URL in App Store Connect for
production and sandbox). The `signedPayload` is verified like a transaction, then
`data.signedTransactionInfo`, and both must name the bundle. Any answer but 200 makes Apple retry,
so everything handled answers 200 and only a bad signature, chain or bundle is a 400.

| Type | What happens |
| --- | --- |
| `REFUND`, `REVOKE` | the purchase's coins come back off (`refund:<id>`), below 0 if they are spent |
| `REFUND_REVERSED` | what the last refund took is credited again (`restore:<id>`, kind `purchase`) |
| `CONSUMPTION_REQUEST` | recorded only (see below) |
| anything else | recorded only |

A notification already recorded is a 200 and changes nothing. One for a transaction the server
never credited, or from an environment the stage doesn't accept (the notification's
`data.environment`, or the signed transaction's own when the notification names none), is recorded
with that outcome.

`CONSUMPTION_REQUEST` asks whether a refunded consumable was used. Answering it means calling the
App Store Server API with a signed key (an in-app purchase key from App Store Connect), which does
not exist yet, so the server records the request and Apple decides without the answer.

### Ourio Plus

The subscription ([subscription.md](subscription.md)) lives beside the packs in the same package
(`plus-*.ts`) and the same notifications route, behind its own flag `plus` (`off`, `draft`). Off
for the caller, or the caller a declared 13-17 (onboarding answer `age-13-17`, any stage), every
`/v1/plus` route is a 404 before the body is read. Dev ignores the flag, not the age.

| Route | Caller | Answer |
| --- | --- | --- |
| `GET /v1/plus` | session | `PlusResponse` |
| `POST /v1/plus/subscribe` `{signedTransaction, signedRenewalInfo?}` | session | `PlusResponse` |
| `POST /v1/plus/mock` `{plan, transactionId, kind}` | session; **dev only** | `PlusResponse` |
| `POST /v1/plus/parcels/open` `{parcel, offer}` | session, paired | `OpenParcelResponse` `{plus, shop}` |

- The subscription is bound to the **account** that first sent it (D1 `plus_subscriptions`, one row
  per `originalTransactionId`); a second account sending it is `409 SubscriptionTaken`. A pair has
  Plus while either member has one that is active, ending or in its 16-day grace period. The
  partner sees `Shared`, with no plan or dates, so a cancel, a failed payment or a refund is never
  shown to them.
- Each paid period is a row of `plus_periods`. Parcels are derived from them, never scheduled: a
  month brings `parcel:<transactionId>`, a year `parcel:<transactionId>:<1..12>` one a month from
  the purchase date. Only an opened parcel is stored (`plus_parcels`), so a parcel nobody opened
  costs nothing and waits for ever.
- Opening grants one piece through the room's grants (`GrantItems`, `GrantInks`, `GrantPostage`),
  at no coins and no ledger entry. The piece must be on sale, not free, at most
  `parcelPriceCeiling` (320 coins) and not owned: `400 InvalidRequest` or `409 AlreadyOwned`
  otherwise. The same parcel with the same offer again answers as before; with another offer it is
  `409 ParcelOpened`.
- Notifications: a signed transaction of a Plus product goes to the Plus path. `SUBSCRIBED`,
  `DID_RENEW`, `DID_CHANGE_RENEWAL_STATUS`, `DID_FAIL_TO_RENEW` (grace), `GRACE_PERIOD_EXPIRED`,
  `EXPIRED` update the row and the period from the transaction and `signedRenewalInfo`. `REFUND` and
  `REVOKE` end the period: its parcels not opened go, and an opened one is owed in coins
  (`refund:<parcelId>`, the piece's price, below 0 if spent, as a pack). `REFUND_REVERSED` gives the
  coins back (`restore:<parcelId>`). Every outcome is recorded as `plus-<type>`; a subscription the
  server never saw is recorded only.
- `/v1/plus/*` shares the purchases rate-limit group (30 a minute per address).
- The app: `Payments.plusOffers()`, `subscribe(_:)`, `restorePlus()`; StoreKit sends a Plus
  transaction to `/v1/plus/subscribe` and finishes it only once the server took it (or bound it to
  someone else). Renewals arriving through `Transaction.updates` go the same way. `PlusMachine` and
  `ParcelMachine` in `FeatureShop` drive the sheet; Labs → Payments (mock) adds renew, cancel, fail,
  expire and refund.

### Owner steps before real purchases

The full checklist is `~/.billet-manager/pet-concept/payments/OWNER-TODO.md` (outside the repo).

1. Create the three consumables in App Store Connect with the ids and prices above.
2. Set the App Store Server Notifications V2 URLs (App Store Connect > the app > App Information >
   App Store Server Notifications, Version 2). There is one production and one sandbox URL per
   app, not one per stage:

   | Field | URL | Stage |
   | --- | --- | --- |
   | Production Server URL | `https://ourio-api.gimpelllll.workers.dev/v1/appstore/notifications` | prod |
   | Sandbox Server URL | `https://ourio-api-dev.gimpelllll.workers.dev/v1/appstore/notifications` | dev |

   Sandbox goes to dev because TestFlight test builds talk to dev (docs/testflight-ci.md), so their
   sandbox refunds must reach the ledger that credited them. App Review's sandbox purchases are
   credited on prod; their refunds would go to dev, which records them as `unknown-transaction`.
   No `stage` stage is deployed; one would answer on
   `https://ourio-api-stage.gimpelllll.workers.dev/v1/appstore/notifications` and could take the
   sandbox URL in dev's place. Once `API_DOMAIN` gives prod a custom domain, the production URL
   moves to `https://<API_DOMAIN>/v1/appstore/notifications`.
3. Later, for consumption answers and refund lookups: an App Store Server API key, stored in Proton
   Pass, never in the repository.
