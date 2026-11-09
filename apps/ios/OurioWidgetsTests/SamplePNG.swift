import UIKit

/// A rendered sample as PNG data. `UIImage.pngData()` is nil for an image with no bitmap of its own behind it, which
/// `ImageRenderer` sometimes hands back on CI; drawing it into an opaque sRGB bitmap first always gives one.
enum SamplePNG {
    /// Nil only for an empty image.
    static func encode(_ image: UIImage) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        // The image's own scale, so the samples keep their pixels.
        format.scale = image.scale
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: image.size, format: format).pngData { _ in image.draw(at: .zero) }
    }
}
