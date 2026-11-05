import Foundation
import Security

/// The account key: 32 random bytes that are the anonymous account. It is made once, on the first
/// launch, and kept in the iCloud Keychain, so the user's other and future phones sign in to the
/// same account with no prompt. Only the server's hash of it exists anywhere else.
public struct AccountKeyStore: Sendable {
  /// The key, made and saved the first time it is asked for.
  public var loadOrCreate: @Sendable () throws(PersistenceError) -> String
  /// Forgets the key on every phone, for account deletion.
  public var clear: @Sendable () throws(PersistenceError) -> Void

  public init(
    loadOrCreate: @escaping @Sendable () throws(PersistenceError) -> String,
    clear: @escaping @Sendable () throws(PersistenceError) -> Void
  ) {
    self.loadOrCreate = loadOrCreate
    self.clear = clear
  }

  /// A store in the iCloud Keychain. `random` gives the key's bytes; tests pass a fixed source.
  public static func keychain(
    client: KeychainClient,
    service: String,
    account: String = "account-key",
    random: @escaping @Sendable (Int) -> Data? = AccountKeyStore.secureRandom
  ) -> AccountKeyStore {
    let key = KeychainItemKey(
      service: service, account: account, accessGroup: nil, synchronizable: true)

    @Sendable func load() throws(PersistenceError) -> String? {
      let result = client.read(key)
      if result.status == KeychainStatus.itemNotFound { return nil }
      guard result.status == KeychainStatus.success else {
        throw .keychain(status: result.status)
      }
      guard let data = result.data, let value = String(data: data, encoding: .utf8) else {
        throw .corrupted("account key is not UTF-8")
      }
      return value
    }

    return AccountKeyStore(
      loadOrCreate: { () throws(PersistenceError) -> String in
        if let existing = try load() { return existing }
        guard let bytes = random(32), bytes.count == 32 else {
          throw .corrupted("no random bytes for the account key")
        }
        let made = base64URL(bytes)
        let status = client.add(key, Data(made.utf8))
        // Another phone's key arrived through iCloud first: that one is the account.
        if status == KeychainStatus.duplicateItem, let synced = try load() { return synced }
        guard status == KeychainStatus.success else { throw .keychain(status: status) }
        return made
      },
      clear: { () throws(PersistenceError) in
        let status = client.delete(key)
        guard status == KeychainStatus.success || status == KeychainStatus.itemNotFound else {
          throw .keychain(status: status)
        }
      })
  }

  public static let secureRandom: @Sendable (Int) -> Data? = { count in
    var bytes = Data(count: count)
    let status = bytes.withUnsafeMutableBytes {
      SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
    }
    return status == errSecSuccess ? bytes : nil
  }

  /// Base64url without padding: 43 characters for 32 bytes, as the contract's `AccountKey`.
  static func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
