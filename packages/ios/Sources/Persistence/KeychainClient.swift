import Foundation

/// The `OSStatus` values the session token store reacts to.
public enum KeychainStatus {
  public static let success: Int32 = 0
  public static let duplicateItem: Int32 = -25299
  public static let itemNotFound: Int32 = -25300
}

public struct KeychainItemKey: Hashable, Sendable {
  public var service: String
  public var account: String
  /// The shared Keychain access group. `nil` uses the app's default group.
  public var accessGroup: String?

  public init(service: String, account: String, accessGroup: String?) {
    self.service = service
    self.account = account
    self.accessGroup = accessGroup
  }
}

public struct KeychainReadResult: Equatable, Sendable {
  public var status: Int32
  public var data: Data?

  public init(status: Int32, data: Data?) {
    self.status = status
    self.data = data
  }
}

/// The Keychain as four closures that return an `OSStatus`. Tests pass an in-memory fake;
/// ``KeychainClient/security`` is the live one.
public struct KeychainClient: Sendable {
  public var add: @Sendable (KeychainItemKey, Data) -> Int32
  public var update: @Sendable (KeychainItemKey, Data) -> Int32
  public var read: @Sendable (KeychainItemKey) -> KeychainReadResult
  public var delete: @Sendable (KeychainItemKey) -> Int32

  public init(
    add: @escaping @Sendable (KeychainItemKey, Data) -> Int32,
    update: @escaping @Sendable (KeychainItemKey, Data) -> Int32,
    read: @escaping @Sendable (KeychainItemKey) -> KeychainReadResult,
    delete: @escaping @Sendable (KeychainItemKey) -> Int32
  ) {
    self.add = add
    self.update = update
    self.read = read
    self.delete = delete
  }
}
