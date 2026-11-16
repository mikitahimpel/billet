// NoteStore is UIKit's: the module compiles to nothing for the package's macOS and Linux tests.
#if canImport(UIKit)
  import Foundation
  import MomentsInterface
  import Persistence
  import ShopInterface
  import Transport
  import Wire

  /// The board's notes between the two phones. A note written here goes up keyed by its local id so a retry never sends
  /// it twice: a text note as text, a doodle as a drawing with its picture. The partner's text notes and drawings come
  /// down into `notes` under `partner`.
  @MainActor
  public struct TextNoteSync {
    let api: APIClient
    let accounts: AccountStore
    let notes: NoteStore
    /// Monogram the partner's notes are kept under.
    let partner: String
    let defaults: UserDefaults

    /// Separate from the photos' and drawings' cursors.
    public static let cursorKey = "texts.lastSeq"

    public init(
      api: APIClient, accounts: AccountStore, notes: NoteStore, partner: String,
      defaults: UserDefaults
    ) {
      self.api = api
      self.accounts = accounts
      self.notes = notes
      self.partner = partner
      self.defaults = defaults
    }

    /// Sends every note still waiting, oldest first. One the server refuses, such as one in an ink, a stamp or a
    /// seal the pair doesn't own, goes again plain: the free ink, no stamp, no seal. One that fails to reach it stays
    /// waiting, and so do the rest. True when that happened, so the caller tries again later.
    public func sendUnsent() async -> Bool {
      for note in notes.unsent {
        guard !Task.isCancelled else { return true }
        if note.doodle != nil {
          switch await send(doodle: note) {
          case .sent, .refused: continue
          case .unreachable: return true
          }
        }
        guard let text = NoteText(validating: note.text) else { continue }
        let key = IdempotencyKey(note.id.uuidString)
        let paper = PaperColor(rawValue: note.paper.rawValue)
        let ink =
          note.ink.flatMap { hex in PaletteInk.bundled.first { $0.light == hex } }?.wireID ?? .free
        let sent: SendNoteResponse
        do {
          sent = try await api.sendNote(
            .text(key: key, text: text, paper: paper, stamp: note.stamp, seal: note.seal, ink: ink))
        } catch {
          if error.isWorthRetrying { return true }
          guard ink != .free || note.stamp != nil || note.seal != nil else { continue }
          do {
            sent = try await api.sendNote(.text(key: key, text: text, paper: paper, ink: .free))
          } catch {
            if error.isWorthRetrying { return true }
            continue
          }
        }
        guard case .text(let id, _, _, _, _, _, _, _) = sent.note else { continue }
        notes.setSent(note.id, noteID: id.rawValue)
      }
      return false
    }

    private enum Sending { case sent, refused, unreachable }

    /// The picture goes to /v1/media first. A doodle the server refuses for its stamp or seal goes again without them;
    /// one it refuses outright stays marked unsent.
    private func send(doodle note: MomentsInterface.Note) async -> Sending {
      guard let url = NoteStore.doodleURL(for: note), let png = try? Data(contentsOf: url) else {
        return .refused
      }
      let key = IdempotencyKey(note.id.uuidString)
      let paper = PaperColor(rawValue: note.paper.rawValue)
      let compact = note.compact ?? CompactStrokes(strokes: [])
      let sent: SendNoteResponse
      do throws(TransportError) {
        let image = try await api.uploadImage(png).image
        do throws(TransportError) {
          sent = try await api.sendNote(
            .drawing(
              key: key, compact: compact, image: image, paper: paper, stamp: note.stamp,
              seal: note.seal))
        } catch {
          guard !error.isWorthRetrying, note.stamp != nil || note.seal != nil else { throw error }
          sent = try await api.sendNote(
            .drawing(key: key, compact: compact, image: image, paper: paper))
        }
      } catch {
        return error.isWorthRetrying ? .unreachable : .refused
      }
      guard case .drawing(let id, _, _, _, _, _, _, _) = sent.note else { return .refused }
      notes.setSent(note.id, noteID: id.rawValue)
      return .sent
    }

    /// Pages through the notes after the last one looked at and keeps each text note and drawing the partner sent.
    /// Stops at a drawing whose picture won't download, so the next call tries it again.
    public func receive() async {
      let viewer = (try? accounts.load())?.record.userID
      var after = defaults.object(forKey: Self.cursorKey) as? Int
      while let page = try? await api.listNotes(after), let last = page.lastSeq {
        for entry in page.notes {
          guard await keep(entry.note, viewer: viewer) else { return }
          defaults.set(entry.seq, forKey: Self.cursorKey)
        }
        after = last
        defaults.set(last, forKey: Self.cursorKey)
      }
    }

    /// False only when the note is the partner's drawing and it could not be saved yet.
    private func keep(_ note: Wire.Note, viewer: String?) async -> Bool {
      switch note {
      case .text(let id, let author, let sentAt, let text, let paper, let stamp, let seal, let ink):
        guard author.rawValue != viewer else { return true }
        notes.addReceived(
          text: text.rawValue, paper: Self.paper(paper), stamp: stamp, seal: seal,
          ink: PaletteInk.bundled.first { $0.wireID == ink }?.light, author: partner,
          date: Self.date(sentAt), noteID: id.rawValue)
        return true
      case .drawing(let id, let author, let sentAt, _, let image, let paper, let stamp, let seal):
        guard author.rawValue != viewer, !notes.contains(noteID: id.rawValue) else { return true }
        guard let png = try? await api.downloadImage(image) else { return false }
        return notes.addReceived(
          doodle: png, paper: Self.paper(paper), stamp: stamp, seal: seal, author: partner,
          date: Self.date(sentAt), noteID: id.rawValue)
      case .photo:
        return true
      }
    }

    private static func paper(_ paper: PaperColor?) -> MomentsInterface.Note.Paper {
      paper.flatMap { MomentsInterface.Note.Paper(rawValue: $0.rawValue) } ?? .butter
    }

    private static func date(_ sentAt: Int) -> Date {
      Date(timeIntervalSince1970: Double(sentAt) / 1000)
    }
  }
#endif
