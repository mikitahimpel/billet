extension KeyedDecodingContainer {
  /// A schema `optionalKey`: absent is `nil`; an explicit `null` is refused, as the server does.
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
  /// An id this build doesn't know is `nil`, so a note from a newer app arrives without the
  /// decoration.
  func decodeKnownKey<T: RawRepresentable & Decodable>(_ type: T.Type, forKey key: Key) throws -> T?
  where T.RawValue == String {
    try decodeOptionalKey(String.self, forKey: key).flatMap(T.init(rawValue:))
  }
}
