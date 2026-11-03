// swift-tools-version: 6.2
import PackageDescription

// The only package that links RealityKit. Dropping it from apps/ios/project.yml removes RealityKit
// and the Nooki assets from the app.
let package = Package(
  name: "PetSceneReality",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [.library(name: "PetSceneReality", targets: ["PetSceneReality"])],
  dependencies: [.package(path: "../../ios")],
  targets: [
    .target(
      name: "PetSceneReality",
      dependencies: [
        .product(name: "DesignSystem", package: "ios"),
        .product(name: "Pet", package: "ios"),
        .product(name: "PetScene", package: "ios"),
      ],
      resources: [
        .copy("Resources/Cats"),
        .copy("Resources/Shopkeepers"),
        .copy("Resources/Heart.reality"),
        .copy("Resources/Room.reality"),
        .copy("Resources/IdolProps.reality"),
        .copy("Resources/Room.usdz"),
        .copy("Resources/pose-sleeping.png"),
        .copy("Resources/pose-proud.png"),
      ]
    ),
    .testTarget(
      name: "PetSceneRealityTests",
      dependencies: [
        "PetSceneReality",
        .product(name: "Pet", package: "ios"),
        .product(name: "PetScene", package: "ios"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
