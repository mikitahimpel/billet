import SwiftUI
import Testing
import UIKit
@testable import Billet

struct CoatPickerTests {
    /// The rows and columns of the image where the cat is (alpha above about 10%).
    private static func bounds(of image: UIImage) throws -> (top: Int, bottom: Int, left: Int, right: Int) {
        let cg = try #require(image.cgImage)
        let width = cg.width, height = cg.height
        var alpha = [UInt8](repeating: 0, count: width * height)
        let context = try #require(CGContext(data: &alpha, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                              bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var top = height, bottom = -1, left = width, right = -1
        for y in 0..<height {
            for x in 0..<width where alpha[y * width + x] > 24 {
                top = min(top, y); bottom = max(bottom, y); left = min(left, x); right = max(right, x)
            }
        }
        return (top, bottom, left, right)
    }

    /// The stage cuts every portrait to the cat with the same numbers (ears at 167, paws at 1431 of 1600), so every
    /// coat must be framed alike: same size, same scale, same eye line.
    @Test(arguments: CatCoat.allCases)
    func everyPortraitIsFramedLikeTheStageExpects(coat: CatCoat) throws {
        let image = try #require(UIImage(named: coat.portrait))
        #expect(image.size.width * image.scale == 1200)
        #expect(image.size.height * image.scale == 1600)
        let box = try Self.bounds(of: image)
        #expect(abs(box.top - 167) <= 12, "ears at \(box.top)")
        #expect(abs(box.bottom - 1431) <= 8, "paws at \(box.bottom)")
        #expect(abs((box.left + box.right) / 2 - 592) <= 40, "centred at \((box.left + box.right) / 2)")
    }

    @Test
    func everyChipHasItsOwnColours() {
        let bases = CatCoat.allCases.map { UIColor($0.swatch.base).cgColor.components ?? [] }
        #expect(Set(bases.map { $0.map { Int(($0 * 255).rounded()) } }).count == CatCoat.allCases.count)
        // The patterned coats show their markings.
        for coat in [CatCoat.grey, .ginger, .cream, .tuxedo, .calico] { #expect(!coat.swatch.marks.isEmpty) }
    }
}
