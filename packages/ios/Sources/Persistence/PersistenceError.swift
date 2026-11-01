public enum PersistenceError: Error, Equatable, Sendable {
  /// A Keychain call returned this `OSStatus`.
  case keychain(status: Int32)
  case storage(String)
  case invalidName(String)
  case appGroupUnavailable(String)
  /// Stored bytes were not what was written.
  case corrupted(String)
}
