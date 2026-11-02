// swift-tools-version: 6.2
import PackageDescription

let features = [
  "FeatureOnboarding",
  "FeaturePairing",
  "FeatureCanvas",
  "FeatureInbox",
  "FeatureSettings",
]

// Surfaces is shared with the widget and Live Activity, so it never depends on a feature target.
let library: [(name: String, dependencies: [String])] = [
  ("BilletKit", []),
  ("Domain", []),
  ("Wire", ["Domain"]),
  ("Ink", ["BilletKit", "Domain", "Wire"]),
  ("DesignSystem", []),
  ("Transport", ["BilletKit", "Domain", "Wire"]),
  ("Persistence", ["Domain"]),
  ("Delivery", ["Domain", "Wire", "Ink", "Persistence"]),
  ("Surfaces", ["Domain", "Ink", "DesignSystem", "Pet", "WidgetBridge"]),
  ("Pet", ["BilletKit", "DesignSystem"]),
  ("PetScene", ["DesignSystem", "Pet"]),
  ("PetSceneCatalog", ["Persistence", "Pet", "PetScene"]),
  // Shared by the app, the widget and the settings screen: flags, the published snapshot, the
  // picture rules and the queue of actions taken outside the app.
  ("WidgetBridge", ["Persistence", "Pet"]),
  (
    "Labs",
    ["Domain", "Wire", "Ink", "DesignSystem", "Persistence", "Pet", "WidgetBridge", "FeatureInbox"]
  ),
]

let featureDependencies = [
  "BilletKit", "Domain", "Wire", "Ink", "DesignSystem", "Transport", "Persistence",
]

let libraryTargets: [Target] = library.map {
  .target(
    name: $0.name,
    dependencies: $0.dependencies.map { .init(stringLiteral: $0) },
    resources: $0.name == "DesignSystem" ? [.copy("Resources/Fonts")] : nil
  )
}

let featureTargets: [Target] = features.map { feature in
  let extra = feature == "FeatureSettings" ? ["PetScene", "WidgetBridge"] : []
  return .target(
    name: feature,
    dependencies: (featureDependencies + extra).map { .init(stringLiteral: $0) })
}

// Knows scenes only through the PetScene contract. No graphics engine links into this package:
// each engine lives in its own package under packages/pet-scenes, chosen by the App target.
let homeTarget: Target = .target(
  name: "FeatureHome",
  dependencies: [
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
    "Pet",
    "PetScene",
    "Transport",
    "WidgetBridge",
    "Wire",
  ]
)

let testTargets: [Target] = [
  .testTarget(name: "BilletKitTests", dependencies: ["BilletKit"]),
  .testTarget(name: "WireConformanceTests", dependencies: ["Wire"]),
  .testTarget(name: "TransportTests", dependencies: ["BilletKit", "Transport", "Wire"]),
  .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
  .testTarget(name: "InkTests", dependencies: ["BilletKit", "Ink", "Wire"]),
  .testTarget(name: "FeatureCanvasTests", dependencies: ["FeatureCanvas", "Wire"]),
  .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
  .testTarget(name: "PrivacyManifestTests"),
  .testTarget(
    name: "FeatureHomeTests",
    dependencies: [
      "BilletKit", "Delivery", "FeatureHome", "FeatureInbox", "Ink", "Persistence", "Pet",
      "WidgetBridge",
      "Wire",
    ]),
  .testTarget(
    name: "FeatureOnboardingTests",
    dependencies: ["FeatureOnboarding", "Persistence", "Transport", "Wire"]),
  .testTarget(
    name: "FeatureSettingsTests",
    dependencies: ["FeatureSettings", "Persistence", "Transport", "Wire"]),
  .testTarget(
    name: "FeaturePairingTests", dependencies: ["FeaturePairing", "Transport", "Wire"]),
  .testTarget(
    name: "FeatureInboxTests",
    dependencies: ["FeatureInbox", "Persistence", "Transport", "Wire"]),
  .testTarget(name: "WidgetBridgeTests", dependencies: ["Persistence", "Pet", "WidgetBridge"]),
  .testTarget(name: "PetTests", dependencies: ["BilletKit", "Pet"]),
  .testTarget(
    name: "LabsTests",
    dependencies: [
      "DesignSystem", "Domain", "FeatureInbox", "Ink", "Labs", "Persistence", "Pet", "WidgetBridge",
      "Wire",
    ]),
  .testTarget(name: "PetSceneTests", dependencies: ["Pet", "PetScene"]),
  .testTarget(
    name: "PetSceneCatalogTests",
    dependencies: ["Persistence", "Pet", "PetScene", "PetSceneCatalog"]),
]

let products: [String] = library.map(\.name) + features + ["FeatureHome"]

let package = Package(
  name: "Billet",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: products.map { .library(name: $0, targets: [$0]) },
  targets: libraryTargets + featureTargets + [homeTarget] + testTargets,
  swiftLanguageModes: [.v6]
)
