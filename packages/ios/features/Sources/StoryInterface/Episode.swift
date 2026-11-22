import Foundation

/// One mystery, written as data: five beats, each with two halves of a clue, three suspects, an ending and a
/// souvenir. Text may carry `{cat}` and `{partner}`; `Episode.filled(_:cat:partner:)` swaps them in.
public struct Episode: Codable, Equatable, Sendable {
  public static let beatCount = 5
  public static let suspectCount = 3

  public struct Half: Codable, Equatable, Sendable {
    /// An SF Symbol name, the flat picture on the clue card.
    public let symbol: String
    public let text: String
  }

  public struct Beat: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// Where in the room the clue lies, in a few words.
    public let place: String
    /// Two different halves; which one a partner sees is `ClueSplit`'s.
    public let halves: [Half]
    /// What the two halves make once both are known.
    public let together: String
  }

  public struct Suspect: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let blurb: String
  }

  public struct Ending: Codable, Equatable, Sendable {
    public struct Verdicts: Codable, Equatable, Sendable {
      public let both: String
      public let one: String
      public let none: String
    }

    public let title: String
    public let lines: [String]
    public let verdicts: Verdicts
  }

  public struct Souvenir: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let note: String
    public let symbol: String
  }

  public let id: String
  public let title: String
  public let opening: String
  public let beats: [Beat]
  public let ask: String
  public let suspects: [Suspect]
  public let culprit: String
  public let ending: Ending
  public let souvenir: Souvenir

  /// Why an episode cannot be played.
  public enum Problem: Error, Equatable, Sendable {
    case beats(Int)
    case halves(beat: String)
    case suspects(Int)
    case unknownCulprit(String)
    case duplicateID(String)
    case badID(String)
    case emptyText(String)
  }

  /// Throws the first thing that would break the engine or the writing format.
  public func validate() throws(Problem) {
    guard beats.count == Self.beatCount else { throw .beats(beats.count) }
    guard suspects.count == Self.suspectCount else { throw .suspects(suspects.count) }
    let ids = [id, souvenir.id] + beats.map(\.id) + suspects.map(\.id)
    for item in ids where !Self.isKebab(item) { throw .badID(item) }
    for beat in beats {
      guard beat.halves.count == 2 else { throw .halves(beat: beat.id) }
      let texts = beat.halves.map(\.text) + [beat.title, beat.place, beat.together]
      if texts.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
        throw .emptyText(beat.id)
      }
    }
    var seen = Set<String>()
    for item in beats.map(\.id) + suspects.map(\.id) where !seen.insert(item).inserted {
      throw .duplicateID(item)
    }
    guard suspects.contains(where: { $0.id == culprit }) else { throw .unknownCulprit(culprit) }
    if ending.lines.isEmpty { throw .emptyText("ending") }
  }

  /// The `StoryId` shape the server accepts.
  static func isKebab(_ id: String) -> Bool {
    guard id.count <= 40, let first = id.first, first.isLowercase, first.isASCII else {
      return false
    }
    return id.split(separator: "-", omittingEmptySubsequences: false).allSatisfy { part in
      !part.isEmpty
        && part.allSatisfy { ($0.isASCII && $0.isLowercase) || $0.isNumber && $0.isASCII }
    }
  }

  /// The mark that records the ending was watched, kept next to the beats' ids.
  public static let endingRef = "ending"

  public func beat(_ id: String) -> Beat? { beats.first { $0.id == id } }

  public func suspect(_ id: String) -> Suspect? { suspects.first { $0.id == id } }

  /// `text` with the cat's and the partner's names in.
  public static func filled(_ text: String, cat: String, partner: String) -> String {
    text.replacingOccurrences(of: "{cat}", with: cat)
      .replacingOccurrences(of: "{partner}", with: partner)
  }
}
