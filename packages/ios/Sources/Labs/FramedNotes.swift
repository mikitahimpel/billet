import FeatureInbox
import Foundation
import Observation

/// The frame wall, kept in `defaults`. A fake partner uses its own key, so its notes never take
/// down the frames of real ones.
@MainActor
@Observable
public final class FramedNotes {
  public private(set) var wall: FrameWall

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let key: String

  public init(defaults: UserDefaults = .standard, key: String = "labs.framedNotes") {
    self.defaults = defaults
    self.key = key
    wall =
      defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(FrameWall.self, from: $0) }
      ?? FrameWall()
  }

  public func hang(_ note: NoteRecord) {
    var next = wall
    next.hang(note)
    update(next)
  }

  public func takeDown(_ id: UUID) {
    var next = wall
    next.takeDown(id)
    update(next)
  }

  public func prune(keeping notes: [NoteRecord]) {
    var next = wall
    next.prune(keeping: Set(notes.map(\.id)))
    update(next)
  }

  private func update(_ next: FrameWall) {
    guard next != wall else { return }
    wall = next
    defaults.set(try? JSONEncoder().encode(next), forKey: key)
  }
}
