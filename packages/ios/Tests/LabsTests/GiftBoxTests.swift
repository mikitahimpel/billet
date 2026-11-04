import Foundation
import Testing

@testable import Labs

@Suite struct GiftBoxTests {
  @Test func aGiftOnTheDoormatOpensOnceAndGivesItsItem() {
    var box = GiftBox()
    let gift = Gift(itemID: "treat-fish", direction: .incoming)
    box.add(gift)
    #expect(box.waiting == [gift])
    #expect(box.unwrap(gift.id) == "treat-fish")
    #expect(box.unwrap(gift.id) == nil)
    #expect(box.waiting.isEmpty)
  }

  @Test func aGiftThisPhoneSentIsNotThisPhonesToOpen() {
    var box = GiftBox()
    let gift = Gift(itemID: "treat-fish", direction: .outgoing)
    box.add(gift)
    #expect(box.unwrap(gift.id) == nil)
    #expect(box.waiting.isEmpty)
  }

  @Test func theSameGiftIsNotAddedTwice() {
    var box = GiftBox()
    let gift = Gift(itemID: "treat-milk", direction: .incoming)
    box.add(gift)
    box.add(gift)
    #expect(box.gifts.count == 1)
  }

  @Test func theSenderSeesWhenItWasOpened() {
    var box = GiftBox()
    let gift = Gift(itemID: "furniture-yarn", direction: .outgoing)
    box.add(gift)
    box.partnerOpened(gift.id)
    #expect(box.gifts.first?.state == .opened)
  }

  @Test func theirOpeningCannotOpenOneOfOurs() {
    var box = GiftBox()
    let incoming = Gift(itemID: "treat-fish", direction: .incoming)
    box.add(incoming)
    box.partnerOpened(incoming.id)
    #expect(box.gifts.first?.state == .wrapped)
  }

  @Test func onlyAFewOpenedGiftsAreKept() {
    var box = GiftBox()
    let wrapped = Gift(itemID: "treat-fish", direction: .incoming)
    box.add(wrapped)
    for _ in 0..<6 {
      let gift = Gift(itemID: "treat-cookie", direction: .incoming)
      box.add(gift)
      _ = box.unwrap(gift.id)
    }
    #expect(box.gifts.filter { $0.state == .opened }.count == GiftBox.keepOpened)
    #expect(box.waiting == [wrapped])
  }

  @MainActor @Test func theStoreKeepsGiftsAcrossLaunches() {
    let defaults = UserDefaults(suiteName: "gifts-\(UUID().uuidString)") ?? .standard
    let store = GiftBoxStore(defaults: defaults)
    let gift = Gift(itemID: "treat-fish", direction: .incoming)
    store.add(gift)
    #expect(GiftBoxStore(defaults: defaults).box.waiting == [gift])
    #expect(store.unwrap(gift.id) == "treat-fish")
    #expect(GiftBoxStore(defaults: defaults).box.waiting.isEmpty)
    #expect(store.lastUnwrapped == gift.id)
  }

  @Test func aGiftSavedBeforeNotesStillLoadsWithoutOne() throws {
    let old =
      #"{"id":"0D4C9E3A-1D2B-4C5E-9F60-7A8B9C0D1E2F","itemID":"treat-fish","#
      + #""direction":"incoming","state":"wrapped"}"#
    let gift = try JSONDecoder().decode(Gift.self, from: Data(old.utf8))
    #expect(gift.note == nil)
    #expect(gift.itemID == "treat-fish")
  }

  @Test func aNoteTravelsWithItsGift() throws {
    let gift = Gift(itemID: "furniture-mouse", direction: .outgoing, note: "for the little one")
    let copy = try JSONDecoder().decode(Gift.self, from: JSONEncoder().encode(gift))
    #expect(copy == gift)
  }
}
