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

    @Test func aTrimmedPictureHasNoHalfTransparentPixelOnItsEdge() throws {
        for id in ["teatable", "monstera", "lantern"] {
            let image = try #require(Thumbnails.trimmed("Item_\(id)"))
            let cgImage = try #require(image.cgImage)
            let width = cgImage.width, height = cgImage.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = try #require(CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            for y in 0..<height {
                for x in 0..<width where x == 0 || y == 0 || x == width - 1 || y == height - 1 {
                    let alpha = pixels[(y * width + x) * 4 + 3]
                    #expect(alpha == 0 || alpha >= 200, "\(id) edge pixel \(x),\(y) has alpha \(alpha)")
                }
            }
        }
    }
}
