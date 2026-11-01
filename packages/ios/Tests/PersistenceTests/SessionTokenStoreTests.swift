import Testing

@testable import Persistence

@Suite struct SessionTokenStoreTests {
  static let group = "TEAM.com.example.shared"

  static func store(_ keychain: FakeKeychain) -> SessionTokenStore {
    .keychain(client: keychain.client, service: "billet", accessGroup: group)
  }

  @Test func loadsNothingBeforeASave() throws {
    #expect(try Self.store(FakeKeychain()).load() == nil)
  }

  @Test func savedTokenLoadsBack() throws {
    let store = Self.store(FakeKeychain())
    try store.save("token-1")
    #expect(try store.load() == "token-1")
  }

  @Test func savingAgainReplacesTheToken() throws {
    let keychain = FakeKeychain()
    let store = Self.store(keychain)
    try store.save("token-1")
    try store.save("token-2")
    #expect(try store.load() == "token-2")
    #expect(keychain.snapshot.updates == 1)
    #expect(keychain.snapshot.items.count == 1)
  }

  @Test func itemsLiveInTheSharedAccessGroup() throws {
    let keychain = FakeKeychain()
    try Self.store(keychain).save("token-1")
    #expect(keychain.snapshot.adds.map(\.accessGroup) == [Self.group])
  }

  @Test func clearRemovesTheTokenAndToleratesNone() throws {
    let store = Self.store(FakeKeychain())
    try store.save("token-1")
    try store.clear()
    #expect(try store.load() == nil)
    try store.clear()
  }

  @Test func keychainFailuresCarryTheStatus() {
    let keychain = FakeKeychain()
    keychain.failEveryCall(with: -34018)
    let store = Self.store(keychain)
    #expect(throws: PersistenceError.keychain(status: -34018)) { try store.load() }
    #expect(throws: PersistenceError.keychain(status: -34018)) { try store.save("t") }
    #expect(throws: PersistenceError.keychain(status: -34018)) { try store.clear() }
  }
}
