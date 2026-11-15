import SwiftUI
import Testing
@testable import Billet

@Suite struct DecorPanelTests {
    @Test func theClosetShowsThreeTilesAndTwoAtTheAccessibilitySizes() {
        #expect(DecorPanel.closetColumns(at: .large) == 3)
        #expect(DecorPanel.closetColumns(at: .xxxLarge) == 3)
        #expect(DecorPanel.closetColumns(at: .accessibility1) == 2)
        #expect(DecorPanel.closetColumns(at: .accessibility5) == 2)
    }
}
