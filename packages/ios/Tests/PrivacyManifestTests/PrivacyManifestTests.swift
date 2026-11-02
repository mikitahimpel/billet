import Foundation
import Testing

/// The privacy manifests in `apps/ios` against the sources that go into each target.
///
/// The manifests must list every required-reason API the code calls, so a new call to one fails
/// here until its reason is declared.
@Suite struct PrivacyManifestTests {
  struct Manifest {
    var tracking: Bool
    var trackingDomains: [String]
    var collected: [String]
    /// API category to declared reasons.
    var accessed: [String: Set<String>]
  }

  static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

  static func manifest(_ target: String) throws -> Manifest {
    let url = root.appending(path: "apps/ios/\(target)/PrivacyInfo.xcprivacy")
    let data = try Data(contentsOf: url)
    let plist = try #require(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    let types = plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
    var accessed: [String: Set<String>] = [:]
    for type in types {
      let name = try #require(type["NSPrivacyAccessedAPIType"] as? String)
      accessed[name] = Set(type["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? [])
    }
    let collected = (plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? [])
      .compactMap { $0["NSPrivacyCollectedDataType"] as? String }
    return Manifest(
      tracking: plist["NSPrivacyTracking"] as? Bool ?? true,
      trackingDomains: plist["NSPrivacyTrackingDomains"] as? [String] ?? ["missing"],
      collected: collected, accessed: accessed)
  }

  static let targets = ["App", "Widget", "NotificationService"]

  @Test(arguments: targets)
  func everyTargetHasAManifestThatDoesNotTrack(target: String) throws {
    let manifest = try Self.manifest(target)
    #expect(!manifest.tracking)
    #expect(manifest.trackingDomains.isEmpty)
  }

  @Test func onlyTheAppDeclaresWhatItCollects() throws {
    let app = try Self.manifest("App").collected
    #expect(
      Set(app) == [
        "NSPrivacyCollectedDataTypeUserID", "NSPrivacyCollectedDataTypeDeviceID",
        "NSPrivacyCollectedDataTypePhotosorVideos", "NSPrivacyCollectedDataTypeOtherUserContent",
      ])
    #expect(try Self.manifest("Widget").collected.isEmpty)
    #expect(try Self.manifest("NotificationService").collected.isEmpty)
  }

  /// A source token that calls a required-reason API, and the category it belongs to.
  static let apis: [(token: String, category: String)] = [
    ("UserDefaults", "NSPrivacyAccessedAPICategoryUserDefaults"),
    ("systemUptime", "NSPrivacyAccessedAPICategorySystemBootTime"),
    ("mach_absolute_time", "NSPrivacyAccessedAPICategorySystemBootTime"),
    ("contentModificationDate", "NSPrivacyAccessedAPICategoryFileTimestamp"),
    ("creationDateKey", "NSPrivacyAccessedAPICategoryFileTimestamp"),
    ("fileModificationDate", "NSPrivacyAccessedAPICategoryFileTimestamp"),
    ("fileCreationDate", "NSPrivacyAccessedAPICategoryFileTimestamp"),
    ("volumeAvailableCapacity", "NSPrivacyAccessedAPICategoryDiskSpace"),
    ("systemFreeSize", "NSPrivacyAccessedAPICategoryDiskSpace"),
    ("activeInputModes", "NSPrivacyAccessedAPICategoryActiveKeyboards"),
  ]

  /// The categories the sources of `directories` use, from `Self.apis`.
  static func categoriesUsed(in directories: [String]) throws -> Set<String> {
    var used: Set<String> = []
    for directory in directories {
      let base = root.appending(path: directory)
      let files =
        FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
      for file in files where !file.path.contains("/Tests/") && !file.path.contains("/.build/") {
        let text = try String(contentsOf: file, encoding: .utf8)
        for api in apis where text.contains(api.token) { used.insert(api.category) }
      }
    }
    return used
  }

  @Test func theAppManifestDeclaresEveryAPIItsSourcesUse() throws {
    let used = try Self.categoriesUsed(in: [
      "apps/ios/App", "packages/ios/Sources", "packages/pet-scenes/reality/Sources",
      "packages/pet-scenes/rive/Sources",
    ])
    let declared = Set(try Self.manifest("App").accessed.keys)
    #expect(used.subtracting(declared).isEmpty, "undeclared: \(used.subtracting(declared))")
  }

  @Test func theExtensionsDeclareTheAPIsTheirOwnSourcesUse() throws {
    for target in ["Widget", "NotificationService"] {
      let used = try Self.categoriesUsed(in: ["apps/ios/\(target)"])
      let declared = Set(try Self.manifest(target).accessed.keys)
      #expect(
        used.subtracting(declared).isEmpty, "\(target) undeclared: \(used.subtracting(declared))")
    }
  }

  @Test func theReasonsAreOnesAppleDefines() throws {
    let allowed: [String: Set<String>] = [
      "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1", "1C8F.1", "C56D.1", "AC6B.1"],
      "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1", "8FFB.1", "3D61.1"],
      "NSPrivacyAccessedAPICategoryFileTimestamp": ["DDA9.1", "C617.1", "3B52.1", "0A2A.1"],
      "NSPrivacyAccessedAPICategoryDiskSpace": ["85F4.1", "E174.1", "7D9E.1", "B728.1"],
      "NSPrivacyAccessedAPICategoryActiveKeyboards": ["3EC4.1", "54BD.1"],
    ]
    for target in Self.targets {
      for (category, reasons) in try Self.manifest(target).accessed {
        let known = try #require(allowed[category], "\(target): unknown category \(category)")
        #expect(!reasons.isEmpty)
        #expect(reasons.isSubset(of: known), "\(target) \(category): \(reasons)")
      }
    }
  }
}
