import LinkPresentation
import UIKit
import UniformTypeIdentifiers

/// A wish's picture, a small JPEG next to the Us store in the app group, so the share extension can save one too.
enum WishImage {
    private static func url(_ id: UUID) -> URL { SharedFile.url("Us/Wishes/\(id.uuidString).jpg") }

    static func load(_ id: UUID) -> UIImage? { UIImage(contentsOfFile: url(id).path()) }

    static func save(_ data: Data, for id: UUID) {
        let target = url(id)
        let folder = target.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: target, options: .atomic)
    }

    static func remove(_ id: UUID) { try? FileManager.default.removeItem(at: url(id)) }
}

enum LinkPreview {
    struct Result {
        var title: String?
        /// JPEG, at most 600 points on its longer side.
        var image: Data?
    }

    /// Nil when the page can't be reached within 8 seconds.
    static func fetch(_ url: URL) async -> Result? {
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
