import MomentsInterface
import WidgetInterface
import WidgetUI
import UIKit
import UsInterface

/// Item tiles are WebP (512 px, props) or PNG (1024 px) with generous transparent margins: each place decodes them at the size it draws,
/// and the hero fan also fades their shadows' cut edges and crops them to the artwork before aligning the pieces on the card's
/// bottom edge.
@MainActor
enum Thumbnails {
    /// NSCache is safe from any thread; `prefetch` fills it off the main one.
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    static func image(_ name: String, maxPixels: Int) -> UIImage? {
        if let cached = cache.object(forKey: key(name, maxPixels)) { return cached }
        guard let image = decode(name, maxPixels: maxPixels) else { return nil }
        cache.setObject(image, forKey: key(name, maxPixels))
        return image
    }

    /// Decodes `names` at `maxPixels` away from the main thread, so the views that draw them later find them ready
    /// instead of decoding each in the middle of a scroll.
    nonisolated static func prefetch(_ names: [String], maxPixels: Int) async {
        await Task.detached(priority: .userInitiated) {
            for name in names where cache.object(forKey: key(name, maxPixels)) == nil {
                if Task.isCancelled { return }
                if let image = decode(name, maxPixels: maxPixels) { cache.setObject(image, forKey: key(name, maxPixels)) }
            }
        }.value
    }

    private nonisolated static func key(_ name: String, _ maxPixels: Int) -> NSString {
        "\(name)@\(maxPixels)" as NSString
    }

    private nonisolated static func decode(_ name: String, maxPixels: Int) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "webp")
            ?? Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return Downsample.image(at: url, maxPixels: maxPixels)
    }

    /// Fan pieces are at most 88 pt, so the 512 px card decode leaves enough after the crop.
    static func trimmed(_ name: String) -> UIImage? {
        if let cached = cache.object(forKey: trimmedKey(name)) { return cached }
        guard let image = Self.image(name, maxPixels: 512) else { return nil }
        return trim(image, name)
    }

    /// `trimmed` for each of `names`, away from the main thread.
    nonisolated static func prefetchTrimmed(_ names: [String]) async {
        await prefetch(names, maxPixels: 512)
        await Task.detached(priority: .userInitiated) {
            for name in names where cache.object(forKey: trimmedKey(name)) == nil {
                if Task.isCancelled { return }
                if let image = cache.object(forKey: key(name, 512)) { trim(image, name) }
            }
        }.value
    }

    private nonisolated static func trimmedKey(_ name: String) -> NSString { "\(name)/trimmed" as NSString }

    @discardableResult
    private nonisolated static func trim(_ image: UIImage, _ name: String) -> UIImage {
        let clean = image.fadingShadowEdges() ?? image
        let result = clean.trimmingTransparentEdges() ?? clean
        cache.setObject(result, forKey: trimmedKey(name))
        return result
    }
}

private extension UIImage {
    /// The renders carry a noisy contact shadow from a ground plane that runs off the square, so on a coloured card
    /// its cut edges read as a box. Shadow pixels (alpha below `solid`) fade to nothing over the outer `band` of the
    /// square and the faintest grain goes; the piece itself, opaque, is left as it is.
    nonisolated func fadingShadowEdges() -> UIImage? {
        guard let cgImage else { return nil }
        let width = cgImage.width, height = cgImage.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let solid: UInt8 = 200, grain: UInt8 = 14
        let band = Double(min(width, height)) * 0.18
        for y in 0..<height {
            let edgeY = Double(min(y, height - 1 - y))
            for x in 0..<width {
                let i = (y * width + x) * 4
                let alpha = pixels[i + 3]
                guard alpha < solid else { continue }
                let edge = min(1, min(Double(min(x, width - 1 - x)), edgeY) / band)
                let keep = alpha < grain ? 0 : edge * edge * (3 - 2 * edge)
                guard keep < 1 else { continue }
                // Premultiplied, so colour and alpha scale together.
                for c in 0..<4 { pixels[i + c] = UInt8(Double(pixels[i + c]) * keep) }
            }
        }
        guard let faded = context.makeImage() else { return nil }
        return UIImage(cgImage: faded, scale: scale, orientation: .up)
    }

    nonisolated func trimmingTransparentEdges() -> UIImage? {
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
