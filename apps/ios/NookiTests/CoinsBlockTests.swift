import Testing
import WidgetBridge
import Wire
@testable import Billet

@Suite struct CoinsBlockTests {
    @Test func thePacksShowOnlyWhenTheServerSellsCoins() {
        #expect(CoinsBlock.Mode.of(RemoteFlags()) == .earn)
        #expect(CoinsBlock.Mode.of(RemoteFlags(assignments: ["payments": "off"])) == .earn)
        #expect(CoinsBlock.Mode.of(RemoteFlags(assignments: ["payments": "maybe"])) == .earn)
        #expect(CoinsBlock.Mode.of(RemoteFlags(assignments: ["payments": "on"])) == .packs)
    }

    @Test func thePacksAreTheOnesTheServerSells() {
        #expect(CoinPackOffer.bundled.map(\.coins) == [100, 550, 1200])
    }

    @Test func anEntryReadsAsWhatItWasFor() {
        let spend = CoinLine(CoinEntry(id: "spend:k", kind: .spend, amount: -60, ref: "yarn", at: 0))
        #expect(spend.title == Catalog.item("yarn")?.name)
        #expect(spend.amount == "−60")
        #expect(!spend.isGain)
        let wish = CoinLine(CoinEntry(id: "earn:wish:w1", kind: .earn, amount: 20, ref: "w1", at: 0))
        #expect(wish.title == "A wish came true")
        #expect(wish.amount == "+20")
        #expect(CoinLine(CoinEntry(id: "earn:k", kind: .earn, amount: 5, ref: "k", at: 0)).title == "Notes and care")
        #expect(CoinLine(CoinEntry(id: "gift:welcome", kind: .gift, amount: 560, ref: "welcome", at: 0)).title
            == "Welcome coins")
        #expect(CoinLine(CoinEntry(id: "spend:t", kind: .spend, amount: -10, ref: "treat", at: 0)).title == "A treat")
    }
}
