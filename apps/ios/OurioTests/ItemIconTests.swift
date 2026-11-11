import MomentsInterface
import OurioShared
import Testing
import UIKit
import UsInterface
@testable import Billet

@Suite struct ItemIconTests {
    private let list = UsGlyph(symbol: "star.fill", tint: .sun)

    @Test(arguments: [
        ("Hot air balloon ride", "balloon.fill"),
        ("Blue Bottle Coffee", "cup.and.saucer.fill"),
        ("Sushi Nakazawa", "fish.fill"),
        ("See the northern lights", "moon.stars.fill"),
        ("Hiking in Patagonia", "mountain.2.fill"),
        ("A graphic novel", "bubble.left.and.bubble.right.fill"),
        ("Ice cream on the pier", "birthday.cake.fill"),
    ])
    func wordsPickTheirIcon(text: String, symbol: String) {
        #expect(ItemIcon.glyph(for: text, list: list).symbol == symbol)
    }

    @Test func aGroceryWordTakesItsAisle() {
        #expect(ItemIcon.glyph(for: "Bananas", list: list) == GroceryAisle.produce.icon)
    }

    @Test func anUnknownItemTakesTheListsIcon() {
        #expect(ItemIcon.glyph(for: "Learn Portuguese", list: list) == list)
        #expect(ItemIcon.glyph(for: "  ", list: list) == list)
    }

    @Test func everySymbolExists() {
        for symbol in ItemIcon.symbols {
            #expect(UIImage(systemName: symbol) != nil, "\(symbol)")
        }
    }
}
