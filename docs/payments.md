# Payments

Stamps are billet's in-app currency. The app sells them in packs, as consumable in-app purchases
through StoreKit 2, and the server keeps a ledger of the stamps each pair has bought.

## Stamp packs

The canonical list is `stampPacks` in `@billet/contracts-domain/stamp-packs`:

| Product id | Stamps | Price (USD) |
| --- | --- | --- |
| `com.mikitahimpel.billet.stamps.100` | 100 | 0.99 |
| `com.mikitahimpel.billet.stamps.550` | 550 | 4.99 |
| `com.mikitahimpel.billet.stamps.1200` | 1200 | 9.99 |

The app's copy (`packages/ios/Sources/Payments/Resources/stamp-packs.json`) and the Xcode StoreKit
configuration (`apps/ios/App/Billet.storekit`) must sell exactly these. A test in
`contracts-fixtures` (`stamp-packs-sync.test.ts`) fails if an id, a number of stamps or a price
differs, or if a StoreKit product is not a consumable.

## Two builds: mock and StoreKit

Which store the app carries is chosen when it is built, with one variable:

| `BILLET_PAYMENTS` | Store | Server path | Use |
| --- | --- | --- | --- |
| `mock` (default) | `MockPayments`: packs and prices from `stamp-packs.json`, no StoreKit, no network to Apple | `POST /v1/purchases/mock` (dev only) | Simulator, TestFlight demos, UI work |
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
gh workflow run testflight.yml --ref main                       # mock (the default)
gh workflow run testflight.yml --ref main -f payments=storekit  # App Store sandbox
```

After switching modes in Xcode, quit Xcode and reopen it from a shell with the variable set (or
`launchctl setenv BILLET_PAYMENTS storekit`), and resolve packages again, since Xcode caches the
package manifest.

An App Store build sets `BILLET_DISTRIBUTION=appstore`; with `mock` it stops at compile time
(`#error` in `AppPayments.swift`). TestFlight builds are `BILLET_DISTRIBUTION=testflight` (the
default).

## The app

- `Payments` (no StoreKit): the `Payments` protocol (`products()`, `purchase(_:)`, `restore()`,
  `updates()`), plain value types (`StampPack`, `PurchaseResult`, `StampCredit`, `StampLedger`,
  `PaymentsError`), the pack list (`StampPackCatalog`, from `Resources/stamp-packs.json`) and
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
| `GET /v1/stamps` | session, paired | `StampsResponse` |
| `POST /v1/appstore/notifications` `{signedPayload}` | Apple, no session | `200 {}` |

- `PurchaseResponse` is `{transactionId, productId, stamps, balance, duplicate}`. `stamps` is what
  the transaction credited (or what a mock refund took back, as a positive number). `duplicate` is
  true when the transaction was already credited: nothing changed and `balance` is the current one.
- `StampsResponse` is `{balance, entries}`, entries oldest first:
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

Then the payload must name the bundle `com.mikitahimpel.billet`, a known pack, type `Consumable`, no
`revocationDate`, and an environment the stage accepts.

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
  and stamps routes take a request with no `authorization` header and an `x-billet-demo-room`
  header (`demoRoomHeader`, 1 to 64 of `A-Z a-z 0-9 _ -`); its ledger is `demo:<code>`. A session
  always wins, and every other stage ignores the header (no session is a 401).

### The ledger

Stamps belong to the pair: both partners share one balance, and pairing again starts from none.
Three D1 tables (`directory-schema.ts`) hold it:

- `purchases`: one row per `originalTransactionId`, with the owner (pair id or `demo:<code>`),
  pack, stamps, environment, `status` (`credited` or `refunded`), how many times it was refunded,
  a `flagged` bit and dates. No user, Apple account or receipt is stored.
- `stamp_ledger`: every change, `purchase:<id>`, `refund:<id>`, `restore:<id>` (then `:2`, `:3` for
  later rounds). The balance is the sum of `amount`.
- `app_store_notifications`: each notification handled, by `notificationUUID`, with what was done.

Crediting is one D1 batch: insert the purchase if its `originalTransactionId` is new, write the
`purchase:` entry only for the owner the stored row names, and read the balance. A transaction sent
again, by the same pair or another, credits nothing and answers `duplicate: true`.

A refund is one batch too. It takes back the pack's stamps but at most the owner's balance, so the
balance never goes below 0. If it took less than the pack, the purchase is flagged for the admin
(the Purchases page). Each step only applies to the purchase in the state it was read in, so two
copies of the same refund apply once.

Stamps are still spent in the app, in its local ledger, so the server's balance only counts what was
bought and refunded. A pair that spent its stamps and then got a refund keeps them on the server's
side; a refund only finds fewer stamps than the pack once spending moves to the server.

### App Store Server Notifications

Apple posts V2 notifications to `/v1/appstore/notifications` (set the URL in App Store Connect for
production and sandbox). The `signedPayload` is verified like a transaction, then
`data.signedTransactionInfo`, and both must name the bundle. Any answer but 200 makes Apple retry,
so everything handled answers 200 and only a bad signature, chain or bundle is a 400.

| Type | What happens |
| --- | --- |
| `REFUND`, `REVOKE` | the purchase's stamps come back off (`refund:<id>`), at most down to 0 |
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
