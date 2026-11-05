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
