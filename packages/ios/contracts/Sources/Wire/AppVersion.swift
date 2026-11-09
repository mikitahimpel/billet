import Foundation

/// `<marketing>` or `<marketing>+<build>`, such as `1.2.0+14`, as sent in `X-Billet-App-Version`.
/// Marketing has one to four numeric parts of up to four digits, the build up to eight digits;
/// decoding refuses anything else.
public struct AppVersion: Codable, Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String
  /// Most significant first.
  public let parts: [Int]
  public let build: Int?

  public init?(_ rawValue: String) {
    let halves = rawValue.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
    guard let marketing = halves.first else { return nil }
    let pieces = marketing.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...4).contains(pieces.count),
      pieces.allSatisfy({ Self.isNumber($0, maxDigits: 4) })
    else { return nil }
    var build: Int?
    if halves.count == 2 {
      guard Self.isNumber(halves[1], maxDigits: 8) else { return nil }
      build = Int(halves[1])
    }
    self.rawValue = rawValue
    self.parts = pieces.compactMap { Int($0) }
    self.build = build
  }

  public var description: String { rawValue }

  /// Matches the server's `compareAppVersions`: missing parts count as 0, and the build is
  /// compared only when both name one, so `1.2` equals every build of 1.2.
  public func compare(_ other: AppVersion) -> ComparisonResult {
    for index in 0..<max(parts.count, other.parts.count) {
      let mine = index < parts.count ? parts[index] : 0
      let theirs = index < other.parts.count ? other.parts[index] : 0
      if mine != theirs { return mine < theirs ? .orderedAscending : .orderedDescending }
    }
    guard let build, let otherBuild = other.build, build != otherBuild else {
      return .orderedSame
    }
    return build < otherBuild ? .orderedAscending : .orderedDescending
  }

  public func isOlder(than minimum: AppVersion) -> Bool {
    compare(minimum) == .orderedAscending
  }

  public init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    guard let version = AppVersion(value) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "AppVersion must be <marketing> or <marketing>+<build>"))
    }
    self = version
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  private static func isNumber(_ text: Substring, maxDigits: Int) -> Bool {
    (1...maxDigits).contains(text.count) && text.allSatisfy { $0.isASCII && $0.isNumber }
  }
}
