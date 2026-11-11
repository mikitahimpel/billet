import Testing
import UIKit
@testable import Billet

@MainActor
@Suite struct ThumbnailsTests {
    @Test(arguments: Catalog.items.map(\.thumbnail))
    func everyCatalogItemHasADecodableBundledPicture(name: String) {
        #expect(Thumbnails.image(name, maxPixels: 128) != nil)
    }
}
