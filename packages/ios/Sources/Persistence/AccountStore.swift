import Foundation

/// What the app keeps about the signed-in account besides the token: who this device is, when the
/// session ends, and who it is paired with. None of it is a credential.
public struct AccountRecord: Codable, Equatable, Sendable {
  public var userID: String
  public var deviceID: String
  /// When the server stops accepting the session token, in epoch milliseconds.
  public var expiresAt: Int
  /// Set once an invite has been claimed or accepted.
  public var pairID: String?

  public init(userID: String, deviceID: String, expiresAt: Int, pairID: String? = nil) {
    self.userID = userID
    self.deviceID = deviceID
    self.expiresAt = expiresAt
    self.pairID = pairID
  }
}

/// The signed-in account: its token in the shared Keychain and its record in the App Group, so the
/// app, widget and extensions all see the same one.
public struct AccountStore: Sendable {
  static let recordName = "account.json"

  /// The saved account, or `nil` when signed out. A record without a token (or a token without a
  /// record) counts as signed out, so a half-written sign-in never looks signed in.
  public var load: @Sendable () throws(PersistenceError) -> (token: String, record: AccountRecord)?
  public var save: @Sendable (String, AccountRecord) throws(PersistenceError) -> Void
  public var setPair: @Sendable (String?) throws(PersistenceError) -> Void
  /// Forgets the token and the record, for sign-out and account deletion.
  public var clear: @Sendable () throws(PersistenceError) -> Void

  public init(
    load:
      @escaping @Sendable () throws(PersistenceError) -> (
        token: String, record: AccountRecord
      )?,
    save: @escaping @Sendable (String, AccountRecord) throws(PersistenceError) -> Void,
    setPair: @escaping @Sendable (String?) throws(PersistenceError) -> Void,
    clear: @escaping @Sendable () throws(PersistenceError) -> Void
  ) {
    self.load = load
    self.save = save
    self.setPair = setPair
    self.clear = clear
  }

  public static func live(tokens: SessionTokenStore, storage: AppGroupStorage) -> AccountStore {
    AccountStore(
      load: { () throws(PersistenceError) in
        guard let token = try tokens.load(),
          let record = try storage.readJSON(AccountRecord.self, named: recordName)
        else { return nil }
        return (token, record)
      },
      save: { (token, record) throws(PersistenceError) in
        try storage.writeJSON(record, named: recordName)
        try tokens.save(token)
      },
      setPair: { (pairID) throws(PersistenceError) in
        guard var record = try storage.readJSON(AccountRecord.self, named: recordName) else {
          return
        }
        record.pairID = pairID
        try storage.writeJSON(record, named: recordName)
      },
      clear: { () throws(PersistenceError) in
        try tokens.clear()
        try storage.remove(recordName)
      })
  }
}
