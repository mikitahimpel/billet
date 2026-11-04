import Foundation

/// Where the opaque session token lives, so the app, widget and extensions all read one copy.
public struct SessionTokenStore: Sendable {
  public var load: @Sendable () throws(PersistenceError) -> String?
  public var save: @Sendable (String) throws(PersistenceError) -> Void
  public var clear: @Sendable () throws(PersistenceError) -> Void

  public init(
    load: @escaping @Sendable () throws(PersistenceError) -> String?,
    save: @escaping @Sendable (String) throws(PersistenceError) -> Void,
    clear: @escaping @Sendable () throws(PersistenceError) -> Void
  ) {
    self.load = load
    self.save = save
    self.clear = clear
  }

  /// A store backed by the Keychain. Pass the shared `accessGroup` so extensions see the item.
  public static func keychain(
    client: KeychainClient,
    service: String,
    account: String = "session-token",
    accessGroup: String?
  ) -> SessionTokenStore {
    let key = KeychainItemKey(service: service, account: account, accessGroup: accessGroup)
    return SessionTokenStore(
      load: { () throws(PersistenceError) -> String? in
        let result = client.read(key)
        if result.status == KeychainStatus.itemNotFound {
          return nil
        }
        guard result.status == KeychainStatus.success else {
          throw .keychain(status: result.status)
        }
        guard let data = result.data, let token = String(data: data, encoding: .utf8) else {
          throw .corrupted("session token is not UTF-8")
        }
        return token
      },
      save: { token throws(PersistenceError) in
        let data = Data(token.utf8)
        var status = client.add(key, data)
        if status == KeychainStatus.duplicateItem {
          status = client.update(key, data)
        }
        guard status == KeychainStatus.success else {
          throw .keychain(status: status)
        }
      },
      clear: { () throws(PersistenceError) in
        let status = client.delete(key)
        guard status == KeychainStatus.success || status == KeychainStatus.itemNotFound else {
          throw .keychain(status: status)
        }
      }
    )
  }
}
