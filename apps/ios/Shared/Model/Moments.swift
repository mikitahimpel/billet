import ImageIO
import Observation
import UIKit

/// One shared photo with a caption, visible only to the couple.
nonisolated struct Moment: Identifiable, Codable, Hashable {
    let id: UUID
    /// Monogram of the partner who added it, "L" or "M".
    let author: String
    let date: Date
    var caption: String
    /// JPEG file name inside the app group's Moments folder.
    let file: String
    var pinned: Bool
    /// The other partner tapped the heart.
    var loved: Bool
}

/// Local-only moments store; JSON index and JPEGs live in the app group's Moments folder, where the widgets read them.
@Observable
final class MomentStore {
    /// Polaroids that fit on the room wall.
    static let wallSlots = 6

    /// Long side of the stored JPEGs; also what the viewer shows.
    static let storedPixels = 2048
    /// Shared by the room's polaroids and the strip that mirrors them, so both hit the same cache entry.
    static let wallPixels = 384

    private(set) var moments: [Moment] = []
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 64 << 20
        return cache
    }()

    private static let folder = AppGroup.container.appending(path: "Moments", directoryHint: .isDirectory)
    private static let index = "Moments/moments.json"

    init() {
        reload()
    }

    /// Picks up changes made outside this process.
    func reload() {
        moments = SharedFile.read([Moment].self, from: Self.index) ?? []
    }

    static func imageURL(for moment: Moment) -> URL { folder.appending(path: moment.file) }

    /// Newest first, pinned ones capped at the wall size.
    var pinned: [Moment] { Array(moments.filter(\.pinned).prefix(Self.wallSlots)) }

    func cachedThumbnail(for moment: Moment, maxPixels: Int) -> UIImage? {
        cache.object(forKey: Self.key(moment, maxPixels))
    }

    /// Decoded off the main thread at `maxPixels` on the long side, then cached.
    func thumbnail(for moment: Moment, maxPixels: Int) async -> UIImage? {
        if let hit = cachedThumbnail(for: moment, maxPixels: maxPixels) { return hit }
        let url = Self.imageURL(for: moment)
        let image = await Task.detached(priority: .userInitiated) { Downsample.image(at: url, maxPixels: maxPixels) }.value
        if let image, let cg = image.cgImage {
            cache.setObject(image, forKey: Self.key(moment, maxPixels), cost: cg.bytesPerRow * cg.height)
        }
        return image
    }

    func thumbnails(for moments: [Moment], maxPixels: Int) async -> [UIImage] {
        var images: [UIImage] = []
        for moment in moments {
            if let image = await thumbnail(for: moment, maxPixels: maxPixels) { images.append(image) }
        }
        return images
    }

    func cachedFilmPrint(for moment: Moment, maxPixels: Int) -> UIImage? {
        cache.object(forKey: Self.key(moment, maxPixels, film: true))
    }

    /// The photo with the instant-film grade, as polaroids show it; graded off the main thread, then cached.
    func filmPrint(for moment: Moment, maxPixels: Int) async -> UIImage? {
        if let hit = cachedFilmPrint(for: moment, maxPixels: maxPixels) { return hit }
        guard let photo = await thumbnail(for: moment, maxPixels: maxPixels) else { return nil }
        let graded = await Task.detached(priority: .userInitiated) { InstantFilm.develop(photo) }.value ?? photo
        if let cg = graded.cgImage {
            cache.setObject(graded, forKey: Self.key(moment, maxPixels, film: true), cost: cg.bytesPerRow * cg.height)
        }
        return graded
    }

    func filmPrints(for moments: [Moment], maxPixels: Int) async -> [UIImage] {
        var images: [UIImage] = []
        for moment in moments {
            if let image = await filmPrint(for: moment, maxPixels: maxPixels) { images.append(image) }
        }
        return images
    }

    private static func key(_ moment: Moment, _ maxPixels: Int, film: Bool = false) -> NSString {
        "\(moment.file)@\(maxPixels)\(film ? "~film" : "")" as NSString
    }

    @discardableResult
    func add(_ image: UIImage, caption: String, author: String) -> Moment? {
        // Camera photos are 12+ MP; 2048 px is plenty for a full-screen look and keeps the folder small.
        let longSide = max(image.size.width, image.size.height)
        let scale = min(1, CGFloat(Self.storedPixels) / max(longSide, 1))
        let fitted = scale < 1
            ? image.preparingThumbnail(of: CGSize(width: image.size.width * scale, height: image.size.height * scale)) ?? image
            : image
        guard let data = fitted.jpegData(compressionQuality: 0.85) else { return nil }
        let file = "\(UUID().uuidString).jpg"
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try data.write(to: Self.folder.appending(path: file))
        } catch {
            return nil
        }
        let moment = Moment(id: UUID(), author: author, date: .now, caption: caption, file: file,
                            pinned: pinned.count < Self.wallSlots, loved: false)
        moments.insert(moment, at: 0)
        save()
        return moment
    }

    /// Pinning a seventh moment unpins the oldest pinned one so the wall stays full but tidy.
    func togglePin(_ moment: Moment) {
        guard let i = moments.firstIndex(of: moment) else { return }
        moments[i].pinned.toggle()
        if moments[i].pinned, let extra = moments.lastIndex(where: \.pinned), moments.filter(\.pinned).count > Self.wallSlots {
            moments[extra].pinned = false
        }
        save()
    }

    func toggleLove(_ moment: Moment) {
        guard let i = moments.firstIndex(of: moment) else { return }
        moments[i].loved.toggle()
        save()
    }

    func setCaption(_ caption: String, of moment: Moment) {
        guard let i = moments.firstIndex(of: moment) else { return }
        moments[i].caption = caption
        save()
    }

    func delete(_ moment: Moment) {
        moments.removeAll { $0.id == moment.id }
        try? FileManager.default.removeItem(at: Self.folder.appending(path: moment.file))
        save()
    }

    private func save() {
        SharedFile.write(moments, to: Self.index)
    }
}

/// ImageIO decodes straight to a bitmap of at most `maxPixels` on the long side, so a 2048 px JPEG or a 12 MP photo
/// never sits in memory at full size. Safe off the main thread.
nonisolated enum Downsample {
    static func image(at url: URL, maxPixels: Int) -> UIImage? {
        CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
            .flatMap { thumbnail($0, maxPixels: maxPixels) }
    }

    static func image(data: Data, maxPixels: Int) -> UIImage? {
        CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
            .flatMap { thumbnail($0, maxPixels: maxPixels) }
    }

    private static func thumbnail(_ source: CGImageSource, maxPixels: Int) -> UIImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options).map { UIImage(cgImage: $0) }
    }
}
