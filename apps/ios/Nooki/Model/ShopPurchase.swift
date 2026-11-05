import Foundation

/// One buy in the Shop, kept for the purchase moment and its Undo.
struct Purchase: Identifiable, Hashable {
    let id = UUID()
    /// What the couple bought: one item, or a set's pieces.
    let itemIDs: [String]
    /// The pieces this buy added; pieces owned before stay owned on Undo.
    let added: [String]
    let cost: Int
    let date: Date
    var title: String
    var kind = Kind.item

    enum Kind: Hashable {
        /// Room pieces, kept on the phone.
        case item
        /// An ink colour for notes and drawings; the server takes the coins once Undo has passed.
        case ink
    }

    static let undoWindow: TimeInterval = 5

    func canUndo(at now: Date) -> Bool { now.timeIntervalSince(date) < Self.undoWindow }
}

extension Wallet {
    /// Takes the cost and adds the pieces not owned yet. Nil, and nothing changes, when the coins don't cover it or
    /// every piece is owned already.
    mutating func buy(
        _ itemIDs: [String], cost: Int, title: String, kind: Purchase.Kind = .item, giftTo: Bool = false, at date: Date
    ) -> Purchase? {
        let added = itemIDs.filter { !owned.contains($0) }
        guard coins >= cost, !added.isEmpty else { return nil }
        coins -= cost
        owned.formUnion(added)
        wishlist.subtract(added)
        if giftTo { gifted.formUnion(added) }
        return Purchase(itemIDs: itemIDs, added: added, cost: cost, date: date, title: title, kind: kind)
    }

    /// Gives the coins back and takes back only what that buy added.
    mutating func undo(_ purchase: Purchase) {
        coins += purchase.cost
        owned.subtract(purchase.added)
        gifted.subtract(purchase.added)
    }
}
