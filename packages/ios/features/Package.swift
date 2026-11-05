// swift-tools-version: 6.2
import PackageDescription

// The top layer: the screens the app borrows (canvas, onboarding, pairing) and the bridge between
// the app and its widget. Depends on every layer below it; nothing depends on this package except
// the apps.

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

let features = ["FeatureOnboarding", "FeaturePairing", "FeatureCanvas"]

let featureDependencies = ["BilletKit", "Wire", "Ink", "DesignSystem", "Transport", "Persistence"]

// Shared by the app and the widget: flags, the published snapshot, the picture rules and the
// queue of actions taken outside the app.
let widgetBridge: Target = .target(
  name: "WidgetBridge",
  dependencies: dependencies(["DesignSystem", "Delivery", "Persistence", "Pet"])
)

let tests: [(name: String, dependencies: [String])] = [
  ("FeatureCanvasTests", ["FeatureCanvas", "Wire"]),
  ("FeatureOnboardingTests", ["FeatureOnboarding", "Persistence", "Transport", "Wire"]),
  ("FeaturePairingTests", ["FeaturePairing", "Transport", "Wire"]),
  ("WidgetBridgeTests", ["Delivery", "Persistence", "Pet", "WidgetBridge"]),
]

let products = features + ["WidgetBridge"]

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
    + [widgetBridge]
    + tests.map { .testTarget(name: $0.name, dependencies: dependencies($0.dependencies)) },
  swiftLanguageModes: [.v6]
)
