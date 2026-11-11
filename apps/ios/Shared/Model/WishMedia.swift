import LinkPresentation
import Persistence
import UIKit
import UniformTypeIdentifiers

/// A wish's picture, a small JPEG next to the Us store in the app group, so the share extension can save one too.
public enum WishImage {
    private static func url(_ id: UUID) -> URL { SharedFile.url("Us/Wishes/\(id.uuidString).jpg") }

    public static func load(_ id: UUID) -> UIImage? { UIImage(contentsOfFile: url(id).path()) }

    nonisolated(unsafe) private static let thumbnails = NSCache<NSString, UIImage>()

    /// Decoded off the main thread at the size a card draws it, and kept until the picture changes.
    public static func thumbnail(_ id: UUID, maxPixels: Int) async -> UIImage? {
        let key = "\(id.uuidString)@\(maxPixels)" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let path = url(id)
        let image = await Task.detached(priority: .userInitiated) {
            Downsample.image(at: path, maxPixels: maxPixels)
        }.value
        if let image { thumbnails.setObject(image, forKey: key) }
        return image
    }

    private static func forget(_ id: UUID) {
        thumbnails.removeObject(forKey: "\(id.uuidString)@\(WishThumbnail.pixels)" as NSString)
    }

    public static func save(_ data: Data, for id: UUID) {
        let target = url(id)
        let folder = target.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: target, options: .atomic)
        forget(id)
    }

    public static func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(id))
        forget(id)
    }
}

public enum WishThumbnail {
    /// A card draws the picture at 64 pt.
    public static let pixels = 192
}

public enum LinkPreview {
    public struct Result {
        public var title: String?
        /// JPEG, at most 600 points on its longer side.
        public var image: Data?

        public init(title: String? = nil, image: Data? = nil) {
            self.title = title
            self.image = image
        }
    }

    /// Nil when the page can't be reached within 8 seconds.
    public static func fetch(_ url: URL) async -> Result? {
        let provider = LPMetadataProvider()
        provider.timeout = 8
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return nil }
        var result = Result(title: metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines))
        if let item = metadata.imageProvider,
           let data = await imageData(item),
           let full = UIImage(data: data),
           let small = await full.byPreparingThumbnail(ofSize: fit(full.size, in: 600)) {
            result.image = small.jpegData(compressionQuality: 0.8)
        }
        return result
    }

    private static func imageData(_ item: NSItemProvider) async -> Data? {
        await withCheckedContinuation { done in
            _ = item.loadDataRepresentation(for: .image) { data, _ in done.resume(returning: data) }
        }
    }

    private static func fit(_ size: CGSize, in side: CGFloat) -> CGSize {
        let scale = min(1, side / max(size.width, size.height, 1))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
