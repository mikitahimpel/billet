import UIKit

/// Item PNGs are 1024 px with generous transparent margins: each place decodes them at the size it draws,
/// and the hero fan also crops them to the artwork before aligning the pieces on the card's bottom edge.
@MainActor
enum Thumbnails {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ name: String, maxPixels: Int) -> UIImage? {
        let key = "\(name)@\(maxPixels)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = Downsample.image(at: url, maxPixels: maxPixels) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Fan pieces are at most 88 pt, so the 512 px card decode leaves enough after the crop.
    static func trimmed(_ name: String) -> UIImage? {
        let key = "\(name)/trimmed" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = Self.image(name, maxPixels: 512) else { return nil }
        let result = image.trimmingTransparentEdges() ?? image
        cache.setObject(result, forKey: key)
        return result
    }
}

private extension UIImage {
    func trimmingTransparentEdges() -> UIImage? {
        guard let cgImage, cgImage.bitsPerPixel == 32,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }

        let alpha = cgImage.alphaInfo
        guard alpha == .premultipliedLast || alpha == .last ||
              alpha == .premultipliedFirst || alpha == .first else { return nil }

        // ImageIO thumbnails usually come back BGRA (alpha first, little endian), which puts alpha in the last byte.
        let alphaFirst = alpha == .premultipliedFirst || alpha == .first
        let alphaOffset = alphaFirst != (cgImage.byteOrderInfo == .order32Little) ? 0 : 3
        let width = cgImage.width
        let height = cgImage.height
        let row = cgImage.bytesPerRow
        var minX = width, minY = height, maxX = -1, maxY = -1

        for y in stride(from: 0, to: height, by: 2) {
            let line = y * row
            for x in stride(from: 0, to: width, by: 2) where bytes[line + x * 4 + alphaOffset] > 12 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
    }
}
