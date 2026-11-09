import Foundation
import Observation

/// As this phone last heard it from the server. Only the server changes the coins; the phone keeps its last answer
/// for the widgets and for offline.
nonisolated struct Wallet: Codable, Hashable {
    var coins = 0
    var level = 1
    var progress = 0.0
    /// The starter pieces every room has, as the server's `starterItems`.
    var owned: Set<String> = ["lamp", "rug"]
    var wishlist: Set<String> = []
    var gifted: Set<String> = []

    /// True once synced from the pair's room. Optional so files saved before it still decode.
    var synced: Bool?

    var isSynced: Bool { synced == true }
}

/// In the app group, so the widgets read the same one.
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

    /// Takes the pair's room on the server as the truth.
    func mirror(coins: Int, owned: Set<String>, wishlist: Set<String>) {
        update {
            $0.coins = coins
            $0.owned = owned
            $0.wishlist = wishlist
            $0.synced = true
        }
    }

    /// The server's balance, as an earn or a wallet read answers it.
    func mirror(balance: Int) {
        update {
            $0.coins = balance
            $0.synced = true
        }
    }

    /// The pair ended: what it had was the room's, so none of it stays, even when the room's answer hadn't reached the
    /// file yet. Mochi's level stays where care left it.
    func leaveSync() {
        update { $0 = Wallet(level: $0.level, progress: $0.progress) }
    }
}
