// swift-tools-version: 6.2
import Foundation
import PackageDescription

#if os(Linux)
  // Linux has none of Apple's UI, graphics or Keychain frameworks. A file that imports one is left
  // out there, and so are the targets in `appleOnly`, so the rest builds and tests on a Linux box
  // (docs/testflight-ci.md#tests-on-the-pc).
  func leaveOutAppleOnly(_ package: Package, targets appleOnly: Set<String>) {
    let frameworks: Set<String> = [
      "SwiftUI", "UIKit", "CoreGraphics", "QuartzCore", "ImageIO", "CoreText",
      "UniformTypeIdentifiers", "Security", "OSLog", "simd", "ActivityKit", "WidgetKit",
      "AppIntents", "AuthenticationServices", "StoreKit", "RealityKit", "Combine",
    ]
    func isAppleOnly(_ text: String) -> Bool {
      text.contains("URLProtocol")
        || text.split(separator: "\n").contains { line in
          let words = line.replacingOccurrences(of: "@testable ", with: "")
            .replacingOccurrences(of: "@preconcurrency ", with: "").split(separator: " ")
          return (line.first == "i" || line.first == "@")
            && words.count > 1 && words[0] == "import" && frameworks.contains(String(words[1]))
        }
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    package.targets.removeAll { appleOnly.contains($0.name) }
    package.products.removeAll { appleOnly.contains($0.name) }
    for target in package.targets {
      let directory = target.path ?? "\(target.type == .test ? "Tests" : "Sources")/\(target.name)"
      let base = root.appending(path: directory, directoryHint: .isDirectory)
      let files = FileManager.default.enumerator(atPath: base.path)?.compactMap { $0 as? String }
      target.exclude += (files ?? []).filter { path in
        path.hasSuffix(".swift")
          && (try? String(contentsOf: base.appending(path: path), encoding: .utf8))
            .map(isAppleOnly) == true
      }
    }
  }
#endif

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

#if os(Linux)
  leaveOutAppleOnly(package, targets: ["PaymentsStoreKit", "PaymentsLive"])
#endif
