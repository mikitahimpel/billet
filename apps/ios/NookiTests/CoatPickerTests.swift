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

    /// The stage cuts every portrait to the cat with the same numbers (ears at 5%, paws at 94.75% of the height), so
    /// every coat must be framed alike at any pixel size: 3:4, same paw line, centred, and no ear above the cut.
    /// Ear tips differ by coat: some are rounder and sit up to 2.5% lower.
    @Test(arguments: CatCoat.allCases)
    func everyPortraitIsFramedLikeTheStageExpects(coat: CatCoat) throws {
        let image = try #require(UIImage(named: coat.portrait))
        let cg = try #require(image.cgImage)
        #expect(cg.width * 4 == cg.height * 3)
        let box = try Self.bounds(of: image)
        let height = Double(cg.height), width = Double(cg.width)
        #expect((0.045...0.08).contains(Double(box.top) / height), "ears at \(Double(box.top) / height)")
        #expect(abs(Double(box.bottom + 1) / height - 0.9475) < 0.01, "paws at \(Double(box.bottom + 1) / height)")
        #expect(abs(Double(box.left + box.right) / 2 / width - 0.5) < 0.03, "centred at \(Double(box.left + box.right) / 2 / width)")
    }

    @Test
    func everyChipHasItsOwnColours() {
        let bases = CatCoat.allCases.map { UIColor($0.swatch.base).cgColor.components ?? [] }
        #expect(Set(bases.map { $0.map { Int(($0 * 255).rounded()) } }).count == CatCoat.allCases.count)
        // The patterned coats show their markings.
        for coat in [CatCoat.grey, .ginger, .cream, .tuxedo, .calico] { #expect(!coat.swatch.marks.isEmpty) }
    }
}
