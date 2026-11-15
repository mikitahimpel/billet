import Design
import SwiftUI
import Testing
@testable import Billet

/// Draw & guess offers three words, each after its tier's chip; the words start at one edge.
@MainActor @Suite(.serialized) struct DrawGuessWordsTests {
    @Test func theThreeWordsStartAtOneEdge() throws {
        let words = VStack(spacing: Space.m) {
            WordOption(tier: "Easy", word: "clock")
            WordOption(tier: "Medium", word: "earrings")
            WordOption(tier: "Hard", word: "fishing")
        }
        .padding(Space.l)
        let layout = HostedLayout(words, phone: .se)
        layout.settle(0.5)
        let easy = try #require(layout.element(label: "clock")).frame
        let medium = try #require(layout.element(label: "earrings")).frame
        let hard = try #require(layout.element(label: "fishing")).frame
        #expect(abs(easy.minX - medium.minX) < 1, "clock at \(easy.minX), earrings at \(medium.minX)")
        #expect(abs(hard.minX - medium.minX) < 1, "fishing at \(hard.minX), earrings at \(medium.minX)")
    }
}
