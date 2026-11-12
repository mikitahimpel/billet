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

// The top layer: nothing depends on this package except the apps.

// Where each module from a lower layer lives. Names not listed here are targets of this package.
let packageOf = [
  "Wire": "contracts",
  "BilletKit": "core", "DesignSystem": "core", "Ink": "core", "Transport": "core",
  "Persistence": "core", "Delivery": "core",
  "Pet": "pet", "PetScene": "pet",
  "Design": "design",
  "Payments": "payments",
]

func dependencies(_ names: [String]) -> [Target.Dependency] {
  names.map { name in
    packageOf[name].map { .product(name: name, package: $0) } ?? .target(name: name)
  }
}

let features = ["FeaturePairing", "FeatureCanvas", "FeatureMoments"]

let featureDependencies = ["BilletKit", "Wire", "Ink", "DesignSystem", "Transport", "Persistence"]

let widgetBridge: Target = .target(
  name: "WidgetBridge",
  dependencies: dependencies(["DesignSystem", "Delivery", "Persistence", "Pet"])
)

let tests: [(name: String, dependencies: [String])] = [
  ("FeatureCanvasTests", ["FeatureCanvas", "Wire"]),
  ("FeaturePairingTests", ["FeaturePairing", "Transport", "Wire"]),
  ("FeatureMomentsTests", ["FeatureMoments", "Transport", "Wire"]),
  ("WidgetInterfaceTests", ["WidgetInterface", "MoodInterface"]),
  ("WidgetBridgeTests", ["Delivery", "Persistence", "Pet", "WidgetBridge"]),
  ("FeatureGamesTests", ["FeatureGames", "GamesInterface", "Pet", "Transport", "Wire"]),
  ("RoomInterfaceTests", ["RoomInterface", "Pet"]),
  ("FeatureInboxTests", ["Design", "FeatureInbox", "Transport", "Wire"]),
  ("FeatureMoodTests", ["FeatureMood", "MoodInterface", "Transport", "Wire"]),
  ("ProfileInterfaceTests", ["ProfileInterface", "Pet"]),
  ("DecorInterfaceTests", ["DecorInterface"]),
  ("UsInterfaceTests", ["UsInterface", "Persistence", "Wire"]),
  ("FeatureDecorTests", ["FeatureDecor", "DecorInterface", "Persistence", "Wire"]),
]

let usTests: Target = .testTarget(
  name: "FeatureUsTests",
  dependencies: dependencies(["FeatureUs", "UsInterface", "Transport", "Persistence", "Wire"]),
  swiftSettings: [.defaultIsolation(MainActor.self)])

let shopTests: Target = .testTarget(
  name: "FeatureShopTests",
  dependencies: dependencies([
    "FeatureShop", "ShopInterface", "ProfileInterface", "Payments", "Persistence", "Transport",
    "Wire",
  ]),
  swiftSettings: [.defaultIsolation(MainActor.self)])

let onboardingTests: Target = .testTarget(
  name: "FeatureOnboardingTests",
  dependencies: dependencies([
    "FeatureOnboarding", "ProfileInterface", "RoomInterface", "Pet", "Persistence", "Transport",
    "Wire",
  ]))

let games: Target = .target(
  name: "FeatureGames",
  dependencies: dependencies(["GamesInterface", "BilletKit", "Pet", "Transport", "Wire"]))

let inbox: Target = .target(
  name: "FeatureInbox", dependencies: dependencies(["BilletKit", "Design", "Transport", "Wire"]))
let decorInterface: Target = .target(name: "DecorInterface", dependencies: dependencies(["Pet"]))
let decor: Target = .target(
  name: "FeatureDecor",
  dependencies: dependencies(["DecorInterface", "BilletKit", "Persistence", "Wire"]))
let moodInterface: Target = .target(name: "MoodInterface", dependencies: dependencies(["Wire"]))
let profileInterface: Target = .target(
  name: "ProfileInterface", dependencies: dependencies(["Persistence", "Pet"]))
