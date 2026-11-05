import Foundation
import Synchronization
import Testing
import Transport
import Wire
@testable import Billet

@Suite struct PaletteInkTests {
    @Test func theServersInksReadAsColours() throws {
        let ink = try #require(
            PaletteInk(Wire.Ink(id: InkId("ink-rose"), name: "Rose", light: "#D2456B", dark: "#FF8FAB", price: 60)))
        #expect(ink.light == 0xD2456B)
        #expect(ink.dark == 0xFF8FAB)
        #expect(PaletteInk.wire(ink.dark) == "#FF8FAB")
        #expect(PaletteInk(Wire.Ink(id: InkId("x"), name: "X", light: "red", dark: "#000000", price: 1)) == nil)
    }

    @Test func theBundledCatalogStartsFree() {
        #expect(PaletteInk.bundled.first == PaletteInk.free)
        #expect(PaletteInk.free.id == InkId.free.rawValue)
        #expect(PaletteInk.bundled.filter { $0.price == 0 } == [PaletteInk.free])
    }

    @Test func anInkBuyIsMarkedAsOneAndUndoesLikeAnyOther() throws {
        var wallet = Wallet()
        wallet.coins = 100
        let made = wallet.buy(["ink-rose"], cost: 60, title: "Rose ink", kind: .ink, at: .now)
        let purchase = try #require(made)
        #expect(purchase.kind == .ink)
        #expect(wallet.coins == 40)
        #expect(wallet.owned.contains("ink-rose"))
        wallet.undo(purchase)
        #expect(wallet.coins == 100)
        #expect(!wallet.owned.contains("ink-rose"))
    }

    @Test func oldNotesKeepTheirBrown() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","author":"L","date":0,"text":"hi","paper":"butter"}"#
        let note = try JSONDecoder().decode(Billet.Note.self, from: Data(json.utf8))
        #expect(note.ink == nil)
        #expect(note.inkHex == 0x5B3A28)
    }
}

/// One HomeState, whose wallet lives in the app group, so these run one at a time.
@MainActor @Suite(.serialized) struct InkSyncTests {
    let state = HomeState()

    init() {
        state.wallet.update {
            $0.coins = 200
            $0.owned = ["lamp"]
        }
    }

    /// A buy made long enough ago that its Undo window is over.
    private func bought(_ id: String, cost: Int = 60) throws -> Purchase {
        var made: Purchase?
        state.wallet.update { made = $0.buy([id], cost: cost, title: id, kind: .ink, at: .now.addingTimeInterval(-10)) }
        return try #require(made)
    }

    @Test func buyingAnInkPlaysThePurchaseMoment() {
        let rose = PaletteInk.bundled[1]
        #expect(state.buy(rose))
        #expect(state.coins == 140)
        #expect(state.lastPurchase?.kind == .ink)
        #expect(state.lastPurchase?.title == "Rose ink")
        #expect(!state.buy(rose))
        #expect(!state.buy(PaletteInk.free))
    }

    @Test func theServersInksReplaceThePhonesButNotItsRoomPieces() {
        state.wallet.update { $0.owned.insert("ink-sea") }
        state.apply(
            InksResponse(
                inks: [Wire.Ink(id: .free, name: "Graphite", light: "#2B2B2E", dark: "#ECEAE4", price: 0)],
                owned: [.free, InkId("ink-gold")]))
        #expect(state.inks.map(\.id) == ["ink-graphite"])
        #expect(state.owned == ["lamp", "ink-graphite", "ink-gold"])
    }

    @Test func anInkInsideItsUndoWindowSurvivesASync() {
        #expect(state.buy(PaletteInk.bundled[1]))
        state.apply(InksResponse(inks: [], owned: [.free]))
        state.apply(balance: 200)
        #expect(state.owned.contains("ink-rose"))
        #expect(state.coins == 140)
        #expect(state.inks == PaletteInk.bundled)
    }

    @Test func aStandingBuyReachesTheServerOnce() async throws {
        let sent = Mutex<[BuyRequest]>([])
        var api = APIClient.offline
        api.buyItem = { (request) async throws(TransportError) in
            sent.withLock { $0.append(request) }
            return BuyResponse(
                entry: CoinEntry(id: "buy:k", kind: .buy, amount: -60, ref: "ink-rose", at: 0), balance: 90,
                granted: [request.item], owned: [.free, request.item])
        }
        let purchase = try bought("ink-rose")
        await InkSync(api: api, undoWindow: .zero).settle(purchase, state)
        let requests = sent.withLock { $0 }
        #expect(requests.map(\.item) == [InkId("ink-rose")])
        #expect(requests.first?.id.rawValue.hasPrefix(purchase.id.uuidString) == true)
        #expect(state.coins == 90)
        #expect(state.owned.contains("ink-rose"))
    }

    @Test func anUndoneBuyNeverLeaves() async throws {
        let sent = Mutex(0)
        var api = APIClient.offline
        api.buyItem = { (_) async throws(TransportError) in
            sent.withLock { $0 += 1 }
            throw .network("unused")
        }
        let purchase = try bought("ink-rose")
        state.wallet.update { $0.undo(purchase) }
        await InkSync(api: api, undoWindow: .zero).settle(purchase, state)
        #expect(sent.withLock { $0 } == 0)
        #expect(state.coins == 200)
    }

    @Test func aRefusedBuyTakesTheServersWord() async throws {
        var api = APIClient.offline
        api.buyItem = { (_) async throws(TransportError) in throw .api(.notEnoughCoins(needed: 60, have: 20)) }
        api.listInks = { () async throws(TransportError) in InksResponse(inks: [], owned: [.free]) }
        api.getCoins = { () async throws(TransportError) in CoinsResponse(balance: 20, entries: []) }
        let purchase = try bought("ink-rose")
        await InkSync(api: api, undoWindow: .zero).settle(purchase, state)
        #expect(!state.owned.contains("ink-rose"))
        #expect(state.coins == 20)
    }
}
