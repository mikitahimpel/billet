import Foundation
import Testing

@testable import Pet

/// The brain never flickers: run frame by frame through needy and happy days, for every
/// temperament, no step, clip or interaction it asks for gives way again sooner than the shortest
/// a step may last, unless a person did something then. A state that flipped back and forth from
/// one frame to the next would show as a twitching cat.
@Suite("CatBrainDwell")
struct CatBrainDwellTests {
  typealias Day = CatBrainTests

  /// The least any state the brain asks for lasts, in seconds: the shortest step, a pounce or a
  /// startle.
  static let minimumDwell = 1.0
  /// The room plays the brain at the display's rate; a quarter of a second is the brain's own
  /// decision step, and a tenth samples between them.
  static let tick = 0.1

  static let days: [(String, [LifeEvent])] = [
    ("starving", CatFeelingTests.starving), ("unloved", CatFeelingTests.unloved),
    ("well fed", CatFeelingTests.wellFed), ("both active", Day.bothActive),
    ("lots of play", Day.lotsOfPlay),
  ]

  /// Half-hour windows through the day: morning, a tantrum's afternoon, a game's evening.
  static let windows: [Double] = [8, 13.5, 19]

  struct Run: CustomStringConvertible {
    var what: String
    var start: Double
    var end: Double
    var description: String { "\(what) for \(String(format: "%.2f", end - start)) s" }
  }

  /// Each run of the same `key` in the frames from `from` for `minutes`, with whether a person's
  /// event fell inside it or at its end.
  static func runs<Key: Equatable>(
    _ events: [LifeEvent], _ type: CatTemperament?, from: Double, minutes: Double,
    key: (CatBrainFrame) -> Key, name: (Key) -> String
  ) -> [(run: Run, touched: Bool)] {
    var runner = CatBrainRunner(
      events: events, now: Day.at(from), context: Day.context, seed: 11, temperament: type,
      room: Day.room)
    let times = events.map(\.at.timeIntervalSince1970)
    var out: [(Run, Bool)] = []
    var t = Day.at(from)
    let end = t + minutes * 60
    var current: (key: Key, start: Double)?
    while t < end {
      runner.advance(to: t)
      let now = key(runner.frame)
      if let held = current, held.key != now {
        let touched = times.contains { $0 >= held.start - tick && $0 <= t + tick }
        out.append((Run(what: name(held.key), start: held.start, end: t), touched))
        current = (now, t)
      } else if current == nil {
        current = (now, t)
      }
      t += tick
    }
    // The first run started before the window and the last goes on after it.
    return Array(out.dropFirst())
  }

  @Test(arguments: CatFeelingTests.types)
  func noStepClipOrTouchFlickers(_ type: CatTemperament?) {
    for (name, events) in Self.days {
      for from in Self.windows {
        let steps = Self.runs(
          events, type, from: from, minutes: 30,
          key: { [$0.stack.step.rawValue, "\($0.stepStart)"] }, name: { $0[0] })
        let clips = Self.runs(
          events, type, from: from, minutes: 30, key: \.action, name: \.rawValue)
        let touches = Self.runs(
          events, type, from: from, minutes: 30, key: \.stack.interaction,
          name: { String(describing: $0) })
        for (kind, runs) in [("step", steps), ("clip", clips), ("touch", touches)] {
          let short = runs.filter { !$0.touched && $0.run.end - $0.run.start < Self.minimumDwell }
          #expect(
            short.isEmpty,
            "\(String(describing: type)), \(name) from \(from) h: \(kind) \(short.prefix(3).map(\.run))"
          )
        }
      }
    }
  }
}
