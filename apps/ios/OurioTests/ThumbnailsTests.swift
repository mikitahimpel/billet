import Testing
import UIKit
@testable import Billet

@MainActor
@Suite struct ThumbnailsTests {
    @Test func everyCatalogItemHasADecodableBundledPicture() {
        for item in Catalog.items {
            #expect(Thumbnails.image(item.thumbnail, maxPixels: 128) != nil, "\(item.thumbnail)")
        }
    }
}
