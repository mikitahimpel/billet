import Foundation
import Observation

/// What both partners share in the shop: coins, Mochi's level and the items they own, wish for or gifted.
nonisolated struct Wallet: Codable, Hashable {
    var coins = 0
    var level = 1
    var progress = 0.0
    /// The starter pieces every room has, as the server's `starterItems`.
    var owned: Set<String> = ["lamp", "rug"]
    var wishlist: Set<String> = []
    var gifted: Set<String> = []
    /// Ticked "we want to" items that earned coins on `listCoinsDay`.
    var listCoinsDay = Date.distantPast
    var listCoinsCount = 0

    /// True while the coins, owned pieces and wishlist mirror the pair's room on the server. Nothing on the phone
    /// earns coins then: only the server does. Optional, so a file saved before it existed still decodes.
    var synced: Bool?

    var isSynced: Bool { synced == true }

    static let listCoins = 5
    static let listCoinsPerDay = 3

    /// Ticking a "we want to" item earns 5 coins, at most 3 times a day.
    mutating func tickList(on date: Date = .now) {
        guard !isSynced else { return }
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

    /// Coins earned on this phone. None while the wallet mirrors the server, which pays for the same things itself.
    func earn(_ coins: Int) {
        guard !wallet.isSynced else { return }
        update { $0.coins += coins }
    }

    /// Where the phone's own wallet waits while this one mirrors the server.
    private var asideFile: String { file.replacingOccurrences(of: ".json", with: ".local.json") }

    /// Takes the pair's room on the server as the truth. The first time, the phone's own wallet is set aside, so a
    /// phone that leaves the pair gets it back.
    func mirror(coins: Int, owned: Set<String>, wishlist: Set<String>) {
        if !wallet.isSynced { SharedFile.write(wallet, to: asideFile) }
        update {
            $0.coins = coins
            $0.owned = owned
            $0.wishlist = wishlist
            $0.synced = true
        }
    }

    /// Back to the phone's own wallet as it was before the first mirror. Mochi's level stays where care left it.
    func leaveSync() {
        guard wallet.isSynced else { return }
        var own = SharedFile.read(Wallet.self, from: asideFile) ?? Wallet()
        own.level = wallet.level
        own.progress = wallet.progress
        own.synced = nil
        wallet = own
        SharedFile.write(wallet, to: file)
    }
}
