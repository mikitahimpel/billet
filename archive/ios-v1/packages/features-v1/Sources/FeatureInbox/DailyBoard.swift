import Foundation
import Persistence
import Wire

/// The prompt a pair shares for one day, as the room chose it.
public struct DailyPromptText: Codable, Hashable, Sendable {
  public let id: String
  public let text: String

  public init(id: String, text: String) {
    self.id = id
    self.text = text
  }
}

/// One day of the drawing of the day, as far as the room has let this phone see it.
public struct DailyEntry: Codable, Hashable, Identifiable, Sendable {
  /// The calendar day, `YYYY-MM-DD`, in the drawer's own calendar.
  public let day: String
  public var prompt: DailyPromptText
  public var mine: [Stroke]?
  /// The partner's drawing. The room sends it only once this phone has drawn its own.
  public var theirs: [Stroke]?
  /// The partner has drawn this day, whether or not their drawing is here yet.
  public var theirsDrawn: Bool

  public var id: String { day }

  /// Both have drawn, so the day counts for the streak.
  public var bothDrew: Bool { mine != nil && theirsDrawn }

  public init(
    day: String, prompt: DailyPromptText, mine: [Stroke]? = nil, theirs: [Stroke]? = nil,
    theirsDrawn: Bool = false
  ) {
    self.day = day
    self.prompt = prompt
    self.mine = mine
    self.theirs = theirs
    self.theirsDrawn = theirsDrawn || theirs != nil
  }
}

/// Every day of the drawing of the day this phone knows, and which reveals it has shown.
///
/// The room is the source of truth: it chooses the prompts and holds the partner's drawing back
/// until this phone has drawn. The board only merges what the room says with this phone's own
/// drawing, which shows at once before the room has answered.
public struct DailyBoard: Codable, Hashable, Sendable {
  /// Days kept for the archive; older ones fall off.
  public static let keptDays = 120

  public private(set) var prompts: [String: DailyPromptText]
  public private(set) var entries: [String: DailyEntry]
  /// Days whose reveal has played on this phone, so it plays once.
  public private(set) var revealed: Set<String>

  public init(
    prompts: [String: DailyPromptText] = [:], entries: [String: DailyEntry] = [:],
    revealed: Set<String> = []
  ) {
    self.prompts = prompts
    self.entries = entries
    self.revealed = revealed
  }

  /// The prompt for `day`, once the room has sent it.
  public func prompt(on day: String) -> DailyPromptText? {
    entries[day]?.prompt ?? prompts[day]
  }

  public func entry(on day: String) -> DailyEntry? {
    entries[day]
  }

  /// True once this phone has drawn `day`.
  public func hasDrawn(on day: String) -> Bool {
    entries[day]?.mine != nil
  }

  /// The days both drew, which the streak counts like a shared treat.
  public var sharedDays: Set<String> {
    Set(entries.values.filter(\.bothDrew).map(\.day))
  }

  /// Every day with a drawing from either side, newest first.
  public var archive: [DailyEntry] {
    entries.values.filter { $0.mine != nil || $0.theirsDrawn }.sorted { $0.day > $1.day }
  }

  /// The newest day with both drawings here whose reveal has not played yet.
  public var pendingReveal: DailyEntry? {
    archive.first { $0.mine != nil && $0.theirs != nil && !revealed.contains($0.day) }
  }

  /// Takes the room's prompts for the days a phone may be living now.
  public mutating func promptsReceived(_ received: [String: DailyPromptText]) {
    prompts = received
  }

  /// Keeps this phone's drawing of `day` before the room has answered. A day already drawn keeps
  /// its first drawing, as the room does.
  public mutating func drew(_ strokes: [Stroke], on day: String) {
    guard let prompt = prompt(on: day), !hasDrawn(on: day) else { return }
    var entry = entries[day] ?? DailyEntry(day: day, prompt: prompt)
    entry.mine = strokes
    entries[day] = entry
    prune()
  }

  /// Merges what the room says of a day. Nothing the room has sent is lost to a later frame that
  /// left it out, such as a replay that raced this phone's own drawing.
  public mutating func received(_ entry: DailyEntry) {
    let kept = entries[entry.day]
    entries[entry.day] = DailyEntry(
      day: entry.day, prompt: entry.prompt, mine: entry.mine ?? kept?.mine,
      theirs: entry.theirs ?? kept?.theirs,
      theirsDrawn: entry.theirsDrawn || kept?.theirsDrawn == true)
    prune()
  }

  /// Marks the reveal of `day` as played. A day the board has never revealed before the first
  /// launch with it, such as one replayed after a reinstall, can be marked without playing.
  public mutating func revealShown(_ day: String) {
    revealed.insert(day)
    revealed = revealed.filter { entries[$0] != nil }
  }

  private mutating func prune() {
    guard entries.count > Self.keptDays else { return }
    let keep = Set(entries.keys.sorted().suffix(Self.keptDays))
    entries = entries.filter { keep.contains($0.key) }
    revealed = revealed.filter(keep.contains)
  }
}

/// The drawing of the day kept on this device, in one JSON file next to the notes.
public actor DailyArchive {
  public static let fileName = "daily.json"

  private let storage: AppGroupStorage

  public init(storage: AppGroupStorage) {
    self.storage = storage
  }

  public func load() -> DailyBoard {
    (try? storage.readJSON(DailyBoard.self, named: Self.fileName)) ?? DailyBoard()
  }

  public func save(_ board: DailyBoard) {
    try? storage.writeJSON(board, named: Self.fileName)
  }
}
