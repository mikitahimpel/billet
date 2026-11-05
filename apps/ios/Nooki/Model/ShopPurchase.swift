import Foundation
import Wire

/// One buy in the Shop, shown on the phone from the tap until the server answers: the purchase moment plays for it,
/// it offers Undo for a few seconds, and only then is it ordered.
struct Purchase: Identifiable, Hashable {
    /// Made once per tap; its string is the order's idempotency key on every retry.
    let id: UUID
    let offer: ShopOffer
    /// What the couple bought: one item, or a set's pieces.
    let itemIDs: [String]
    /// The pieces this buy adds; pieces owned before stay owned when it is undone or refused.
    let added: [String]
    /// The price shown; the server charges its own.
    let cost: Int
    let date: Date
    var title: String
    var kind = Kind.item
    /// Bought for the partner: it arrives wrapped and they unwrap it.
    var asGift = false

    init(
        id: UUID = UUID(), offer: ShopOffer, itemIDs: [String], added: [String], cost: Int, date: Date, title: String,
        kind: Kind = .item, asGift: Bool = false
    ) {
        self.id = id
        self.offer = offer
        self.itemIDs = itemIDs
        self.added = added
        self.cost = cost
        self.date = date
        self.title = title
        self.kind = kind
        self.asGift = asGift
    }

    enum Kind: Hashable {
        /// Room pieces.
        case item
        /// An ink colour for notes and drawings.
        case ink
        /// A treat for the cat: no purchase moment and no Undo.
        case treat
    }

    static let undoWindow: TimeInterval = 5

    var key: IdempotencyKey { IdempotencyKey(id.uuidString) }

    func canUndo(at now: Date) -> Bool { kind != .treat && now.timeIntervalSince(date) < Self.undoWindow }
}

/// Why the Coins sheet is open: `missing` is what a buy needed beyond the balance, 0 when the header's coins opened
/// it, and `retry` is that buy, to finish in one tap once the coins are there.
struct CoinsAsk: Identifiable, Hashable {
    let id = UUID()
    let missing: Int
    let retry: Retry?

    struct Retry: Hashable {
        let offer: ShopOffer
        let itemIDs: [String]
        let cost: Int
        let title: String
        var kind = Purchase.Kind.item
        var asGift = false
    }
}

extension CoinsAsk.Retry {
    init(_ purchase: Purchase) {
        self.init(
            offer: purchase.offer, itemIDs: purchase.itemIDs, cost: purchase.cost, title: purchase.title,
            kind: purchase.kind, asGift: purchase.asGift)
    }
}
