import Observation
import UIKit

/// The two partners on this device and the day they got together. A local profile until accounts and sync exist.
nonisolated struct Couple: Codable, Hashable {
    /// Monograms, first partner first.
    var partners: [String]
    var togetherSince: Date
    /// Which partner is holding the phone; switched on the Us tab.
    var viewer: String
    /// Names the partners gave themselves, by monogram. The monograms stay their ids everywhere else.
    var names: [String: String]? = nil

    var other: String { viewer == partners[0] ? partners[1] : partners[0] }

    /// Day one counts as day 1.
    func daysTogether(on day: Date = .now) -> Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: togetherSince), to: cal.startOfDay(for: day)).day ?? 0
        return days + 1
    }

    /// First launch lands on day 127, the counter the app showed before profiles existed.
    static func starter(now: Date = .now) -> Couple {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -126, to: cal.startOfDay(for: now)) ?? now
        return Couple(partners: ["L", "M"], togetherSince: start, viewer: "L")
    }
}

@Observable
final class CoupleStore {
    private(set) var couple: Couple

    private static let file = "Couple/couple.json"

    init() {
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

    func reload() {
        if let saved = SharedFile.read(Couple.self, from: Self.file) { couple = saved }
        loadPhotos()
    }

    /// The partner's own name, or their monogram until they set one.
    func name(of partner: String) -> String {
        couple.names?[partner].flatMap { $0.isEmpty ? nil : $0 } ?? partner
    }

    /// The first letter of their name, shown on their avatar.
    func initial(of partner: String) -> String {
        String(name(of: partner).prefix(1)).uppercased()
    }

    func update(names: [String: String], togetherSince: Date) {
        couple.names = names.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        couple.togetherSince = togetherSince
        SharedFile.write(couple, to: Self.file)
    }

    // MARK: - Photos

    /// Avatar photos by partner, kept as small square JPEGs beside couple.json.
    private(set) var photos: [String: UIImage] = [:]

    private static func photoFile(_ partner: String) -> String { "Couple/photo-\(partner).jpg" }

    private func loadPhotos() {
        photos = [:]
        for partner in couple.partners {
            if let data = try? Data(contentsOf: SharedFile.url(Self.photoFile(partner))), let image = UIImage(data: data) {
                photos[partner] = image
            }
        }
    }

    /// Crops `image` to its centre square and stores it at 400 px; nil removes the photo.
    func setPhoto(_ image: UIImage?, for partner: String) {
        let url = SharedFile.url(Self.photoFile(partner))
        guard let image else {
            try? FileManager.default.removeItem(at: url)
            photos[partner] = nil
            return
        }
        let side = min(image.size.width, image.size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let square = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400), format: format).image { _ in
            let scale = 400 / side
            image.draw(in: CGRect(x: (side - image.size.width) / 2 * scale, y: (side - image.size.height) / 2 * scale,
                                  width: image.size.width * scale, height: image.size.height * scale))
        }
        guard let data = square.jpegData(compressionQuality: 0.85) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        photos[partner] = square
    }

    func setViewer(_ partner: String) {
        guard couple.partners.contains(partner), couple.viewer != partner else { return }
        couple.viewer = partner
        SharedFile.write(couple, to: Self.file)
    }
}
