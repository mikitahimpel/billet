import Foundation
import Persistence
import Testing

@testable import FeatureShop

@Suite struct PlusWelcomeTests {
  nonisolated static let now = Date(timeIntervalSince1970: 1_790_000_000)

  @Test func aNewPairWithPlusOnOfferSeesItOnce() {
    let fresh = PlusWelcome()
    #expect(fresh.shows(onboarded: true, paired: true, partnerWaiting: false, entry: .offer))
    let shown = PlusWelcome(shownAt: Self.now)
    #expect(!shown.shows(onboarded: true, paired: true, partnerWaiting: false, entry: .offer))
  }

  @Test(arguments: [
    (false, true, false, PlusEntry.offer), (true, false, false, .offer), (true, true, true, .offer),
    (true, true, false, .hidden), (true, true, false, .has), (true, true, false, .parcels(1)),
  ])
  func neverBeforeOnboardingWhileThePartnerWaitsOrWhenNotOnOffer(
    onboarded: Bool, paired: Bool, waiting: Bool, entry: PlusEntry
  ) {
    #expect(
      !PlusWelcome().shows(
        onboarded: onboarded, paired: paired, partnerWaiting: waiting, entry: entry))
  }

  @Test func whatWasShownStaysShownAndAnUnreadableFileCountsAsShown() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let storage = AppGroupStorage.directory(folder)
    let store = PlusWelcomeStore.storage(storage) { Self.now }
    #expect(store.load() == PlusWelcome())
    store.save(PlusWelcome(shownAt: Self.now))
    #expect(store.load().shownAt == Self.now)
    try Data("{".utf8).write(to: folder.appending(path: "plus-welcome.json"))
    #expect(store.load().shownAt == Self.now)
  }
}
