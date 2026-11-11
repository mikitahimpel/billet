// swift-tools-version: 6.2
import Foundation
import PackageDescription

#if os(Linux)
  // Linux has none of Apple's UI, graphics or Keychain frameworks. A file that imports one is left
  // out there, and so are the targets in `appleOnly`, so the rest builds and tests on a Linux box
  // (docs/testflight-ci.md#tests-on-the-pc).
  func leaveOutAppleOnly(_ package: Package, targets appleOnly: Set<String>) {
    let frameworks: Set<String> = [
      "SwiftUI", "UIKit", "CoreGraphics", "QuartzCore", "ImageIO", "CoreText",
      "UniformTypeIdentifiers", "Security", "OSLog", "simd", "ActivityKit", "WidgetKit",
      "AppIntents", "AuthenticationServices", "StoreKit", "RealityKit", "Combine",
    ]
    func isAppleOnly(_ text: String) -> Bool {
      text.contains("URLProtocol")
        || text.split(separator: "\n").contains { line in
          let words = line.replacingOccurrences(of: "@testable ", with: "")
            .replacingOccurrences(of: "@preconcurrency ", with: "").split(separator: " ")
          return (line.first == "i" || line.first == "@")
            && words.count > 1 && words[0] == "import" && frameworks.contains(String(words[1]))
        }
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    package.targets.removeAll { appleOnly.contains($0.name) }
    package.products.removeAll { appleOnly.contains($0.name) }
    for target in package.targets {
      let directory = target.path ?? "\(target.type == .test ? "Tests" : "Sources")/\(target.name)"
      let base = root.appending(path: directory, directoryHint: .isDirectory)
      let files = FileManager.default.enumerator(atPath: base.path)?.compactMap { $0 as? String }
      target.exclude += (files ?? []).filter { path in
        path.hasSuffix(".swift")
          && (try? String(contentsOf: base.appending(path: path), encoding: .utf8))
            .map(isAppleOnly) == true
      }
    }
  }
#endif

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

#if os(Linux)
  leaveOutAppleOnly(package, targets: ["PetScene", "PetSceneTests"])
#endif
