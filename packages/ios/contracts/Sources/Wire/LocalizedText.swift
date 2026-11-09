public struct LocalizedText: Codable, Hashable, Sendable {
  public let en: String
  public let ru: String

  public init(en: String, ru: String) {
    self.en = en
    self.ru = ru
  }

  /// English for any language it lacks.
  public func text(for languageCode: String?) -> String {
    languageCode == "ru" ? ru : en
  }
}
