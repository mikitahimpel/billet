// swift-tools-version: 6.2
import PackageDescription

// Sources/CatMotion/Cat holds links to the app's own cat files (apps/ios/Nooki/Scene), so the harness
// runs the code the phone runs; everything else here stands in for the app around them.
let package = Package(
  name: "CatMotion",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(path: "../../packages/ios/pet"),
    .package(path: "../../packages/ios/features"),
  ],
  targets: [
    .executableTarget(
      name: "CatMotion",
      dependencies: [
        .product(name: "Pet", package: "pet"),
        .product(name: "DecorInterface", package: "features"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6),
        .defaultIsolation(MainActor.self),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableUpcomingFeature("InferIsolatedConformances"),
      ]
    )
  ]
)
