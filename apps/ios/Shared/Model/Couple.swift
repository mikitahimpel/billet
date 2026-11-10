import Observation
import Persistence
import UIKit
import Vision

/// The pair on the server: which account holds each monogram.
public nonisolated struct PairMembers: Codable, Hashable, Sendable {
    public var pairID: String
    /// User ids by monogram.
    public var users: [String: String]

    public init(pairID: String, users: [String: String]) {
        self.pairID = pairID
        self.users = users
    }
}

/// The two partners on this device and the day they got together. Monograms and names are for display; once paired,
/// `pair` ties each monogram to an account.
public nonisolated struct Couple: Codable, Hashable, Sendable {
    /// Monograms, first partner first.
    public var partners: [String]
    public var togetherSince: Date
    /// Which partner is holding the phone: the signed-in account once paired, switched on the Us tab before that.
    public var viewer: String
    /// By monogram; the monograms stay their ids everywhere else.
    public var names: [String: String]? = nil
    /// Nil until this phone is paired on a server.
    public var pair: PairMembers? = nil

    public init(partners: [String], togetherSince: Date, viewer: String, names: [String: String]? = nil, pair: PairMembers? = nil) {
        self.partners = partners
        self.togetherSince = togetherSince
        self.viewer = viewer
        self.names = names
        self.pair = pair
    }

    public var other: String { viewer == partners[0] ? partners[1] : partners[0] }

    /// The partner's own name, or their monogram until they set one.
    public func name(of partner: String) -> String {
        names?[partner].flatMap { $0.isEmpty ? nil : $0 } ?? partner
    }

    /// Day one counts as day 1.
    public func daysTogether(on day: Date = .now) -> Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: togetherSince), to: cal.startOfDay(for: day)).day ?? 0
        return days + 1
    }

    /// First launch is day 1 until the couple sets their date.
    public static func starter(now: Date = .now) -> Couple {
        Couple(partners: ["L", "M"], togetherSince: Calendar.current.startOfDay(for: now), viewer: "L")
    }
}

@Observable
public final class CoupleStore {
    public private(set) var couple: Couple

    nonisolated private static let file = "Couple/couple.json"

    /// The couple as last saved, for a reader without a store such as the notification extension.
    public nonisolated static func saved() -> Couple? { SharedFile.read(Couple.self, from: file) }

    public init() {
        if let saved = SharedFile.read(Couple.self, from: Self.file) {
            couple = saved
        } else {
            // Saved right away so the widgets count from the same day.
            couple = .starter()
            SharedFile.write(couple, to: Self.file)
            SharedFile.flush()
        }
        loadPhotos()
    }

    public func reload() {
        if let saved = SharedFile.read(Couple.self, from: Self.file) { couple = saved }
        loadPhotos()
    }

    public func name(of partner: String) -> String { couple.name(of: partner) }

    public func initial(of partner: String) -> String {
        String(name(of: partner).prefix(1)).uppercased()
    }

    public func update(names: [String: String], togetherSince: Date) {
        couple.names = names.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        couple.togetherSince = togetherSince
        SharedFile.write(couple, to: Self.file)
    }

    // MARK: - Photos

    /// Small square JPEGs beside couple.json.
    public private(set) var photos: [String: UIImage] = [:]

    private static func photoFile(_ partner: String) -> String { "Couple/photo-\(partner).jpg" }

    private func loadPhotos() {
        photos = [:]
        for partner in couple.partners {
            if let data = try? Data(contentsOf: SharedFile.url(Self.photoFile(partner))), let image = UIImage(data: data) {
                photos[partner] = image
            }
        }
    }

    /// Square around the face, or the upper middle without one, stored at 400 px; nil removes the photo.
    public func setPhoto(_ image: UIImage?, for partner: String) {
        let url = SharedFile.url(Self.photoFile(partner))
        guard let image else {
            try? FileManager.default.removeItem(at: url)
            photos[partner] = nil
            return
        }
        let crop = Self.portraitSquare(in: image)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let square = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400), format: format).image { _ in
            let scale = 400 / crop.width
            image.draw(in: CGRect(x: -crop.minX * scale, y: -crop.minY * scale,
                                  width: image.size.width * scale, height: image.size.height * scale))
        }
        guard let data = square.jpegData(compressionQuality: 0.85) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        photos[partner] = square
    }

    /// The square, in the image's points, that frames a head: the largest face with room around it, so a circle
    /// never clips the chin or the hair. Without a face, the top of a tall photo, where heads usually are.
    public static func portraitSquare(in image: UIImage) -> CGRect {
        let size = image.size
        let short = min(size.width, size.height)
        var centre = CGPoint(x: size.width / 2, y: size.height > size.width ? short / 2 + (size.height - short) * 0.2
                                                                              : size.height / 2)
        var side = short
        if let cgImage = image.cgImage {
            let request = VNDetectFaceRectanglesRequest()
            let orientation = CGImagePropertyOrientation(image.imageOrientation)
            try? VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
            if let face = request.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width })?.boundingBox {
                // Vision's box is normalised with its origin at the bottom left.
                let rect = CGRect(x: face.minX * size.width, y: (1 - face.maxY) * size.height,
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

    /// Before pairing only; after it the viewer is the signed-in account.
    public func setViewer(_ partner: String) {
        guard couple.pair == nil, couple.partners.contains(partner), couple.viewer != partner else { return }
        couple.viewer = partner
        SharedFile.write(couple, to: Self.file)
    }

    /// Ties the monograms to the pair's two accounts. The holder keeps the monogram they had, or the one an earlier
    /// adopt gave this account.
    public func adopt(pairID: String, me: String, partner: String) {
        let mine = couple.pair?.users.first { $0.value == me }?.key ?? couple.viewer
        let theirs = mine == couple.partners[0] ? couple.partners[1] : couple.partners[0]
        let pair = PairMembers(pairID: pairID, users: [mine: me, theirs: partner])
        guard couple.pair != pair || couple.viewer != mine else { return }
        couple.pair = pair
        couple.viewer = mine
        SharedFile.write(couple, to: Self.file)
    }

    public func leavePair() {
        guard couple.pair != nil else { return }
        couple.pair = nil
        SharedFile.write(couple, to: Self.file)
    }
}

extension Notification.Name {
    /// The couple was saved by another `CoupleStore`, so the one on screen reads it again.
    public static let coupleChanged = Notification.Name("com.ourio.app.couple-changed")
}

private extension CGImagePropertyOrientation {
    public init(_ orientation: UIImage.Orientation) {
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
