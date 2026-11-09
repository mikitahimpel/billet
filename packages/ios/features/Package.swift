// swift-tools-version: 6.2
import PackageDescription

// The top layer: nothing depends on this package except the apps.

// Where each module from a lower layer lives. Names not listed here are targets of this package.
let packageOf = [
  "Wire": "contracts",
  "BilletKit": "core", "DesignSystem": "core", "Ink": "core", "Transport": "core",
  "Persistence": "core", "Delivery": "core",
  "Pet": "pet",
]

func dependencies(_ names: [String]) -> [Target.Dependency] {
  names.map { name in
    packageOf[name].map { .product(name: name, package: $0) } ?? .target(name: name)
  }
}

let features = ["FeatureOnboarding", "FeaturePairing", "FeatureCanvas", "FeatureMoments"]

let featureDependencies = ["BilletKit", "Wire", "Ink", "DesignSystem", "Transport", "Persistence"]

let widgetBridge: Target = .target(
  name: "WidgetBridge",
  dependencies: dependencies(["DesignSystem", "Delivery", "Persistence", "Pet"])
)

let tests: [(name: String, dependencies: [String])] = [
  ("FeatureShopTests", ["FeatureShop", "ShopInterface", "Transport", "Wire"]),
  ("FeatureCanvasTests", ["FeatureCanvas", "Wire"]),
  ("FeatureOnboardingTests", ["FeatureOnboarding", "Persistence", "Transport", "Wire"]),
  ("FeaturePairingTests", ["FeaturePairing", "Transport", "Wire"]),
  ("FeatureMomentsTests", ["FeatureMoments", "Transport", "Wire"]),
  ("WidgetBridgeTests", ["Delivery", "Persistence", "Pet", "WidgetBridge"]),
  ("FeatureGamesTests", ["FeatureGames", "GamesInterface", "Transport", "Wire"]),
  ("RoomInterfaceTests", ["RoomInterface", "Pet"]),
  ("FeatureInboxTests", ["FeatureInbox", "Transport", "Wire"]),
]

let games: Target = .target(
  name: "FeatureGames",
  dependencies: dependencies(["GamesInterface", "BilletKit", "Transport", "Wire"]))

let shopInterface: Target = .target(name: "ShopInterface", dependencies: dependencies(["Wire"]))
let inbox: Target = .target(
  name: "FeatureInbox", dependencies: dependencies(["BilletKit", "Transport", "Wire"]))
let shop: Target = .target(
  name: "FeatureShop",
  dependencies: dependencies(["ShopInterface", "BilletKit", "Transport", "Wire"])
)

// The room itself is in the app, where RealityKit is.
let gamesInterface: Target = .target(name: "GamesInterface", dependencies: dependencies(["Wire"]))
let roomInterface: Target = .target(
  name: "RoomInterface", dependencies: dependencies(["GamesInterface", "Pet", "BilletKit"]))

let products =
  features + [
    "WidgetBridge", "FeatureGames", "GamesInterface", "RoomInterface", "ShopInterface",
    "FeatureShop", "FeatureInbox",
  ]

let package = Package(
  name: "BilletFeatures",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: products.map { .library(name: $0, targets: [$0]) },
  dependencies: [
    .package(path: "../contracts"),
    .package(path: "../core"),
    .package(path: "../pet"),
  ],
  targets: features.map { .target(name: $0, dependencies: dependencies(featureDependencies)) }
    + [widgetBridge, games, gamesInterface, roomInterface, shopInterface, shop, inbox]
    + tests.map { .testTarget(name: $0.name, dependencies: dependencies($0.dependencies)) },
  swiftLanguageModes: [.v6]
)
