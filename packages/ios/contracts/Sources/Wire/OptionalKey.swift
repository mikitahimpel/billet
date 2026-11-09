extension KeyedDecodingContainer {
  /// Decodes a schema `optionalKey`: absent is `nil`, and an explicit `null` is refused, as the
  /// server refuses it.
  func decodeOptionalKey<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
    guard contains(key) else { return nil }
    guard try !decodeNil(forKey: key) else {
      throw DecodingError.dataCorruptedError(
        forKey: key, in: self, debugDescription: "\(key.stringValue) must be absent, not null")
    }
    return try decode(T.self, forKey: key)
  }
}

extension KeyedDecodingContainer {
  /// Decodes a schema `optionalKey` of literals that may grow: an id this build doesn't know is
  /// `nil`, so a note decorated by a newer app still arrives, only without the decoration.
  func decodeKnownKey<T: RawRepresentable & Decodable>(_ type: T.Type, forKey key: Key) throws -> T?
  where T.RawValue == String {
    try decodeOptionalKey(String.self, forKey: key).flatMap(T.init(rawValue:))
  }
}
