import Foundation

/// None of it is a credential.
public struct AccountRecord: Codable, Equatable, Sendable {
  public var userID: String
  public var deviceID: String
  /// When the server stops accepting the session token, in epoch milliseconds.
  public var expiresAt: Int
  /// Whether an invite has been claimed, by this account or by its partner.
  public var isPaired: Bool
  /// The pair's ID, known only when this account entered the code.
  public var pairID: String?

  public init(
    userID: String, deviceID: String, expiresAt: Int, isPaired: Bool = false, pairID: String? = nil
  ) {
    self.userID = userID
    self.deviceID = deviceID
    self.expiresAt = expiresAt
    self.isPaired = isPaired
    self.pairID = pairID
  }
}

/// The signed-in account: its token in the shared Keychain and its record in the App Group, so the
/// app, widget and extensions all see the same one.
public struct AccountStore: Sendable {
  public static let recordName = "account.json"

  /// The saved account, or `nil` when signed out. A record without a token (or a token without a
  /// record) counts as signed out, so a half-written sign-in never looks signed in.
  public var load: @Sendable () throws(PersistenceError) -> (token: String, record: AccountRecord)?
  public var save: @Sendable (String, AccountRecord) throws(PersistenceError) -> Void
  public var setPaired: @Sendable (Bool, String?) throws(PersistenceError) -> Void
  /// Forgets the token and the record, for sign-out and account deletion.
  public var clear: @Sendable () throws(PersistenceError) -> Void

  public init(
    load:
      @escaping @Sendable () throws(PersistenceError) -> (
        token: String, record: AccountRecord
      )?,
    save: @escaping @Sendable (String, AccountRecord) throws(PersistenceError) -> Void,
    setPaired: @escaping @Sendable (Bool, String?) throws(PersistenceError) -> Void,
    clear: @escaping @Sendable () throws(PersistenceError) -> Void
  ) {
    self.load = load
    self.save = save
    self.setPaired = setPaired
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
      setPaired: { (isPaired, pairID) throws(PersistenceError) in
        guard var record = try storage.readJSON(AccountRecord.self, named: recordName) else {
          return
        }
        record.isPaired = isPaired
        record.pairID = pairID
        try storage.writeJSON(record, named: recordName)
      },
      clear: { () throws(PersistenceError) in
        try tokens.clear()
        try storage.remove(recordName)
      })
  }
}
