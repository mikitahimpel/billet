// MomentStore is UIKit's: the module compiles to nothing for the package's macOS and Linux tests.
#if canImport(UIKit)
  import Foundation
  import MomentsInterface
  import Persistence
  import Transport
  import Wire

  /// Moments photos between the two phones. A photo taken here goes up to `POST /v1/media` as a JPEG and then as a photo
  /// note with its caption; the partner's photo notes come down into `moments`, which is the local cache of both.
  @MainActor
  public struct PhotoSync {
    let api: APIClient
    let accounts: AccountStore
    let moments: MomentStore
    /// Monogram the partner's photos are kept under.
    let partner: String
    let receiving: PhotoReceiving
    let defaults: UserDefaults
    /// Reads and compresses the photo at a file; nil when it can't be read.
    let prepare: @Sendable (URL) -> PhotoUpload?

    /// Separate from the drawings' cursor, so each reads the history at its own pace.
    public static let cursorKey = "photos.lastSeq"

    public init(
      api: APIClient, accounts: AccountStore, moments: MomentStore, partner: String,
      receiving: PhotoReceiving,
      defaults: UserDefaults, prepare: @escaping @Sendable (URL) -> PhotoUpload?
    ) {
      self.api = api
      self.accounts = accounts
      self.moments = moments
      self.partner = partner
      self.receiving = receiving
      self.defaults = defaults
      self.prepare = prepare
    }

    /// Sends every photo still waiting, oldest first. One that fails stays waiting for the next try; the note's key
    /// is the moment's id, so a retry after a lost response never sends it twice. True when the server couldn't be
    /// reached, which leaves the rest waiting too, so the caller tries again later.
    public func sendUnsent() async -> Bool {
      for moment in moments.unsent {
        guard !Task.isCancelled else { return true }
        let url = MomentStore.imageURL(for: moment)
        guard let photo = await Task.detached(priority: .utility, operation: { prepare(url) }).value
        else { continue }
        do {
          let upload = try await api.uploadImage(photo.jpeg)
          let caption = moment.caption.isEmpty ? nil : NoteText(validating: moment.caption)
          let sent = try await api.sendNote(
            .photo(
              key: IdempotencyKey(moment.id.uuidString), image: upload.image, width: photo.width,
              height: photo.height, preview: photo.preview, caption: caption))
          guard case .photo(let id, _, _, _, _, _, _, _) = sent.note else { continue }
          moments.setUnsent(false, id: moment.id, noteID: id.rawValue)
        } catch {
          if error.isWorthRetrying { return true }
        }
      }
      return false
    }

    /// Pages through the notes after the last one looked at and keeps each photo the partner sent. Stops at a photo
    /// that won't download, so the next call tries it again.
    public func receive() async {
      await receiving.run(page)
    }

    private func page() async {
      let viewer = (try? accounts.load())?.record.userID
      var after = defaults.object(forKey: Self.cursorKey) as? Int
      while let page = try? await api.listNotes(after), let last = page.lastSeq {
        for entry in page.notes {
          guard await keep(entry.note, viewer: viewer) else { return }
          after = entry.seq
          defaults.set(entry.seq, forKey: Self.cursorKey)
        }
        after = last
        defaults.set(last, forKey: Self.cursorKey)
      }
    }

    /// False only when the note is the partner's photo and it could not be saved yet.
    private func keep(_ note: Wire.Note, viewer: String?) async -> Bool {
      guard case .photo(let id, let author, let sentAt, let image, _, _, _, let caption) = note,
        author.rawValue != viewer, !moments.contains(noteID: id.rawValue)
      else { return true }
      guard let data = try? await api.downloadImage(image) else { return false }
      let date = Date(timeIntervalSince1970: Double(sentAt) / 1000)
      await moments.addReceived(
        data, caption: caption?.rawValue ?? "", author: partner, date: date,
        noteID: id.rawValue)
      // False when it couldn't be stored, so the next receive tries it again.
      return moments.contains(noteID: id.rawValue)
    }
  }
#endif
