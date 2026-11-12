import Foundation
import Persistence

/// When to offer "Save your cat and notes" (Sign in with Apple) to an unlinked anonymous account:
/// after about a week of use or a few notes. Closing the card hides it for a month; the "Us"
/// screen always keeps the Sign in with Apple row.
public nonisolated struct SaveAccountPrompt: Codable, Equatable, Sendable {
  /// When this phone first used the account.
  public var startedAt: Date
  public var dismissedAt: Date?

  public static let afterUse: TimeInterval = 7 * 24 * 60 * 60
  public static let afterNotes = 5
  public static let quietAfterDismissal: TimeInterval = 30 * 24 * 60 * 60

  public init(startedAt: Date, dismissedAt: Date? = nil) {
    self.startedAt = startedAt
    self.dismissedAt = dismissedAt
  }

  public func isOffered(linked: Bool, notesSent: Int, now: Date) -> Bool {
    if linked { return false }
    if let dismissedAt, now.timeIntervalSince(dismissedAt) < Self.quietAfterDismissal {
      return false
    }
    return now.timeIntervalSince(startedAt) >= Self.afterUse || notesSent >= Self.afterNotes
  }

  public func dismissed(at now: Date) -> SaveAccountPrompt {
    SaveAccountPrompt(startedAt: startedAt, dismissedAt: now)
  }
}

/// Keeps ``SaveAccountPrompt`` in the App Group. A file that can't be read starts over, which at
/// worst offers the card a week later than it would have.
public nonisolated struct SaveAccountPromptStore: Sendable {
  public var load: @Sendable (_ now: Date) -> SaveAccountPrompt
  public var save: @Sendable (SaveAccountPrompt) -> Void

  public init(
    load: @escaping @Sendable (_ now: Date) -> SaveAccountPrompt,
    save: @escaping @Sendable (SaveAccountPrompt) -> Void
  ) {
    self.load = load
    self.save = save
  }

  public static func storage(_ storage: AppGroupStorage) -> SaveAccountPromptStore {
    let name = "save-account-prompt.json"
    return SaveAccountPromptStore(
      load: { now in
        if let saved = try? storage.readJSON(SaveAccountPrompt.self, named: name) { return saved }
        let started = SaveAccountPrompt(startedAt: now)
        try? storage.writeJSON(started, named: name)
        return started
      },
      save: { prompt in try? storage.writeJSON(prompt, named: name) })
  }
}
