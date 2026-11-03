/// The variant one experiment gives this pair. Both partners always get the same one. The server
/// checks that `key` and `variant` are lowercase hyphenated words; the client only needs them to be
/// non-empty and looks them up in the variants its own build contains.
public struct FlagAssignment: Codable, Hashable, Sendable {
  public let key: String
  public let variant: String

  public init(key: String, variant: String) {
    self.key = key
    self.variant = variant
  }

  private enum CodingKeys: String, CodingKey {
    case key
    case variant
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    key = try Self.nonEmpty(container, .key)
    variant = try Self.nonEmpty(container, .variant)
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

/// Every running experiment and the variant the pair is in. One that is not listed is off, and the
/// client uses its built-in default. A client replaces its stored copy with this list, never merges.
///
/// `status` is the service's status, the same as `GET /v1/status` answers, when the server sends it.
public struct FlagsResponse: Codable, Hashable, Sendable {
  public let flags: [FlagAssignment]
  public let status: AppStatus?

  public init(flags: [FlagAssignment], status: AppStatus? = nil) {
    self.flags = flags
    self.status = status
  }
}
