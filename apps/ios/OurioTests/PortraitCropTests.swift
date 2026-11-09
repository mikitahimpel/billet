import OurioShared
import Testing
import UIKit
@testable import Billet

/// An avatar's square: whole, inside the photo, and high on a tall photo, where heads are.
@MainActor @Suite struct PortraitCropTests {
    private func blank(_ width: CGFloat, _ height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func aTallPhotoWithoutAFaceKeepsItsUpperPart() {
        let crop = CoupleStore.portraitSquare(in: blank(600, 1200))
        #expect(crop.width == 600 && crop.height == 600)
        #expect(crop.minX == 0)
        #expect(crop.minY == 120, "a fifth of the spare height above, not half")
    }

    @Test func aWidePhotoWithoutAFaceIsCentred() {
        let crop = CoupleStore.portraitSquare(in: blank(1200, 600))
        #expect(crop == CGRect(x: 300, y: 0, width: 600, height: 600))
    }

    @Test func theSquareStaysInsideThePhoto() {
        for size in [CGSize(width: 400, height: 401), CGSize(width: 1000, height: 3000), CGSize(width: 512, height: 512)] {
            let crop = CoupleStore.portraitSquare(in: blank(size.width, size.height))
            #expect(CGRect(origin: .zero, size: size).contains(crop))
        }
    }
}
