import Foundation
import Pet

/// FAKE. How the scripted partner chooses the cat with you. A short while after your pick it picks
/// too: often the same cat, sometimes another. When it picked another it comes round to yours
/// after a while, so the bid never goes on forever. When you hold the agreed cat it holds too,
/// long enough to fill its ring.
struct FakeAdopter: Sendable {
  /// A reply to send after a delay, counted from the move it answers.
  struct Reply: Equatable, Sendable {
    var after: Duration
    var move: AdoptionMove
  }

  static let pickDelay = Duration.seconds(2)
  static let comeRoundDelay = Duration.seconds(9)
  static let holdDelay = Duration.milliseconds(700)
  static let holdLength = Duration.milliseconds(1_700)
  /// How often its first pick is the same as yours.
  static let agreeing = 0.55

  /// Its pick as far as its replies go.
  private(set) var pick: AdoptionCat?
  /// Draws from 0 up to 1.
  private var roll: @Sendable () -> Double

  init(roll: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }) {
    self.roll = roll
  }

  /// What it does in answer to your `move`. A new answer replaces any replies not sent yet.
  mutating func answer(_ move: AdoptionMove) -> [Reply] {
    switch move {
    case .pick(nil), .hold(false), .adopt:
      return []
    case .pick(let yours?):
      guard let current = pick else {
        let first = roll() < Self.agreeing ? yours : other(than: yours)
        pick = yours
        return first == yours
          ? [Reply(after: Self.pickDelay, move: .pick(yours))]
          : [
            Reply(after: Self.pickDelay, move: .pick(first)),
            Reply(after: Self.pickDelay + Self.comeRoundDelay, move: .pick(yours)),
          ]
      }
      pick = yours
      // You came round to its cat: it says so again, in case an earlier reply was dropped.
      if current == yours { return [Reply(after: .milliseconds(300), move: .pick(yours))] }
      return [
        Reply(after: .milliseconds(300), move: .pick(current)),
        Reply(after: Self.comeRoundDelay, move: .pick(yours)),
      ]
    case .hold(true):
      return [
        Reply(after: Self.holdDelay, move: .hold(true)),
        Reply(after: Self.holdDelay + Self.holdLength, move: .hold(false)),
      ]
    }
  }

  private func other(than cat: AdoptionCat) -> AdoptionCat {
    let others = AdoptionCat.allCases.filter { $0 != cat }
    return others[min(Int(roll() * Double(others.count)), others.count - 1)]
  }
}
