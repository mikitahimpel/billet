// swift-tools-version: 6.2
import PackageDescription

// The bottom layer: the domain values and the wire format shared with the server. Depends on nothing.
let package = Package(
  name: "BilletContracts",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [
    .library(name: "Domain", targets: ["Domain"]),
    .library(name: "Wire", targets: ["Wire"]),
  ],
  targets: [
    .target(name: "Domain"),
    .target(name: "Wire", dependencies: ["Domain"]),
    .testTarget(name: "WireConformanceTests", dependencies: ["Wire"]),
  ],
  swiftLanguageModes: [.v6]
)
