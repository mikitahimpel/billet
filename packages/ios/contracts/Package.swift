// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "BilletContracts",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [.library(name: "Wire", targets: ["Wire"])],
  targets: [
    .target(name: "Wire"),
    .testTarget(name: "WireConformanceTests", dependencies: ["Wire"]),
  ],
  swiftLanguageModes: [.v6]
)
