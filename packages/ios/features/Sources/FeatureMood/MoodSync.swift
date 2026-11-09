import Foundation
import MoodInterface
import Transport
import Wire

/// The couple's check-ins in step with the pair's room: one sent for each set here, and each one
/// the room has taken into the phone's check-ins, which the header and the widgets read.
@MainActor
public struct MoodSync {
  public typealias Send = @Sendable (SetMoodRequest) async throws(TransportError) -> PartnerCheckIn

  let send: Send
  let moods: any MoodChecking
  /// This person's monogram.
  let viewer: () -> String
  /// A pair member's monogram by their user ID; nil for anyone outside the pair.
  let monogram: (UserId) -> String?

  public init(
    send: @escaping Send, moods: any MoodChecking, viewer: @escaping () -> String,
    monogram: @escaping (UserId) -> String?
  ) {
    self.send = send
    self.moods = moods
    self.viewer = viewer
    self.monogram = monogram
  }

  /// The room's check-ins when the phone follows the pair. One the viewer set here later, such as
  /// from a widget while the app was away, goes up now.
  public func follow(_ checkIns: [PartnerCheckIn]) async {
    for checkIn in checkIns { received(checkIn) }
    let viewer = viewer()
    guard let mine = moods.latest[viewer] else { return }
    let sent = checkIns.first { monogram($0.user) == viewer }.map(Self.date(of:))
    if sent.map({ mine.date > $0.addingTimeInterval(1) }) ?? true { await share(mine) }
  }

  /// Sends a check-in set on this phone. The room's answer, at the room's time, takes its place, so
  /// a phone whose clock runs ahead doesn't send it again on the next follow.
  public func share(_ check: MoodCheckIn) async {
    if let stored = try? await send(SetMoodRequest(mood: check.mood, note: check.note)) {
      received(stored, replacing: true)
    }
  }

  /// A check-in from the room, the partner's or this account's own from another phone.
  public func received(_ checkIn: PartnerCheckIn, replacing: Bool = false) {
    guard let partner = monogram(checkIn.user) else { return }
    moods.take(
      MoodCheckIn(mood: checkIn.mood, date: Self.date(of: checkIn), note: checkIn.note),
      for: partner, replacing: replacing)
  }

  public nonisolated static func date(of checkIn: PartnerCheckIn) -> Date {
    Date(timeIntervalSince1970: Double(checkIn.at) / 1000)
  }
}
