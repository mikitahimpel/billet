import Foundation
import Testing
import Transport
import Wire
@testable import Billet

@MainActor
@Suite struct ShopModelTests {
    private let walletFile = "Tests/\(UUID().uuidString)-wallet.json"

    private func shop(coins: Int) -> (ShopModel, WalletStore) {
        let wallet = WalletStore(file: walletFile)
        wallet.update { $0 = Wallet(coins: coins) }
        let care = CatCare(wallet: wallet, streak: StreakStore(file: "Tests/\(UUID().uuidString)-streak.json"))
        return (ShopModel(wallet: wallet, couple: CoupleStore(), care: care), wallet)
    }

    private func room(_ balance: Int, items: [String]) -> ShopResponse {
        ShopResponse(balance: balance, inks: [], items: items.map(RoomItemId.init), wishlist: [])
    }

    private func cleanUp() {
        SharedFile.flush()
        for file in [walletFile, walletFile.replacingOccurrences(of: ".json", with: ".local.json")] {
            try? FileManager.default.removeItem(at: SharedFile.url(file))
        }
    }

    @Test func aSyncedWalletMirrorsTheRoomAndLeavingGivesThePhonesOwnBack() async {
        defer { cleanUp() }
        let (model, wallet) = shop(coins: 70)
        let server = room(400, items: ["lamp", "rug", "tower"])
        await model.connect(ShopSync(fetch: { server }, order: { _ in throw .status(500) }, wish: { _ in server }))
        #expect(model.isSynced)
        #expect(model.coins == 400)
        #expect(model.owned == ["lamp", "rug", "tower"])

        wallet.earn(25)
        #expect(model.coins == 400)

        await model.connect(nil)
        #expect(!model.isSynced)
        #expect(model.coins == 70)
    }

    @Test func aBuyTheRoomRefusesIsTakenBack() async throws {
        defer { cleanUp() }
        let (model, _) = shop(coins: 0)
        let server = room(100, items: ["lamp", "rug"])
        await model.connect(ShopSync(fetch: { server }, order: { _ in throw .status(409) }, wish: { _ in server }))
        let yarn = try #require(Catalog.item("yarn"))

        #expect(model.buy(yarn))
        #expect(model.owned.contains("yarn"))
        for _ in 0..<100 where model.owned.contains("yarn") { await Task.yield() }
        #expect(!model.owned.contains("yarn"))
        #expect(model.coins == 100)
    }
}
