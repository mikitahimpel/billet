import Foundation
import Wire

/// What the Coins sheet says when an App Store refund took back coins the pair had already spent, so the balance
/// is below 0. Spending waits until earning has covered it; nothing else is taken back.
struct CoinDebt: Equatable {
  /// What new coins must cover first.
  let owed: Int
  /// What the latest refund took back, or `owed` while the history hasn't been read.
  let refunded: Int

  /// Nil unless the balance is below 0. `history` is newest first.
  init?(balance: Int, history: [CoinEntry]) {
    guard balance < 0 else { return nil }
    owed = -balance
    let latest = history.first { $0.kind == .refund && $0.amount < 0 }
    refunded = latest.map { -$0.amount } ?? -balance
  }

  var title: String { "A refund took back \(refunded) coins" }

  var detail: String {
    "New coins you earn cover it first, then you can spend again. Nothing else is taken back, and coins never expire."
  }

  /// Under the balance.
  var caption: String { "to cover before you can spend again" }
}
