import Foundation

/// The build and system the app reports with each request, so events and flags can be read by app
/// version and OS. Nothing in it names a person or a device.
public struct ClientInfo: Equatable, Sendable {
  /// `<marketing version>+<build>`, such as `1.2.0+14`. `nil` when the bundle has no version.
  public let appVersion: String?
  /// The platform and its version, such as `iOS 26.1`.
  public let os: String

  public init(appVersion: String?, os: String) {
    self.appVersion = appVersion
    self.os = os
  }

  /// Reads the version from `info` (a bundle's info dictionary) and the system from `system`.
  public init(info: [String: Any], system: OperatingSystemVersion, platform: String = "iOS") {
    let marketing = info["CFBundleShortVersionString"] as? String
    let build = info["CFBundleVersion"] as? String
    appVersion = marketing.map { version in build.map { "\(version)+\($0)" } ?? version }
    let patch = system.patchVersion == 0 ? "" : ".\(system.patchVersion)"
    os = "\(platform) \(system.majorVersion).\(system.minorVersion)\(patch)"
  }

  public static func current() -> ClientInfo {
    ClientInfo(
      info: Bundle.main.infoDictionary ?? [:],
      system: ProcessInfo.processInfo.operatingSystemVersion)
  }

  /// The headers that carry it. A missing version is left out, and the server reads it as unknown.
  public var headers: [String: String] {
    var headers = [Routes.osHeader: os]
    if let appVersion { headers[Routes.appVersionHeader] = appVersion }
    return headers
  }
}
