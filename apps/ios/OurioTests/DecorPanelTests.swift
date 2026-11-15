import SwiftUI
import Testing
@testable import Billet

@Suite struct DecorPanelTests {
    @Test func theClosetIsTwoEqualColumnsAndOneAtTheAccessibilitySizes() {
        #expect(DecorPanel.closetColumns(at: .large) == 2)
        #expect(DecorPanel.closetColumns(at: .xxxLarge) == 2)
        #expect(DecorPanel.closetColumns(at: .accessibility1) == 1)
        #expect(DecorPanel.closetColumns(at: .accessibility5) == 1)
    }
}
