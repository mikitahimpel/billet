import MomentsInterface
import ServerSync
import UIKit

nonisolated extension PhotoUpload {
    static let longSide = 2048
    static let quality: CGFloat = 0.8

    init?(fileAt url: URL) {
        guard let image = Downsample.image(at: url, maxPixels: Self.longSide) else { return nil }
        self.init(image)
    }

    init?(_ image: UIImage) {
        guard let cg = image.cgImage, let jpeg = image.jpegData(compressionQuality: Self.quality),
              let preview = BlurHash.encode(cg) else { return nil }
        self.init(jpeg: jpeg, width: cg.width, height: cg.height, preview: preview)
    }
}
