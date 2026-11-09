import CoreImage
import Testing
import UIKit

struct SamplePNGTests {
    @Test func anImageWithoutItsOwnBitmapStillEncodes() throws {
        let pixels = CIImage(color: CIColor(red: 0.5, green: 0.2, blue: 0.9)).cropped(
            to: CGRect(x: 0, y: 0, width: 40, height: 20))
        let image = UIImage(ciImage: pixels, scale: 2, orientation: .up)
        #expect(image.cgImage == nil)

        let png = try #require(SamplePNG.encode(image))
        let decoded = try #require(UIImage(data: png)?.cgImage)
        #expect(decoded.width == 40)
        #expect(decoded.height == 20)
    }

    @Test func anEmptyImageHasNoPNG() {
        #expect(SamplePNG.encode(UIImage()) == nil)
    }
}
