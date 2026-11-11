import Foundation
import Observation
import Wire

/// The couple's latest check-ins, kept where `load` and `save` say: the app and its widgets pass the
/// same App Group file.
@Observable
public final class MoodStore: MoodChecking {
  /// Latest check-in per partner monogram.
  public private(set) var latest: [String: MoodCheckIn] = [:]

  @ObservationIgnored private let load: () -> [String: MoodCheckIn]?
  @ObservationIgnored private let save: ([String: MoodCheckIn]) -> Void

  public init(
    load: @escaping () -> [String: MoodCheckIn]?,
    save: @escaping ([String: MoodCheckIn]) -> Void
  ) {
    self.load = load
    self.save = save
    reload()
  }

  public func reload() {
    latest = load() ?? [:]
  }

  public func set(
    _ mood: CheckInMood, note: String? = nil, for partner: String, at date: Date = .now
  ) {
    take(MoodCheckIn(mood: mood, date: date, note: MoodCheckIn.clean(note)), for: partner)
  }

  @discardableResult
  public func take(_ check: MoodCheckIn, for partner: String, replacing: Bool = false) -> Bool {
    guard MoodCheckIn.take(check, for: partner, into: &latest, replacing: replacing) else {
      return false
    }
    save(latest)
    return true
  }
}
