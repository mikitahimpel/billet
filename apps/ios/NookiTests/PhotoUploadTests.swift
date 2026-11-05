import Foundation
import Testing
import UIKit
@testable import Billet

struct PhotoUploadTests {
    private static func image(_ size: CGSize, color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: size, format: .init(for: .init(displayScale: 1))).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width / 3, height: size.height))
        }
    }

    @Test func aBlurHashHasTheLengthItsHeaderPromises() throws {
        let cg = try #require(Self.image(CGSize(width: 64, height: 48), color: .systemPink).cgImage)
        let hash = try #require(BlurHash.encode(cg))
        // 4 by 3 components: size flag "L", then 4 + 2 * 12 characters in all.
        #expect(hash.count == 28)
        #expect(hash.first == "L")
        let alphabet = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~")
        #expect(hash.allSatisfy(alphabet.contains))
    }

    @Test func aFlatColorHasNoDetail() throws {
        let flat = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        let cg = try #require(flat.cgImage)
        let hash = try #require(BlurHash.encode(cg))
        // Nothing but the average colour, so the quantised maximum of the detail is 0.
        #expect(hash.dropFirst().first == "0")
    }

    @Test func aBigPhotoGoesUpAsAJPEGOf2048OnTheLongSide() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let big = Self.image(CGSize(width: 3000, height: 1500), color: .systemTeal)
        let data = try #require(big.jpegData(compressionQuality: 0.9))
        try data.write(to: url)

        let upload = try #require(PhotoUpload(fileAt: url))
        #expect(upload.width == 2048)
        #expect(upload.height == 1024)
        #expect(upload.jpeg.starts(with: [0xFF, 0xD8, 0xFF]))
        #expect(upload.preview.count == 28)
    }
}
