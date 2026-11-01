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
  ("Pet", []),
  ("Transport", ["BilletKit", "Domain", "Wire"]),
  ("Persistence", ["Domain"]),
  ("Delivery", ["Domain", "Wire", "Ink", "Persistence"]),
  ("Surfaces", ["Domain", "Ink", "DesignSystem"]),
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

let featureTargets: [Target] = features.map {
  .target(name: $0, dependencies: featureDependencies.map { .init(stringLiteral: $0) })
}

// The only target that links Rive. Surfaces and the widget stay free of it.
let homeTarget: Target = .target(
  name: "FeatureHome",
  dependencies: [
    "BilletKit",
    "Delivery",
    "DesignSystem",
    "FeatureCanvas",
    "FeatureInbox",
    "FeatureSettings",
    "Ink",
    "Persistence",
    "Pet",
    "Wire",
    .product(name: "RiveRuntime", package: "rive-ios"),
  ],
  resources: [.copy("Resources/LittleHouse.riv")]
)

let testTargets: [Target] = [
  .testTarget(name: "BilletKitTests", dependencies: ["BilletKit"]),
  .testTarget(name: "WireConformanceTests", dependencies: ["Wire"]),
  .testTarget(name: "TransportTests", dependencies: ["BilletKit", "Transport", "Wire"]),
  .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
  .testTarget(name: "InkTests", dependencies: ["BilletKit", "Ink", "Wire"]),
  .testTarget(name: "FeatureCanvasTests", dependencies: ["FeatureCanvas", "Wire"]),
  .testTarget(name: "PetTests", dependencies: ["Pet"]),
  .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
  .testTarget(
    name: "FeatureHomeTests",
    dependencies: ["BilletKit", "Delivery", "FeatureHome", "FeatureInbox", "Ink", "Persistence", "Wire"]),
  .testTarget(name: "FeatureInboxTests", dependencies: ["FeatureInbox", "Persistence", "Wire"]),
]

let products: [String] = library.map(\.name) + features + ["FeatureHome"]

let package = Package(
  name: "Billet",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: products.map { .library(name: $0, targets: [$0]) },
  dependencies: [
    .package(url: "https://github.com/rive-app/rive-ios.git", exact: "6.29.0")
  ],
  targets: libraryTargets + featureTargets + [homeTarget] + testTargets,
  swiftLanguageModes: [.v6]
)
