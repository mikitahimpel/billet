# Payments

Ourio's **coins** are billet's one currency (owner decision, 2026-11-05). Stamps, the old app's
paid-only currency, are gone. Coins are earned in play (mini-games, feeding, notes) and, once
payments are on, also sold in packs as consumable in-app purchases through StoreKit 2. The server
keeps a ledger of the coins each pair has bought.

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
- **Bought coins** (`coin_ledger` in D1, through `/v1/purchases*`) are not in this wallet yet. They
  join it when payments are switched on; until then the flag is off and nothing is bought.
- **Still to come:** daily deals, the daily gift, collection bonuses, undo, and Inbox items for buys.

## Three builds: none, mock and StoreKit

Which store the app carries is chosen when it is built, with one variable:

| `BILLET_PAYMENTS` | Store | Server path | Use |
| --- | --- | --- | --- |
| `none` (the release default, to come) | none: no StoreKit, no mock, no "buy coins" anywhere | none | The first App Store release |
| `mock` (default) | `MockPayments`: packs and prices from `coin-packs.json`, no StoreKit, no network to Apple | `POST /v1/purchases/mock` (dev only) | Simulator and UI work; never uploaded |
| `storekit` | `StoreKitPayments`: StoreKit 2 | `POST /v1/purchases` with the signed transaction | Xcode/Simulator with `Billet.storekit`, TestFlight sandbox, the App Store |

Set it in the **environment**, never as an `xcodebuild` argument: `Package.swift` reads it to link
only that store into `PaymentsLive`, and the app target reads the same variable as a build setting
(`BILLET_PAYMENTS_MODE`, then the compile condition `PAYMENTS_MOCK` or `PAYMENTS_STOREKIT`). The two
can't disagree silently: each mode of `PaymentsLive` has a type the other lacks
(`MockPaymentsBuild`, `StoreKitPaymentsBuild`) and `apps/ios/App/AppPayments.swift` names the one
for its condition, so a mix fails to compile. The mock build contains no StoreKit purchase path and
the StoreKit build contains no mock: `check-archive.sh` checks the archive's binary for the other
store's names and its `BilletPayments` Info.plist value.

```sh
# Simulator or device builds
BILLET_PAYMENTS=mock     xcodebuild build -project apps/ios/Billet.xcodeproj -scheme Billet ...
BILLET_PAYMENTS=storekit xcodebuild build -project apps/ios/Billet.xcodeproj -scheme Billet ...

# StoreKit purchases on a Simulator, from Billet.storekit (also run by ios.yml). Use a
# runtime before iOS 26.3: 26.4 and 26.5 Simulators don't load .storekit files from
# xcodebuild test, and on 27.2 the first purchase hangs (ios.yml picks the newest one
# before 26.3, downloading iOS 26.2 when the runner has none:
# xcodebuild -downloadPlatform iOS -buildVersion 26.2).
(cd apps/ios && xcodegen generate)
BILLET_PAYMENTS=storekit xcodebuild test -project apps/ios/Billet.xcodeproj \
  -scheme BilletStoreKitTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'

# TestFlight
gh workflow run testflight.yml --ref main   # always StoreKit, Labs compiled out
```

After switching modes in Xcode, quit Xcode and reopen it from a shell with the variable set (or
`launchctl setenv BILLET_PAYMENTS storekit`), and resolve packages again, since Xcode caches the
package manifest.

The TestFlight workflow always builds with `BILLET_PAYMENTS=storekit`, because the binary it
uploads is the one App Review and the App Store get, and `check-archive.sh` fails the upload when
`BilletPayments` is not `storekit` or the binary carries `MockPaymentsBuild`.

## The app

The Swift package types below still carry the old `Stamp` names (`StampPack`, `StampShop`, …);
they count coins, and the Ourio client renames them when it wires payments (decoding already maps
`coins`).

- `Payments` (no StoreKit): the `Payments` protocol (`products()`, `purchase(_:)`, `restore()`,
  `updates()`), plain value types (`StampPack`, `PurchaseResult`, `StampCredit`, `StampLedger`,
  `PaymentsError`), the pack list (`StampPackCatalog`, from `Resources/coin-packs.json`) and
  `PaymentsServer`, the server half as closures.
