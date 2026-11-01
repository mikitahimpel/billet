// swift-tools-version: 6.2
import PackageDescription

// The only package that links Rive. Dropping it from apps/ios/project.yml removes Rive and the
// Little House from the app.
let package = Package(
  name: "PetSceneRive",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [.library(name: "PetSceneRive", targets: ["PetSceneRive"])],
  dependencies: [
    .package(path: "../../ios"),
    .package(url: "https://github.com/rive-app/rive-ios.git", exact: "6.29.0"),
  ],
  targets: [
    .target(
      name: "PetSceneRive",
      dependencies: [
        .product(name: "Pet", package: "ios"),
        .product(name: "PetScene", package: "ios"),
        .product(name: "RiveRuntime", package: "rive-ios"),
      ],
      resources: [
        .copy("Resources/LittleHouse.riv"),
        .copy("Resources/pose-sleeping.png"),
        .copy("Resources/pose-proud.png"),
      ]
    ),
    .testTarget(
      name: "PetSceneRiveTests",
      dependencies: [
        "PetSceneRive",
        .product(name: "Pet", package: "ios"),
        .product(name: "PetScene", package: "ios"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
