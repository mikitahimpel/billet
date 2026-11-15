import Design
import SwiftUI
import Testing
@testable import Billet

/// The composer's stamp and seal tray at the largest text: its words and prices stop growing at the largest regular
/// size, so the prices under the 44-point buttons don't run into each other.
@MainActor @Suite(.serialized) struct PostageTrayTests {
    private func tray(_ dynamicType: DynamicTypeSize) throws -> (header: CGRect, tray: CGRect, window: CGRect) {
        let view = PostageTray(stamp: .constant(nil), seal: .constant(nil), owned: []) { _, _ in }
        var phone = HostedLayout.Phone.se
        phone.dynamicType = dynamicType
        let layout = HostedLayout(view, phone: phone)
        layout.settle(0.5)
        let header = try #require(layout.element(label: "Stamp"), "no Stamp header").frame
        let tray = try #require(layout.element(id: "postageTray"), "no tray").frame
        return (header, tray, layout.bounds)
    }

    @Test func theLargestTextStopsAtTheLargestRegularSize() throws {
        let largest = try tray(.accessibility5)
        let capped = try tray(.xxxLarge)
        #expect(abs(largest.header.height - capped.header.height) < 1,
                "the header is \(largest.header.height) tall at the largest text, \(capped.header.height) capped")
        #expect(largest.tray.maxX <= largest.window.maxX + 1, "the tray fits the SE")
    }
}
