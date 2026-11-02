import Foundation
import Testing

@testable import Persistence

@Suite struct AccountStoreTests {
  static func store() throws -> (AccountStore, FakeKeychain, URL) {
    let keychain = FakeKeychain()
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let tokens = SessionTokenStore.keychain(
      client: keychain.client, service: "test", accessGroup: nil)
    return (
      .live(tokens: tokens, storage: .directory(directory)), keychain, directory
    )
  }

  static let record = AccountRecord(userID: "u1", deviceID: "d1", expiresAt: 9)

  @Test func aSavedAccountComesBack() throws {
    let (store, _, _) = try Self.store()
    #expect(try store.load() == nil)
    try store.save("tok", Self.record)
    let saved = try store.load()
    let loaded = try #require(saved)
    #expect(loaded.token == "tok")
    #expect(loaded.record == Self.record)
  }

  @Test func theTokenIsNotInTheRecordFile() throws {
    let (store, _, directory) = try Self.store()
    try store.save("tok-secret", Self.record)
    let files = try FileManager.default.contentsOfDirectory(atPath: directory.path())
    for file in files {
      let text = try String(contentsOf: directory.appending(path: file), encoding: .utf8)
      #expect(!text.contains("tok-secret"))
    }
  }

  @Test func theTokenAloneIsSignedOut() throws {
    let (store, _, directory) = try Self.store()
    try store.save("tok", Self.record)
    try FileManager.default.removeItem(at: directory.appending(path: AccountStore.recordName))
    #expect(try store.load() == nil)
  }

  @Test func pairingIsKeptAndCleared() throws {
    let (store, _, _) = try Self.store()
    try store.save("tok", Self.record)
    try store.setPair("p1")
    #expect(try store.load()?.record.pairID == "p1")
    try store.setPair(nil)
    #expect(try store.load()?.record.pairID == nil)
  }

  @Test func clearingForgetsTokenAndRecord() throws {
    let (store, keychain, directory) = try Self.store()
    try store.save("tok", Self.record)
    try store.clear()
    #expect(try store.load() == nil)
    #expect(keychain.snapshot.items.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path()).isEmpty)
    try store.clear()
  }
}
