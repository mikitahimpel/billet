import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import Testing
import UIKit
import UsInterface
@testable import Billet

struct PolaroidTests {
    @Test func everyPrintLeansTwoToFourDegreesTheSameWayEachTime() {
        for _ in 0..<200 {
            let id = UUID()
            let tilt = abs(id.polaroidTilt.degrees)
            #expect(tilt >= 2 && tilt <= 4)
            #expect(id.polaroidTilt == id.polaroidTilt)
        }
    }

    @Test func theFilmGradeKeepsThePhotoSizeAndLiftsItsBlacks() throws {
        let size = CGSize(width: 64, height: 48)
        let black = UIGraphicsImageRenderer(size: size, format: .init(for: .init(displayScale: 1))).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let graded = try #require(InstantFilm.develop(black))
        #expect(graded.size == black.size)

        let center = try #require(pixel(of: graded, at: CGPoint(x: 32, y: 24)))
        #expect(center.red > 0.03, "black should come out a warm brown, not black")
        #expect(center.red > center.blue)
    }

    @Test func aBylineIsWhoAndWhen() {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!
        let moment = Moment(id: UUID(), author: "M", date: date, caption: "", file: "a.jpg", pinned: false, loved: false)
        #expect(moment.byline(by: "Anya").hasPrefix("Anya · "))
        #expect(moment.byline(by: "Anya").contains("5"))
    }

    private func pixel(of image: UIImage, at point: CGPoint) -> (red: Double, blue: Double)? {
        guard let cg = image.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: -point.x, y: -point.y, width: CGFloat(cg.width), height: CGFloat(cg.height)))
            return true
        }
        return drawn ? (Double(bytes[0]) / 255, Double(bytes[2]) / 255) : nil
    }
}
