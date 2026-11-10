import Foundation
import Observation

#if canImport(UIKit)
  import UIKit
  import Vision

  public typealias PartnerPhoto = UIImage
#else
  /// Photos are drawn only on iOS; the package's macOS tests see none.
  public typealias PartnerPhoto = Never
#endif

/// The couple on this phone, kept where `load` and `save` say: the app and its extensions pass the
/// same App Group file. `photoURL` is where each partner's photo is.
@Observable
public final class CoupleStore {
  public private(set) var couple: Couple
  /// Small square JPEGs beside the couple's file.
  public private(set) var photos: [String: PartnerPhoto] = [:]

  @ObservationIgnored private let load: () -> Couple?
  @ObservationIgnored private let save: (Couple) -> Void
  @ObservationIgnored private let photoURL: (String) -> URL

  /// With nothing saved, the starter couple is saved right away so the widgets count from the
  /// same day.
  public init(
    load: @escaping () -> Couple?, save: @escaping (Couple) -> Void,
    photoURL: @escaping (String) -> URL
  ) {
    self.load = load
    self.save = save
    self.photoURL = photoURL
    if let saved = load() {
      couple = saved
    } else {
      couple = .starter()
      save(couple)
    }
    loadPhotos()
  }

  public func reload() {
    if let saved = load() { couple = saved }
    loadPhotos()
  }

  public func name(of partner: String) -> String { couple.name(of: partner) }

  public func initial(of partner: String) -> String {
    String(name(of: partner).prefix(1)).uppercased()
  }

  public func update(names: [String: String], togetherSince: Date) {
    couple.names = names.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    couple.togetherSince = togetherSince
    save(couple)
  }

  /// Before pairing only; after it the viewer is the signed-in account.
  public func setViewer(_ partner: String) {
    guard couple.pair == nil, couple.partners.contains(partner), couple.viewer != partner else {
      return
    }
    couple.viewer = partner
    save(couple)
  }

  /// Ties the monograms to the pair's two accounts. The holder keeps the monogram they had, or the
  /// one an earlier adopt gave this account.
  public func adopt(pairID: String, me: String, partner: String) {
    let mine = couple.pair?.users.first { $0.value == me }?.key ?? couple.viewer
    let theirs = mine == couple.partners[0] ? couple.partners[1] : couple.partners[0]
    let pair = PairMembers(pairID: pairID, users: [mine: me, theirs: partner])
    guard couple.pair != pair || couple.viewer != mine else { return }
    couple.pair = pair
    couple.viewer = mine
    save(couple)
  }

  public func leavePair() {
    guard couple.pair != nil else { return }
    couple.pair = nil
    save(couple)
  }

  #if canImport(UIKit)
    private func loadPhotos() {
      photos = [:]
      for partner in couple.partners {
        if let data = try? Data(contentsOf: photoURL(partner)), let image = UIImage(data: data) {
          photos[partner] = image
        }
      }
    }

    /// Square around the face, or the upper middle without one, stored at 400 px; nil removes the
    /// photo.
    public func setPhoto(_ image: UIImage?, for partner: String) {
      let url = photoURL(partner)
      guard let image else {
        try? FileManager.default.removeItem(at: url)
        photos[partner] = nil
        return
      }
      let crop = Self.portraitSquare(in: image)
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      let square = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400), format: format)
        .image { _ in
          let scale = 400 / crop.width
          image.draw(
            in: CGRect(
              x: -crop.minX * scale, y: -crop.minY * scale,
              width: image.size.width * scale, height: image.size.height * scale))
        }
      guard let data = square.jpegData(compressionQuality: 0.85) else { return }
      try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: url, options: .atomic)
      photos[partner] = square
    }

    /// The square, in the image's points, that frames a head: the largest face with room around it,
    /// so a circle never clips the chin or the hair. Without a face, the top of a tall photo, where
    /// heads usually are.
    public static func portraitSquare(in image: UIImage) -> CGRect {
      let size = image.size
      let short = min(size.width, size.height)
      var centre = CGPoint(
        x: size.width / 2,
        y: size.height > size.width ? short / 2 + (size.height - short) * 0.2 : size.height / 2)
      var side = short
      if let cgImage = image.cgImage {
        let request = VNDetectFaceRectanglesRequest()
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        try? VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
        if let face = request.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width })?
          .boundingBox
        {
          // Vision's box is normalised with its origin at the bottom left.
          let rect = CGRect(
            x: face.minX * size.width, y: (1 - face.maxY) * size.height,
            width: face.width * size.width, height: face.height * size.height)
          side = min(short, max(rect.width, rect.height) * 2.4)
          // A little above the box's middle, so the hair has as much room as the chin.
          centre = CGPoint(x: rect.midX, y: rect.midY - rect.height * 0.1)
        }
      }
      let x = min(max(centre.x - side / 2, 0), size.width - side)
      let y = min(max(centre.y - side / 2, 0), size.height - side)
      return CGRect(x: x, y: y, width: side, height: side)
    }
  #else
    private func loadPhotos() {}
  #endif
}

#if canImport(UIKit)
  extension CGImagePropertyOrientation {
    fileprivate init(_ orientation: UIImage.Orientation) {
      switch orientation {
      case .up: self = .up
      case .down: self = .down
      case .left: self = .left
      case .right: self = .right
      case .upMirrored: self = .upMirrored
      case .downMirrored: self = .downMirrored
      case .leftMirrored: self = .leftMirrored
      case .rightMirrored: self = .rightMirrored
      @unknown default: self = .up
      }
    }
  }
#endif
