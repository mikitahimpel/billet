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
  ("Surfaces", ["Domain", "Ink", "DesignSystem"]),
]

let featureDependencies = [
  "BilletKit", "Domain", "Wire", "Ink", "DesignSystem", "Transport", "Persistence",
]

let package = Package(
  name: "Billet",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: (library.map(\.name) + features).map { .library(name: $0, targets: [$0]) },
  targets: library.map {
    .target(name: $0.name, dependencies: $0.dependencies.map { .init(stringLiteral: $0) })
  }
    + features.map {
      .target(name: $0, dependencies: featureDependencies.map { .init(stringLiteral: $0) })
    }
    + [
      .testTarget(name: "BilletKitTests", dependencies: ["BilletKit"]),
      .testTarget(name: "WireConformanceTests", dependencies: ["Wire"]),
      .testTarget(name: "TransportTests", dependencies: ["BilletKit", "Transport", "Wire"]),
      .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
      .testTarget(name: "InkTests", dependencies: ["BilletKit", "Ink", "Wire"]),
    ],
  swiftLanguageModes: [.v6]
)
