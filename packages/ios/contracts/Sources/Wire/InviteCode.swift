import Foundation

/// The server checks its format; the client checks only that it is not empty.
public struct InviteCode: Codable, Hashable, Sendable {
  public let rawValue: String

  /// The contract's `inviteCodeAlphabet` and `inviteCodeLength`; a test in contracts keeps them so.
  public static let alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
  public static let length = 10
  /// The contract's `reviewCodeLength`: the App Review pair's code, typed in the same field.
  public static let reviewLength = 26

  /// Claimed on its own route.
  public var isReview: Bool { rawValue.count == Self.reviewLength }

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  /// Drops case, spaces and dashes.
  public static func normalized(_ typed: String) -> String {
    String(typed.uppercased().filter { !$0.isWhitespace && $0 != "-" })
  }

  /// What was typed or pasted, kept to the symbols a code has, up to the App Review pair's longer code.
  public static func cleaned(_ typed: String) -> String {
    String(normalized(typed).filter { alphabet.contains($0) }.prefix(reviewLength))
  }

  /// In fives, as the invite page shows it ("K7QM4 R2XHP"): easier to read out and to type back.
  public static func grouped(_ code: String) -> String {
    stride(from: 0, to: code.count, by: 5).map { start in
      String(code.dropFirst(start).prefix(5))
    }.joined(separator: " ")
  }

  /// A code typed or carried by a link in any case, grouped by spaces or dashes; nil for anything else.
  public static func parsed(_ typed: String) -> InviteCode? {
    let code = normalized(typed)
    guard [length, reviewLength].contains(code.count), code.allSatisfy(alphabet.contains) else {
      return nil
    }
    return InviteCode(code)
  }

  /// The contract's `inviteLinkPath` on the server the app is built for: the universal link, or the page
  /// for a phone without the app.
  public func link(on server: URL) -> URL {
    server.appending(path: "i/\(rawValue)")
  }

  public init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    guard !value.isEmpty else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "InviteCode must not be empty"))
    }
    rawValue = value
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
