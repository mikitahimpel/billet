import Design
import SwiftUI
import Testing
@testable import Billet

/// The composer's stamp and seal tray at the largest text: its words and prices stop growing at the largest regular
/// size, so the prices under the 44-point buttons don't run into each other. Measured off-screen, without a window.
@MainActor @Suite struct PostageTrayTests {
    private func size(_ dynamicType: DynamicTypeSize) throws -> CGSize {
        let tray = PostageTray(stamp: .constant(nil), seal: .constant(nil), owned: []) { _, _ in }
            .environment(\.dynamicTypeSize, dynamicType)
        let image = try #require(ImageRenderer(content: tray).uiImage, "the tray didn't render")
        return image.size
    }

    @Test func theLargestTextStopsAtTheLargestRegularSize() throws {
        let largest = try size(.accessibility5)
        // Three columns at every accessibility size; without the cap the largest would be far bigger than the first.
        let first = try size(.accessibility1)
        #expect(abs(largest.height - first.height) < 1, "\(largest.height) tall at the largest text, \(first.height) at the first")
        #expect(abs(largest.width - first.width) < 1, "\(largest.width) wide at the largest text, \(first.width) at the first")
        #expect(largest.width <= HostedLayout.Phone.se.size.width, "the tray fits the SE")
    }
}
