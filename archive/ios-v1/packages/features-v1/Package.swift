// swift-tools-version: 6.2
import PackageDescription

// The v1 app's own screens: the home and its shop, settings, the inbox, Labs, the widget's surfaces
// and the scene catalog. Built on the live packages in packages/ios.

let live = "../../../../packages/ios"

// Where each module from another package lives. Names not listed here are targets of this package.
let packageOf = [
  "Wire": "contracts",
  "BilletKit": "core", "DesignSystem": "core", "Ink": "core", "Transport": "core",
  "Persistence": "core", "Delivery": "core",
  "Pet": "pet", "PetScene": "pet",
  "FeatureCanvas": "features", "FeatureOnboarding": "features", "FeaturePairing": "features",
  "WidgetBridge": "features",
  "Payments": "payments",
]

func dependencies(_ names: [String]) -> [Target.Dependency] {
  names.map { name in
    packageOf[name].map { .product(name: name, package: $0) } ?? .target(name: name)
  }
}

let featureDependencies = ["BilletKit", "Wire", "Ink", "DesignSystem", "Transport", "Persistence"]

let library: [(name: String, dependencies: [String])] = [
  // Shared with the widget and Live Activity, so it never depends on a feature target.
  ("Surfaces", ["Ink", "DesignSystem", "Pet", "WidgetBridge"]),
  ("PetSceneCatalog", ["Persistence", "Pet", "PetScene"]),
  ("FeatureInbox", featureDependencies),
  ("FeatureSettings", featureDependencies + ["Pet", "PetScene", "WidgetBridge"]),
  (
    "Labs",
    ["Wire", "Ink", "DesignSystem", "Persistence", "Pet", "WidgetBridge", "FeatureInbox"]
  ),
  (
    "FeatureHome",
    [
      "BilletKit", "Delivery", "DesignSystem", "FeatureCanvas", "FeatureInbox", "FeatureOnboarding",
      "FeaturePairing", "FeatureSettings", "Ink", "Labs", "Persistence", "Payments", "Pet",
      "PetScene", "Transport", "WidgetBridge", "Wire",
    ]
  ),
]

let tests: [(name: String, dependencies: [String])] = [
  (
    "FeatureHomeTests",
    [
      "BilletKit", "Delivery", "FeatureHome", "FeatureInbox", "Ink", "Payments", "Persistence",
      "Pet", "PetScene", "Transport", "WidgetBridge", "Wire",
    ]
  ),
  ("FeatureSettingsTests", ["FeatureSettings", "Persistence", "Transport", "Wire"]),
  ("FeatureInboxTests", ["FeatureInbox", "Persistence", "Transport", "Wire"]),
  (
    "LabsTests",
    [
      "DesignSystem", "FeatureInbox", "Ink", "Labs", "Persistence", "Pet", "WidgetBridge", "Wire",
    ]
  ),
  ("PetSceneCatalogTests", ["Persistence", "Pet", "PetScene", "PetSceneCatalog"]),
  ("PrivacyManifestTests", []),
]

let package = Package(
  name: "BilletFeaturesV1",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: library.map { .library(name: $0.name, targets: [$0.name]) },
  dependencies: ["contracts", "core", "pet", "features", "payments"].map {
    .package(path: "\(live)/\($0)")
  },
  targets: library.map { .target(name: $0.name, dependencies: dependencies($0.dependencies)) }
    + tests.map { .testTarget(name: $0.name, dependencies: dependencies($0.dependencies)) },
  swiftLanguageModes: [.v6]
)
