import Foundation
import Persistence
import Transport
import UIKit
import Wire

/// Moments photos between the two phones. A photo taken here goes up to `POST /v1/media` as a JPEG and then as a photo
/// note with its caption; the partner's photo notes come down into `moments`, which is the local cache of both.
@MainActor
struct PhotoSync {
    let api: APIClient
    let accounts: AccountStore
    let moments: MomentStore
    /// Monogram the partner's photos are kept under.
    let partner: String
    var defaults: UserDefaults = .standard

    /// The last note `seq` this phone has looked at for photos. Separate from the drawings' cursor, so each reads
    /// the history at its own pace.
    static let cursorKey = "photos.lastSeq"

    /// Sends every photo still waiting, oldest first. One that fails stays waiting for the next try; the note's key
    /// is the moment's id, so a retry after a lost response never sends it twice.
    func sendUnsent() async {
        for moment in moments.unsent {
            guard !Task.isCancelled else { return }
            let url = MomentStore.imageURL(for: moment)
            guard let photo = await Task.detached(priority: .utility, operation: { PhotoUpload(fileAt: url) }).value
            else { continue }
            do {
                let upload = try await api.uploadImage(photo.jpeg)
                let caption = moment.caption.isEmpty ? nil : NoteText(validating: moment.caption)
                _ = try await api.sendNote(
                    .photo(key: IdempotencyKey(moment.id.uuidString), image: upload.image, width: photo.width,
                           height: photo.height, preview: photo.preview, caption: caption))
                moments.setUnsent(false, id: moment.id)
            } catch {
                continue
            }
        }
    }

    /// Pages through the notes after the last one looked at and keeps each photo the partner sent. Stops at a photo
    /// that won't download, so the next call tries it again.
    func receive() async {
        let viewer = (try? accounts.load())?.record.userID
        var after = defaults.object(forKey: Self.cursorKey) as? Int
        while let page = try? await api.listNotes(after), !page.notes.isEmpty {
            for entry in page.notes {
                guard await keep(entry.note, viewer: viewer) else { return }
                after = entry.seq
                defaults.set(entry.seq, forKey: Self.cursorKey)
            }
        }
    }

    /// False only when the note is the partner's photo and it could not be saved yet.
    private func keep(_ note: Wire.Note, viewer: String?) async -> Bool {
        guard case .photo(let id, let author, let sentAt, let image, _, _, _, let caption) = note,
              author.rawValue != viewer, !moments.contains(noteID: id.rawValue) else { return true }
        let maxPixels = MomentStore.storedPixels
        guard let data = try? await api.downloadImage(image),
              let photo = await Task.detached(priority: .utility, operation: {
                  Downsample.image(data: data, maxPixels: maxPixels)
              }).value else { return false }
        moments.add(photo, caption: caption?.rawValue ?? "", author: partner,
                    date: Date(timeIntervalSince1970: Double(sentAt) / 1000), noteID: id.rawValue)
        return true
    }
}

/// A Moments photo ready to send: a JPEG of at most 2048 px on the long side, its size, and its BlurHash.
nonisolated struct PhotoUpload {
    static let longSide = 2048
    static let quality: CGFloat = 0.8

    let jpeg: Data
    let width: Int
    let height: Int
    let preview: String

    init?(fileAt url: URL) {
        guard let image = Downsample.image(at: url, maxPixels: Self.longSide) else { return nil }
        self.init(image)
    }

    init?(_ image: UIImage) {
        guard let cg = image.cgImage, let jpeg = image.jpegData(compressionQuality: Self.quality),
              let preview = BlurHash.encode(cg) else { return nil }
        self.jpeg = jpeg
        width = cg.width
        height = cg.height
        self.preview = preview
    }
}
