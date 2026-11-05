// swift-tools-version: 6.2
import PackageDescription

// The cat: its brain and the scene contract. No graphics engine links into this package.
let billetKit: Target.Dependency = .product(name: "BilletKit", package: "core")
let designSystem: Target.Dependency = .product(name: "DesignSystem", package: "core")

let package = Package(
  name: "BilletPet",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: ["Pet", "PetScene"].map { .library(name: $0, targets: [$0]) },
  dependencies: [.package(path: "../core")],
  targets: [
    .target(name: "Pet", dependencies: [billetKit, designSystem]),
    .target(name: "PetScene", dependencies: [designSystem, "Pet"]),
    .testTarget(name: "PetTests", dependencies: [billetKit, "Pet"]),
    .testTarget(name: "PetSceneTests", dependencies: ["Pet", "PetScene"]),
  ],
  swiftLanguageModes: [.v6]
)
