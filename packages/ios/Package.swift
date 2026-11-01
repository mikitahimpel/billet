// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Billet",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [
    .library(name: "BilletKit", targets: ["BilletKit"])
  ],
  targets: [
    .target(name: "BilletKit"),
    .testTarget(name: "BilletKitTests", dependencies: ["BilletKit"]),
  ],
  swiftLanguageModes: [.v6]
)
