import ShopInterface
import Testing
import Wire

@Suite struct NotePostageTests {
  @Test func everyStampAndSealIsSoldOnce() {
    #expect(NotePostage.all.count == NoteStamp.allCases.count + NoteSeal.allCases.count)
    #expect(Set(NotePostage.all.map(\.id)).count == NotePostage.all.count)
  }

  @Test func idsAndPricesAreTheServers() {
    #expect(NotePostage(NoteStamp.heart).id == "stamp-heart")
    #expect(NotePostage(NoteSeal.plum).id == "seal-plum")
    #expect(NotePostage.stamps.allSatisfy { $0.price == 30 })
    #expect(NotePostage.seals.allSatisfy { $0.price == 45 })
  }

  @Test func nothingIsOwnedUntilUnlocked() {
    #expect(NotePostage.all.allSatisfy { !$0.isOwned(["lamp", "rug", "ink-graphite"]) })
    #expect(NotePostage(NoteSeal.honey).isOwned(["seal-honey"]))
  }

  @Test func aShelfCardNamesItWithoutItsKind() {
    #expect(NotePostage(NoteStamp.moon).shortName == "Moon")
    #expect(NotePostage(NoteSeal.meadow).shortName == "Meadow")
    #expect(NotePostage(NoteSeal.meadow).name == "Meadow seal")
  }
}
