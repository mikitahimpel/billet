// swift-tools-version: 6.2
import PackageDescription

// The top layer: the screens, the widget's surfaces and the bridge between the app and its widget.
// Depends on every layer below it; nothing depends on this package except the apps.

// Where each module from a lower layer lives. Names not listed here are targets of this package.
let packageOf = [
  "Domain": "contracts", "Wire": "contracts",
  "BilletKit": "core", "DesignSystem": "core", "Ink": "core", "Transport": "core",
  "Persistence": "core", "Delivery": "core",
  "Pet": "pet", "PetScene": "pet", "PetSceneCatalog": "pet",
  "Payments": "payments",
]

func dependencies(_ names: [String]) -> [Target.Dependency] {
  names.map { name in
    packageOf[name].map { .product(name: name, package: $0) } ?? .target(name: name)
  }
}

let features = [
  "FeatureOnboarding",
  "FeaturePairing",
  "FeatureCanvas",
  "FeatureInbox",
  "FeatureSettings",
]

// Surfaces is shared with the widget and Live Activity, so it never depends on a feature target.
let library: [(name: String, dependencies: [String])] = [
  ("Surfaces", ["Domain", "Ink", "DesignSystem", "Pet", "WidgetBridge"]),
  // Shared by the app, the widget and the settings screen: flags, the published snapshot, the
  // picture rules and the queue of actions taken outside the app.
  ("WidgetBridge", ["DesignSystem", "Delivery", "Persistence", "Pet"]),
  (
    "Labs",
    ["Domain", "Wire", "Ink", "DesignSystem", "Persistence", "Pet", "WidgetBridge", "FeatureInbox"]
  ),
]

let featureDependencies = [
  "BilletKit", "Domain", "Wire", "Ink", "DesignSystem", "Transport", "Persistence",
]

let libraryTargets: [Target] = library.map {
  .target(name: $0.name, dependencies: dependencies($0.dependencies))
}

let featureTargets: [Target] = features.map { feature in
  let extra = feature == "FeatureSettings" ? ["Pet", "PetScene", "WidgetBridge"] : []
  return .target(name: feature, dependencies: dependencies(featureDependencies + extra))
}

// Knows scenes only through the PetScene contract. No graphics engine links into this package:
// each engine lives in its own package under packages/pet-scenes, chosen by the App target.
let homeTarget: Target = .target(
  name: "FeatureHome",
  dependencies: dependencies([
    "BilletKit",
    "Delivery",
    "DesignSystem",
    "FeatureCanvas",
    "FeatureInbox",
    "FeatureOnboarding",
    "FeaturePairing",
    "FeatureSettings",
    "Ink",
    "Labs",
    "Persistence",
    "Payments",
    "Pet",
    "PetScene",
    "Transport",
    "WidgetBridge",
    "Wire",
  ])
)

let tests: [(name: String, dependencies: [String])] = [
  ("FeatureCanvasTests", ["FeatureCanvas", "Wire"]),
  (
    "FeatureHomeTests",
    [
      "BilletKit", "Delivery", "FeatureHome", "FeatureInbox", "Ink", "Payments", "Persistence",
      "Pet", "PetScene", "Transport", "WidgetBridge", "Wire",
    ]
  ),
  ("FeatureOnboardingTests", ["FeatureOnboarding", "Persistence", "Transport", "Wire"]),
  ("FeatureSettingsTests", ["FeatureSettings", "Persistence", "Transport", "Wire"]),
  ("FeaturePairingTests", ["FeaturePairing", "Transport", "Wire"]),
  ("FeatureInboxTests", ["FeatureInbox", "Persistence", "Transport", "Wire"]),
  ("WidgetBridgeTests", ["Delivery", "Persistence", "Pet", "WidgetBridge"]),
  (
    "LabsTests",
    [
      "DesignSystem", "Domain", "FeatureInbox", "Ink", "Labs", "Persistence", "Pet", "WidgetBridge",
      "Wire",
    ]
  ),
]

let products = library.map(\.name) + features + ["FeatureHome"]

let package = Package(
  name: "BilletFeatures",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: products.map { .library(name: $0, targets: [$0]) },
  dependencies: [
    .package(path: "../contracts"),
    .package(path: "../core"),
    .package(path: "../payments"),
    .package(path: "../pet"),
  ],
  targets: libraryTargets + featureTargets + [homeTarget]
    + tests.map { .testTarget(name: $0.name, dependencies: dependencies($0.dependencies)) },
  swiftLanguageModes: [.v6]
)
