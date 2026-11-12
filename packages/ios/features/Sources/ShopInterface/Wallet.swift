import Foundation
import Observation
import Persistence

/// As this phone last heard it from the server. Only the server changes the coins; the phone keeps its last answer
/// for the widgets and for offline.
public nonisolated struct Wallet: Codable, Hashable, Sendable {
  public var coins = 0
  public var level = 1
  public var progress = 0.0
  /// The starter pieces every room has, as the server's `starterItems`.
  public var owned: Set<String> = ["lamp", "rug"]
  public var wishlist: Set<String> = []
  public var gifted: Set<String> = []

  /// True once synced from the pair's room. Optional so files saved before it still decode.
  public var synced: Bool?

  public init(
    coins: Int = 0, level: Int = 1, progress: Double = 0.0, owned: Set<String> = ["lamp", "rug"],
    wishlist: Set<String> = [], gifted: Set<String> = [], synced: Bool? = nil
  ) {
    self.coins = coins
    self.level = level
    self.progress = progress
    self.owned = owned
    self.wishlist = wishlist
    self.gifted = gifted
    self.synced = synced
  }

  public var isSynced: Bool { synced == true }
}

/// In the app group, so the widgets read the same one.
@Observable
@MainActor
public final class WalletStore {
  public private(set) var wallet: Wallet

  private let file: String

  public init(file: String = "Shop/wallet.json") {
    self.file = file
    wallet = SharedFile.read(Wallet.self, from: file) ?? Wallet()
  }

  public func reload() {
    if let saved = SharedFile.read(Wallet.self, from: file) { wallet = saved }
  }

  public func update(_ change: (inout Wallet) -> Void) {
    change(&wallet)
    SharedFile.write(wallet, to: file)
  }

  /// Takes the pair's room on the server as the truth.
  public func mirror(coins: Int, owned: Set<String>, wishlist: Set<String>) {
    update {
      $0.coins = coins
      $0.owned = owned
      $0.wishlist = wishlist
      $0.synced = true
    }
  }

  /// The server's balance, as an earn or a wallet read answers it.
  public func mirror(balance: Int) {
    update {
      $0.coins = balance
      $0.synced = true
    }
  }

  /// The pair ended: what it had was the room's, so none of it stays, even when the room's answer hadn't reached the
  /// file yet. Mochi's level stays where care left it.
  public func leaveSync() {
    update { $0 = Wallet(level: $0.level, progress: $0.progress) }
  }
}
