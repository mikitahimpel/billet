// swift-tools-version: 6.2
import PackageDescription

// `mock` (the default) or `storekit`. The same variable the app target reads as a build setting
// (docs/payments.md), so `BILLET_PAYMENTS=storekit xcodebuild ...` switches both.
let paymentsMode =
  Context.environment["BILLET_PAYMENTS"].flatMap { $0.isEmpty ? nil : $0 } ?? "mock"
precondition(
  ["mock", "storekit"].contains(paymentsMode),
  "BILLET_PAYMENTS must be mock or storekit, not \(paymentsMode)")

let targets = ["Payments", "PaymentsMock", "PaymentsStoreKit", "PaymentsLive"]

let package = Package(
  name: "BilletPayments",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: targets.map { .library(name: $0, targets: [$0]) },
  targets: [
    .target(name: "Payments", resources: [.copy("Resources/coin-packs.json")]),
    .target(name: "PaymentsMock", dependencies: ["Payments"]),
    .target(name: "PaymentsStoreKit", dependencies: ["Payments"]),
    .target(
      name: "PaymentsLive",
      dependencies: paymentsMode == "storekit"
        ? ["Payments", "PaymentsStoreKit"] : ["Payments", "PaymentsMock"],
      swiftSettings: paymentsMode == "storekit"
        ? [.define("PAYMENTS_STOREKIT")] : [.define("PAYMENTS_MOCK")]
    ),
    .testTarget(name: "PaymentsTests", dependencies: ["Payments", "PaymentsMock"]),
  ],
  swiftLanguageModes: [.v6]
)