- `PaymentsMock`: `MockPayments` and its switches (`MockSwitches`, Labs → Payments): the next purchase
  succeeds, is cancelled, fails or waits for Ask to Buy; buttons approve or decline Ask to Buy and
  refund the last purchase (through the mock route's `kind: "refund"`).
- `PaymentsStoreKit`: `StoreKitPayments`. `Product.products(for:)` for the prices; `purchase()`; the
  JWS of a verified transaction goes to the server and the transaction is finished **only after the
  server answered**, so a crash or lost network leaves it unfinished and `Transaction.updates` or
  `restore()` (which walks `Transaction.unfinished`) sends it again. Refunds reach the server from
  Apple's notifications; the device only sees a changed ledger.
- `PaymentsLive`: the one store this build carries (see above).
- `FeatureHome.StampShop`: the model the shop uses (`packs`, `state`, `buy(_:)`). It credits the
  pair's wallet (`ShopStore.creditPurchase`, entry `purchase:<transaction>`), merges the server's
  ledger on attach and on `updates()`, and takes App Store refunds back with
  `ShopStore.revokePurchase` (source `revoked`, entry `revoked:<transaction>`, never below zero; the
  shop's own `refund:` entries are its 5-second Undo). The shop's own row of packs (behind the Labs
  switch "Stamp packs") gets them through `StampShopPacks`, its `StampPackSource`. Labs → Payments
  also opens a plain `StampPacksSheet`, next to the mock store's switches.
- The shop lives in the demo app, which has no session: on the dev server, its purchase calls carry
  the room code in `X-Billet-Demo-Room` (see Stages).

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

A refund is one batch too. It takes back the pack's coins but at most the owner's balance, so the
balance never goes below 0. If it took less than the pack, the purchase is flagged for the admin
(the Purchases page). Each step only applies to the purchase in the state it was read in, so two
copies of the same refund apply once.

This D1 ledger counts only bought coins. The pair's wallet (coins earned in play plus coins bought,
minus coins spent in the shop) is in the pair's `PairRoom`, next to the cat's journal; a phone
with no partner keeps its own. Every purchase, refund and restore is entered there too
(`CreditPurchase`, through `PairWallet`), under the same entry id, kind `buy` or `refund`: once
per id, so the server always calls the room again for a repeated transaction or a retry. A credit
goes to the room after D1, a refund or restore before it (D1 records the notification, which stops
Apple's retries). A refund in the room takes at most the wallet's balance, which coins spent
already may have lowered; a restore gives back what that refund took. A demo room has no wallet
and keeps only the D1 ledger.

### App Store Server Notifications

Apple posts V2 notifications to `/v1/appstore/notifications` (set the URL in App Store Connect for
production and sandbox). The `signedPayload` is verified like a transaction, then
`data.signedTransactionInfo`, and both must name the bundle. Any answer but 200 makes Apple retry,
so everything handled answers 200 and only a bad signature, chain or bundle is a 400.

| Type | What happens |
| --- | --- |
| `REFUND`, `REVOKE` | the purchase's coins come back off (`refund:<id>`), at most down to 0 |
| `REFUND_REVERSED` | what the last refund took is credited again (`restore:<id>`, kind `purchase`) |
| `CONSUMPTION_REQUEST` | recorded only (see below) |
| anything else | recorded only |

A notification already recorded is a 200 and changes nothing. One for a transaction the server
never credited, or from an environment the stage doesn't accept, is recorded with that outcome.

`CONSUMPTION_REQUEST` asks whether a refunded consumable was used. Answering it means calling the
App Store Server API with a signed key (an in-app purchase key from App Store Connect), which does
not exist yet, so the server records the request and Apple decides without the answer.

### Owner steps before real purchases

The full checklist is `~/.billet-manager/pet-concept/payments/OWNER-TODO.md` (outside the repo).

1. Create the three consumables in App Store Connect with the ids and prices above.
2. Set the App Store Server Notifications V2 URL (production and sandbox) to
   `https://billet.mikitahimpel.com/v1/appstore/notifications`.
3. Later, for consumption answers and refund lookups: an App Store Server API key, stored in Proton
   Pass, never in the repository.
