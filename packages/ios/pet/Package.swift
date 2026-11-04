// swift-tools-version: 6.2
import PackageDescription

// The cat: its brain, the scene contract and the scene catalog. No graphics engine links into this
// package: each engine lives in its own package under packages/pet-scenes, chosen by the app.
let billetKit: Target.Dependency = .product(name: "BilletKit", package: "core")
let designSystem: Target.Dependency = .product(name: "DesignSystem", package: "core")
let persistence: Target.Dependency = .product(name: "Persistence", package: "core")

let package = Package(
  name: "BilletPet",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: ["Pet", "PetScene", "PetSceneCatalog"].map { .library(name: $0, targets: [$0]) },
  dependencies: [.package(path: "../core")],
  targets: [
    .target(name: "Pet", dependencies: [billetKit, designSystem]),
    .target(name: "PetScene", dependencies: [designSystem, "Pet"]),
    .target(name: "PetSceneCatalog", dependencies: [persistence, "Pet", "PetScene"]),
    .testTarget(name: "PetTests", dependencies: [billetKit, "Pet"]),
    .testTarget(name: "PetSceneTests", dependencies: ["Pet", "PetScene"]),
    .testTarget(
      name: "PetSceneCatalogTests",
      dependencies: [persistence, "Pet", "PetScene", "PetSceneCatalog"]),
  ],
  swiftLanguageModes: [.v6]
)
