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
        .product(name: "Pet", package: "ios"),
        .product(name: "PetScene", package: "ios"),
      ],
      resources: [
        .copy("Resources/Cat.usdz"),
        .copy("Resources/Item_armchair.usdz"),
        .copy("Resources/Item_bookcase.usdz"),
        .copy("Resources/Item_donutbed.usdz"),
        .copy("Resources/Item_lamp.usdz"),
        .copy("Resources/Item_lantern.usdz"),
        .copy("Resources/Item_monstera.usdz"),
        .copy("Resources/Item_mouse.usdz"),
        .copy("Resources/Item_print.usdz"),
        .copy("Resources/Item_rug.usdz"),
        .copy("Resources/Item_teatable.usdz"),
        .copy("Resources/Item_tower.usdz"),
        .copy("Resources/Item_yarn.usdz"),
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
