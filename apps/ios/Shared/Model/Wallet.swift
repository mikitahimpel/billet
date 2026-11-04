import Foundation
import Observation

/// What both partners share in the shop: coins, Mochi's level and the items they own, wish for or gifted.
nonisolated struct Wallet: Codable, Hashable {
    var coins = 560
    var level = 5
    var progress = 0.62
    var owned: Set<String> = ["lamp", "rug"]
    var wishlist: Set<String> = ["tower"]
    var gifted: Set<String> = []
    /// Ticked "we want to" items that earned coins on `listCoinsDay`.
    var listCoinsDay = Date.distantPast
    var listCoinsCount = 0

    static let listCoins = 5
    static let listCoinsPerDay = 3

    /// Ticking a "we want to" item earns 5 coins, at most 3 times a day.
    mutating func tickList(on date: Date = .now) {
        let day = Calendar.current.startOfDay(for: date)
        if listCoinsDay != day { (listCoinsDay, listCoinsCount) = (day, 0) }
        guard listCoinsCount < Self.listCoinsPerDay else { return }
        listCoinsCount += 1
        coins += Self.listCoins
    }
}

/// The shared wallet in the app group, so widget intents can earn coins too.
@Observable
final class WalletStore {
    private(set) var wallet: Wallet

    private let file: String

    init(file: String = "Shop/wallet.json") {
        self.file = file
        wallet = SharedFile.read(Wallet.self, from: file) ?? Wallet()
    }

    func reload() {
        if let saved = SharedFile.read(Wallet.self, from: file) { wallet = saved }
    }

    func update(_ change: (inout Wallet) -> Void) {
        change(&wallet)
        SharedFile.write(wallet, to: file)
    }

    func earn(_ coins: Int) {
        update { $0.coins += coins }
    }
}
