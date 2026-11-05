import SwiftUI

/// One ink for the lock-screen drawing. `price` is in coins; zero is the free ink everyone has.
struct DrawInk: Identifiable, Hashable {
    let id: String
    let name: String
    let hex: UInt32
    let price: Int

    var color: Color { Color(hex: hex) }
    /// `#RRGGBB`, as strokes carry it.
    var wire: String { String(format: "#%06X", hex) }

    func isOwned(_ owned: Set<String>) -> Bool { price == 0 || owned.contains(id) }
}

/// The inks on sale. A local stand-in, shaped like billet-pay's ink catalog, until that contract lands and the
/// server sends the list.
enum DrawInks {
    static let free = DrawInk(id: "ink.violet", name: "Violet", hex: 0x7B4FE0, price: 0)

    static let all: [DrawInk] = [
        free,
        DrawInk(id: "ink.rose", name: "Rose", hex: 0xFF4F86, price: 60),
        DrawInk(id: "ink.honey", name: "Honey", hex: 0xF29A3B, price: 60),
        DrawInk(id: "ink.mint", name: "Mint", hex: 0x2FB98F, price: 80),
        DrawInk(id: "ink.sky", name: "Sky", hex: 0x3D8BF2, price: 80),
        DrawInk(id: "ink.cocoa", name: "Cocoa", hex: 0x5B3A28, price: 100),
        DrawInk(id: "ink.snow", name: "Snow", hex: 0xFFFFFF, price: 120),
    ]
}
