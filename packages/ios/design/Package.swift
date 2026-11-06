// swift-tools-version: 6.2
import PackageDescription

// The look of the app: colour, type, spacing, glass and the components every screen is built from. It depends
// on nothing else in the repository, so the app, its widgets and the feature packages can all import it.
let package = Package(
  name: "BilletDesign",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [.library(name: "Design", targets: ["Design"])],
  targets: [
    .target(name: "Design"),
    .testTarget(name: "DesignTests", dependencies: ["Design"]),
  ],
  swiftLanguageModes: [.v6]
)
