/// Wire form of the contracts `LocalizedText`: a string a person reads, in each language the app
/// ships.
public struct LocalizedText: Codable, Hashable, Sendable {
  public let en: String
  public let ru: String

  public init(en: String, ru: String) {
    self.en = en
    self.ru = ru
  }

  /// The text for `languageCode` (such as `ru`), English for any other.
  public func text(for languageCode: String?) -> String {
    languageCode == "ru" ? ru : en
  }
}
