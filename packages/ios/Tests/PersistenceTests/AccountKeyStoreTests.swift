import Foundation
import Testing

@testable import Persistence

@Suite struct AccountKeyStoreTests {
  static func store(_ keychain: FakeKeychain, byte: UInt8 = 0xAB) -> AccountKeyStore {
    .keychain(client: keychain.client, service: "billet") { count in
      Data(repeating: byte, count: count)
    }
  }

  @Test func makesA43CharacterBase64URLKeyOnce() throws {
    let keychain = FakeKeychain()
    let store = Self.store(keychain)
    let key = try store.loadOrCreate()
    #expect(key.count == 43)
    #expect(key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    #expect(try store.loadOrCreate() == key)
    #expect(keychain.snapshot.adds.count == 1)
  }

  @Test func keepsTheKeyInTheICloudKeychain() throws {
    let keychain = FakeKeychain()
    _ = try Self.store(keychain).loadOrCreate()
    #expect(keychain.snapshot.adds.map(\.synchronizable) == [true])
    #expect(keychain.snapshot.adds.map(\.accessGroup) == [nil])
  }

  @Test func usesTheKeyAnotherPhoneSynced() throws {
    let keychain = FakeKeychain()
    let synced = try Self.store(keychain, byte: 0x01).loadOrCreate()
    #expect(try Self.store(keychain, byte: 0x02).loadOrCreate() == synced)
  }

  @Test func clearForgetsTheKeyAndToleratesNone() throws {
    let keychain = FakeKeychain()
    let store = Self.store(keychain)
    let first = try store.loadOrCreate()
    try store.clear()
    try store.clear()
    #expect(keychain.snapshot.items.isEmpty)
    #expect(try Self.store(keychain, byte: 0x07).loadOrCreate() != first)
  }

  @Test func failsWithoutRandomBytesInsteadOfAWeakKey() {
    let store = AccountKeyStore.keychain(client: FakeKeychain().client, service: "billet") { _ in
      nil
    }
    #expect(throws: PersistenceError.self) { try store.loadOrCreate() }
  }

  @Test func surfacesKeychainFailures() {
    let keychain = FakeKeychain()
    keychain.failEveryCall(with: -25291)
    #expect(throws: PersistenceError.keychain(status: -25291)) {
      try Self.store(keychain).loadOrCreate()
    }
  }

  @Test func encodesBase64URLWithoutPadding() {
    #expect(AccountKeyStore.base64URL(Data([0xFB, 0xFF])) == "-_8")
  }
}