// Moved from the app, which builds with Xcode's approachable concurrency: a
// nonisolated async method runs on its caller's actor, so the app's stores can call it from the UI.
let fromTheApp: [SwiftSetting] = [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
let shopInterface: Target = .target(
  name: "ShopInterface", dependencies: dependencies(["Persistence", "Wire"]),
  swiftSettings: fromTheApp)

let usInterface: Target = .target(
  name: "UsInterface", dependencies: dependencies(["Persistence", "ProfileInterface", "Wire"]),
  swiftSettings: fromTheApp)
// Moved from the app, so it keeps the app's default of main-actor isolation.
let us: Target = .target(
  name: "FeatureUs",
  dependencies: dependencies([
    "UsInterface", "MomentsInterface", "ProfileInterface", "WidgetInterface", "WidgetUI",
    "BilletKit", "Design", "DesignSystem", "Ink", "Persistence",
    "Pet", "Transport", "WidgetBridge", "Wire",
  ]),
  swiftSettings: fromTheApp + [.defaultIsolation(MainActor.self)])
let momentsInterface: Target = .target(
  name: "MomentsInterface", dependencies: dependencies(["Persistence", "Wire"]),
  swiftSettings: fromTheApp)
// What the widgets show and the App Group files they share with the app and the other extensions.
let widgetInterface: Target = .target(
  name: "WidgetInterface",
  dependencies: dependencies([
    "MoodInterface", "Persistence", "ProfileInterface", "UsInterface", "Wire",
  ]),
  swiftSettings: fromTheApp)
// The views the widgets and the app both draw.
let widgetUI: Target = .target(
  name: "WidgetUI",
  dependencies: dependencies([
    "Design", "DrawInterface", "Ink", "MomentsInterface", "ProfileInterface", "UsInterface",
    "WidgetInterface", "Wire",
  ]),
  swiftSettings: fromTheApp)
let drawInterface: Target = .target(
  name: "DrawInterface", dependencies: dependencies(["Persistence", "Wire"]))
let mood: Target = .target(
  name: "FeatureMood", dependencies: dependencies(["MoodInterface", "Transport", "Wire"]))
// Moved from the app, so it keeps the app's default of main-actor isolation.
let shop: Target = .target(
  name: "FeatureShop",
  dependencies: dependencies([
    "ShopInterface", "BilletKit", "DecorInterface", "Design", "MomentsInterface", "Payments",
    "Persistence", "Pet", "PetScene", "ProfileInterface", "Transport", "UsInterface",
    "WidgetBridge",
    "WidgetUI",
    "Wire",
  ]),
  swiftSettings: fromTheApp + [.defaultIsolation(MainActor.self)]
)

// Moved from the app, so it keeps the app's default of main-actor isolation.
let onboarding: Target = .target(
  name: "FeatureOnboarding",
  dependencies: dependencies(
    featureDependencies + [
      "Design", "MomentsInterface", "Pet", "ProfileInterface", "RoomInterface", "UsInterface",
      "WidgetInterface", "WidgetUI",
    ]),
  swiftSettings: [.defaultIsolation(MainActor.self)]
)

// The room itself is in the app, where RealityKit is.
let gamesInterface: Target = .target(
  name: "GamesInterface", dependencies: dependencies(["Pet", "Wire"]))
let roomInterface: Target = .target(
  name: "RoomInterface",
  dependencies: dependencies(["GamesInterface", "DecorInterface", "Pet", "BilletKit"]))

let products =
  features + [
    "FeatureOnboarding",
    "WidgetBridge", "FeatureGames", "GamesInterface", "RoomInterface", "ShopInterface",
    "FeatureShop", "FeatureInbox", "MoodInterface", "FeatureMood", "DrawInterface",
    "ProfileInterface", "UsInterface", "MomentsInterface", "WidgetInterface", "WidgetUI",
    "DecorInterface", "FeatureDecor", "FeatureUs",
  ]

let package = Package(
  name: "BilletFeatures",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: products.map { .library(name: $0, targets: [$0]) },
  dependencies: [
    .package(path: "../contracts"),
    .package(path: "../core"),
    .package(path: "../design"),
    .package(path: "../pet"),
    .package(path: "../payments"),
  ],
  targets: features.map { .target(name: $0, dependencies: dependencies(featureDependencies)) }
    + [
      widgetBridge, games, gamesInterface, roomInterface, shopInterface, shop, inbox, moodInterface,
      mood, drawInterface, profileInterface, usInterface, momentsInterface, widgetInterface,
      widgetUI,
      decorInterface, decor, us, onboarding,
    ]
    + tests.map { .testTarget(name: $0.name, dependencies: dependencies($0.dependencies)) }
    + [usTests, shopTests, onboardingTests],
  swiftLanguageModes: [.v6]
)

#if os(Linux)
  leaveOutAppleOnly(
    package,
    targets: [
      "FeatureCanvas", "FeatureCanvasTests", "FeatureInbox", "FeatureInboxTests",
      "FeatureOnboardingTests", "FeatureOnboarding",
      "WidgetBridge", "WidgetBridgeTests", "WidgetUI", "FeatureUs", "FeatureUsTests", "FeatureShop",
      "FeatureShopTests",
    ])
#endif
