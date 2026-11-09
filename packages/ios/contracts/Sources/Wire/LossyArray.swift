extension KeyedDecodingContainer {
  /// Leaves out elements this build can't read, such as a kind the server added later, so one
  /// never fails the whole page.
  func decodeLossyArray<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> [T] {
    var list = try nestedUnkeyedContainer(forKey: key)
    var values: [T] = []
    while !list.isAtEnd {
      if let value = try? list.decode(T.self) {
        values.append(value)
      } else {
        // A failed decode leaves the container where it was.
        _ = try list.decode(Skipped.self)
      }
    }
    return values
  }
}

private struct Skipped: Decodable {
  init(from decoder: any Decoder) throws {}
}
