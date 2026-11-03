import Foundation
import Persistence
import Testing
import Transport
import WidgetBridge
import Wire

@testable import FeatureHome

@Suite @MainActor struct RealAppModelAccountTests {
  /// A paired account on this phone, in memory.
  final class Saved: @unchecked Sendable {
    private let lock = NSLock()
    private var record = AccountRecord(
      userID: "u", deviceID: "d", expiresAt: 1, isPaired: true, pairID: "p")

    var isPaired: Bool { lock.withLock { record.isPaired } }

    var store: AccountStore {
      AccountStore(
        load: { [self] () throws(PersistenceError) in
          lock.withLock { (token: "t", record: record) }
        },
        save: { (_, _) throws(PersistenceError) in },
        setPaired: { [self] (paired, id) throws(PersistenceError) in
          lock.withLock {
            record.isPaired = paired
            record.pairID = id
          }
        },
        clear: { () throws(PersistenceError) in })
    }
  }

  static let keys = AccountKeyStore(
    loadOrCreate: { () throws(PersistenceError) in "k" }, clear: { () throws(PersistenceError) in })

  static func model(account: AccountResponse, saved: Saved, storage: AppGroupStorage)
    -> RealAppModel
  {
    var api = APIClient.offline
    api.account = { () async throws(TransportError) in account }
    return RealAppModel(
      api: api, accounts: saved.store, keys: keys,
      baseURL: URL(string: "https://billet.test")!, reauthorize: { .cancelled },
      labs: WidgetFeaturesModel(store: nil), eventStorage: storage, hasWidget: { false })
  }

  static func storage() -> AppGroupStorage {
    .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
  }

  @Test func aPartnerWhoLeftEndsThePairAndIsToldOnce() async {
    let saved = Saved()
    let storage = Self.storage()
    let left = PartnerLeft(reason: .accountDeleted, at: 1_700_000_400_000)
    let account = AccountResponse(userId: UserId("u"), linked: false, partnerLeft: left)

    let model = Self.model(account: account, saved: saved, storage: storage)
    #expect(model.stage == .paired)
    await model.refreshAccount()
    #expect(model.stage == .unpaired)
    #expect(!saved.isPaired)
    #expect(model.partnerLeft == left)
    #expect(model.linked == false)

    model.partnerLeftSeen()
    #expect(model.partnerLeft == nil)
    // The server says so until the user pairs again; the phone remembers it was read.
    let later = Self.model(account: account, saved: saved, storage: storage)
    await later.refreshAccount()
    #expect(later.partnerLeft == nil)
  }

  @Test func aLinkedAccountWithAPartnerStaysAsItIs() async {
    let saved = Saved()
    let model = Self.model(
      account: AccountResponse(userId: UserId("u"), linked: true), saved: saved,
      storage: Self.storage())
    await model.refreshAccount()
    #expect(model.stage == .paired)
    #expect(model.linked == true)
    #expect(model.partnerLeft == nil)
  }

  @Test func theSaveCardWaitsForTheServerThenForAFewNotes() async {
    let model = Self.model(
      account: AccountResponse(userId: UserId("u"), linked: false), saved: Saved(),
      storage: Self.storage())
    // Before the server has said, the phone doesn't know whether the account is linked.
    #expect(!model.offersSaveAccount(notesSent: 10))
    await model.refreshAccount()
    #expect(!model.offersSaveAccount(notesSent: 1))
    #expect(model.offersSaveAccount(notesSent: 5))
    #expect(model.offersSaveAccount(notesSent: 0, now: .now.addingTimeInterval(8 * 24 * 3600.0)))
  }

  @Test func aClosedSaveCardStaysClosedAcrossLaunches() async {
    let storage = Self.storage()
    let account = AccountResponse(userId: UserId("u"), linked: false)
    let model = Self.model(account: account, saved: Saved(), storage: storage)
    await model.refreshAccount()
    model.dismissSaveAccount()
    #expect(!model.offersSaveAccount(notesSent: 5))

    let later = Self.model(account: account, saved: Saved(), storage: storage)
    await later.refreshAccount()
    #expect(!later.offersSaveAccount(notesSent: 5))
  }

  @Test func aLinkedAccountIsNeverAskedToSave() async {
    let model = Self.model(
      account: AccountResponse(userId: UserId("u"), linked: true), saved: Saved(),
      storage: Self.storage())
    await model.refreshAccount()
    #expect(!model.offersSaveAccount(notesSent: 50))
  }
}
