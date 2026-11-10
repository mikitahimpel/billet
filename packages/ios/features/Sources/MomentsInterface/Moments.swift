// The photos are UIKit images: the target compiles to nothing for the package's macOS tests.
#if canImport(UIKit)
  import ImageIO
  import Observation
  import Persistence
  import UIKit
  import UniformTypeIdentifiers

  public struct Moment: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    /// Monogram of the partner who added it, "L" or "M".
    public let author: String
    public let date: Date
    public var caption: String
    /// JPEG file name inside the app group's Moments folder.
    public let file: String
    public var pinned: Bool
    /// The other partner tapped the heart.
    public var loved: Bool
    /// Taken on this phone and still waiting to reach the partner.
    public var unsent: Bool? = nil
    /// The partner's photo note this came from, for photos they sent.
    public var noteID: String? = nil

    public init(
      id: UUID, author: String, date: Date, caption: String, file: String, pinned: Bool,
      loved: Bool, unsent: Bool? = nil, noteID: String? = nil
    ) {
      self.id = id
      self.author = author
      self.date = date
      self.caption = caption
      self.file = file
      self.pinned = pinned
      self.loved = loved
      self.unsent = unsent
      self.noteID = noteID
    }
  }

  /// The couple's moments on this phone: a JSON index and JPEGs in the app group's Moments folder, where the widgets read
  /// them. Photos taken here go to the partner and theirs come back through `PhotoSync`; this folder is the cache.
  @Observable
  public final class MomentStore {
    public static let wallSlots = 6

    /// Long side of the stored JPEGs; also what the viewer shows.
    public static let storedPixels = 2048
    /// Shared by the room's polaroids and the strip that mirrors them, so both hit the same cache entry.
    public static let wallPixels = 384

    public private(set) var moments: [Moment] = []
    private let cache: NSCache<NSString, UIImage> = {
      let cache = NSCache<NSString, UIImage>()
      cache.totalCostLimit = 64 << 20
      return cache
    }()

    private static let folder = AppGroup.container.appending(
      path: "Moments", directoryHint: .isDirectory)
    private static let index = "Moments/moments.json"

    public init() {
      reload()
    }

    /// Picks up changes made outside this process.
    public func reload() {
      moments = SharedFile.read([Moment].self, from: Self.index) ?? []
    }

    public static func imageURL(for moment: Moment) -> URL { folder.appending(path: moment.file) }

    /// Newest first, pinned ones capped at the wall size.
    public var pinned: [Moment] { Array(moments.filter(\.pinned).prefix(Self.wallSlots)) }

    public func cachedThumbnail(for moment: Moment, maxPixels: Int) -> UIImage? {
      cache.object(forKey: Self.key(moment, maxPixels))
    }

    /// Decoded off the main thread at `maxPixels` on the long side, then cached.
    public func thumbnail(for moment: Moment, maxPixels: Int) async -> UIImage? {
      if let hit = cachedThumbnail(for: moment, maxPixels: maxPixels) { return hit }
      let url = Self.imageURL(for: moment)
      let image = await Task.detached(priority: .userInitiated) {
        Downsample.image(at: url, maxPixels: maxPixels)
      }.value
      if let image, let cg = image.cgImage {
        cache.setObject(
          image, forKey: Self.key(moment, maxPixels), cost: cg.bytesPerRow * cg.height)
      }
      return image
    }

    public func thumbnails(for moments: [Moment], maxPixels: Int) async -> [UIImage] {
      var images: [UIImage] = []
      for moment in moments {
        if let image = await thumbnail(for: moment, maxPixels: maxPixels) { images.append(image) }
      }
      return images
    }

    public func cachedFilmPrint(for moment: Moment, maxPixels: Int) -> UIImage? {
      cache.object(forKey: Self.key(moment, maxPixels, film: true))
    }

    /// The photo with the instant-film grade, as polaroids show it; graded off the main thread, then cached.
    public func filmPrint(for moment: Moment, maxPixels: Int) async -> UIImage? {
      if let hit = cachedFilmPrint(for: moment, maxPixels: maxPixels) { return hit }
      guard let photo = await thumbnail(for: moment, maxPixels: maxPixels) else { return nil }
      let graded =
        await Task.detached(priority: .userInitiated) { InstantFilm.develop(photo) }.value ?? photo
      if let cg = graded.cgImage {
        cache.setObject(
          graded, forKey: Self.key(moment, maxPixels, film: true), cost: cg.bytesPerRow * cg.height)
      }
      return graded
    }

    public func filmPrints(for moments: [Moment], maxPixels: Int) async -> [UIImage] {
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
    public func add(
      _ image: UIImage, caption: String, author: String, date: Date = .now, noteID: String? = nil,
      unsent: Bool = false
    ) -> Moment? {
      // Camera photos are 12+ MP; 2048 px is plenty for a full-screen look and keeps the folder small.
      let longSide = max(image.size.width, image.size.height)
      let scale = min(1, CGFloat(Self.storedPixels) / max(longSide, 1))
      let fitted =
        scale < 1
        ? image.preparingThumbnail(
          of: CGSize(width: image.size.width * scale, height: image.size.height * scale)) ?? image
        : image
      guard let data = fitted.jpegData(compressionQuality: 0.85),
        let file = Self.write(data, in: Self.folder)
      else { return nil }
      return insert(
        file: file, caption: caption, author: author, date: date, noteID: noteID, unsent: unsent)
    }

    /// A partner's photo as it was downloaded. A JPEG within `storedPixels` is kept as it came; anything else is fitted
    /// and encoded again. Either way off the main thread, which only adds it to the list.
    @discardableResult
    public func addReceived(
      _ data: Data, caption: String, author: String, date: Date, noteID: String
    ) async -> Moment? {
      let folder = Self.folder
      let maxPixels = Self.storedPixels
      let file = await Task.detached(priority: .utility) {
        MomentStore.store(received: data, maxPixels: maxPixels, in: folder)
      }.value
      guard let file, !contains(noteID: noteID) else { return nil }
      return insert(
        file: file, caption: caption, author: author, date: date, noteID: noteID, unsent: false)
    }

    /// Its own function: Xcode 26's isolation checker rejects this body inline in a detached closure in Release.
    nonisolated private static func store(received data: Data, maxPixels: Int, in folder: URL)
      -> String?
    {
      guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
      let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? .max
      let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? .max
      if CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
        max(width, height) <= maxPixels
      {
        return write(data, in: folder)
      }
      guard
        let jpeg = Downsample.image(data: data, maxPixels: maxPixels)?.jpegData(
          compressionQuality: 0.85)
      else { return nil }
      return write(jpeg, in: folder)
    }

    nonisolated private static func write(_ jpeg: Data, in folder: URL) -> String? {
      let file = "\(UUID().uuidString).jpg"
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try jpeg.write(to: folder.appending(path: file))
      } catch {
        return nil
      }
      return file
    }

    private func insert(
      file: String, caption: String, author: String, date: Date, noteID: String?,
      unsent: Bool
    ) -> Moment {
      let moment = Moment(
        id: UUID(), author: author, date: date, caption: caption, file: file,
        pinned: pinned.count < Self.wallSlots, loved: false, unsent: unsent ? true : nil,
        noteID: noteID)
      // Newest first; a photo from the partner can be older than ones already here.
      moments.insert(moment, at: moments.firstIndex { $0.date < date } ?? moments.endIndex)
      save()
      return moment
    }

    /// Photos taken here that have not reached the partner yet, oldest first.
    public var unsent: [Moment] { moments.filter { $0.unsent == true }.reversed() }

    public func contains(noteID: String) -> Bool { moments.contains { $0.noteID == noteID } }

    /// Marks a photo taken here as waiting to reach the partner, or as delivered as the server's note `noteID`.
    public func setUnsent(_ unsent: Bool, id: UUID, noteID: String? = nil) {
      guard let i = moments.firstIndex(where: { $0.id == id }) else { return }
      moments[i].unsent = unsent ? true : nil
      if let noteID { moments[i].noteID = noteID }
      save()
    }

    /// Pinning a seventh moment unpins the oldest pinned one so the wall stays full but tidy.
    public func togglePin(_ moment: Moment) {
      guard let i = moments.firstIndex(of: moment) else { return }
      moments[i].pinned.toggle()
      if moments[i].pinned, let extra = moments.lastIndex(where: \.pinned),
        moments.filter(\.pinned).count > Self.wallSlots
      {
        moments[extra].pinned = false
      }
      save()
    }

    public func toggleLove(_ moment: Moment) {
      guard let i = moments.firstIndex(of: moment) else { return }
      moments[i].loved.toggle()
      save()
    }

    public func setCaption(_ caption: String, of moment: Moment) {
      guard let i = moments.firstIndex(of: moment) else { return }
      moments[i].caption = caption
      save()
    }

    public func delete(_ moment: Moment) {
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
  public enum Downsample {
    public static func image(at url: URL, maxPixels: Int) -> UIImage? {
      CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        .flatMap { thumbnail($0, maxPixels: maxPixels) }
    }

    public static func image(data: Data, maxPixels: Int) -> UIImage? {
      CGImageSourceCreateWithData(
        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary
      )
      .flatMap { thumbnail($0, maxPixels: maxPixels) }
    }

    private static func thumbnail(_ source: CGImageSource, maxPixels: Int) -> UIImage? {
      let options =
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceShouldCacheImmediately: true,
          kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary
      return CGImageSourceCreateThumbnailAtIndex(source, 0, options).map { UIImage(cgImage: $0) }
    }
  }
#endif
