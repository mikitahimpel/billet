// swift-tools-version: 6.2
import PackageDescription

// Shared building blocks over the contracts: networking, storage, delivery, ink and the design system.
let library: [(name: String, dependencies: [Target.Dependency])] = [
  ("BilletKit", []),
  ("DesignSystem", []),
  (
    "Ink",
    [
      "BilletKit", .product(name: "Domain", package: "contracts"),
      .product(name: "Wire", package: "contracts"),
    ]
  ),
  (
    "Transport",
    [
      "BilletKit", .product(name: "Domain", package: "contracts"),
      .product(name: "Wire", package: "contracts"),
    ]
  ),
  ("Persistence", [.product(name: "Domain", package: "contracts")]),
  (
    "Delivery",
    [
      .product(name: "Domain", package: "contracts"), .product(name: "Wire", package: "contracts"),
      "Ink", "Persistence",
    ]
  ),
]

let wire: Target.Dependency = .product(name: "Wire", package: "contracts")

let package = Package(
  name: "BilletCore",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: library.map { .library(name: $0.name, targets: [$0.name]) },
  dependencies: [.package(path: "../contracts")],
  targets: library.map {
    .target(
      name: $0.name,
      dependencies: $0.dependencies,
      resources: $0.name == "DesignSystem"
        ? [.copy("Resources/Fonts"), .copy("Resources/Paper")] : nil
    )
  } + [
    .testTarget(name: "BilletKitTests", dependencies: ["BilletKit"]),
    .testTarget(name: "TransportTests", dependencies: ["BilletKit", "Transport", wire]),
    .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
    .testTarget(name: "InkTests", dependencies: ["BilletKit", "Ink", wire]),
    .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
    .testTarget(name: "PrivacyManifestTests"),
  ],
  swiftLanguageModes: [.v6]
)
