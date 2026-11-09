/// `key` names a localized string; `text` is shown when the app has none. The server checks the
/// format; the client only needs both non-empty.
public struct StatusMessage: Codable, Hashable, Sendable {
  public let key: String
  public let text: String

  public init(key: String, text: String) {
    self.key = key
    self.text = text
  }

  private enum CodingKeys: String, CodingKey {
    case key
    case text
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    key = try Self.nonEmpty(container, .key)
    text = try Self.nonEmpty(container, .text)
  }

  private static func nonEmpty(
    _ container: KeyedDecodingContainer<CodingKeys>, _ field: CodingKeys
  ) throws -> String {
    let value = try container.decode(String.self, forKey: field)
    guard !value.isEmpty else {
      throw DecodingError.dataCorruptedError(
        forKey: field, in: container, debugDescription: "\(field.rawValue) must not be empty")
    }
    return value
  }
}
