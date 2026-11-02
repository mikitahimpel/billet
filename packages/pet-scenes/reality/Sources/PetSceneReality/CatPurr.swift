import Foundation
import Observation
import Pet
import SwiftUI

/// What the purr shows over a room: whether the cat is purring, for the haptic, and the hearts
/// floating up from where the cat is on screen.
@MainActor @Observable
final class CatPurr {
  struct Heart: Identifiable, Equatable {
    let id: Int
    let at: CGPoint
    let born: Date
    /// Sideways drift, from -1 to 1, so hearts do not stack.
    let drift: Double
  }

  static let heartLife: TimeInterval = 1.4

  private(set) var isPurring = false
  private(set) var hearts: [Heart] = []
  @ObservationIgnored private var next = 0
  @ObservationIgnored private var petting = CatPetting()

  /// A stroke at `clock`, with the cat at `point` on screen. Returns whether the cat should roll.
  func touch(at clock: Double, cat point: CGPoint?) -> Bool {
    apply(petting.touch(at: clock), cat: point)
  }

  /// Time passed: hearts keep coming while the petting lasts, and a pause stops the purr.
  func tick(at clock: Double, cat point: CGPoint?) {
    guard petting.isPurring || !hearts.isEmpty else { return }
    _ = apply(petting.tick(at: clock), cat: point)
    let now = Date.now
    if hearts.contains(where: { now.timeIntervalSince($0.born) > Self.heartLife }) {
      hearts.removeAll { now.timeIntervalSince($0.born) > Self.heartLife }
    }
  }

  private func apply(_ events: [CatPetting.Event], cat point: CGPoint?) -> Bool {
    var rolled = false
    for event in events {
      switch event {
      case .purrStarted: isPurring = true
      case .purrEnded: isPurring = false
      case .rolled: rolled = true
      case .heart:
        guard let point else { continue }
        next += 1
        hearts.append(
          Heart(id: next, at: point, born: .now, drift: sin(Double(next) * 2.4)))
      }
    }
    return rolled
  }
}

/// The hearts over the cat, and a soft purr under the finger while it lasts.
struct CatPurrOverlay: View {
  let purr: CatPurr
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pulse = 0

  var body: some View {
    TimelineView(.animation(paused: purr.hearts.isEmpty)) { context in
      ZStack {
        ForEach(purr.hearts) { heart in
          let age = min(context.date.timeIntervalSince(heart.born) / CatPurr.heartLife, 1)
          let rise = reduceMotion ? 0 : 70 * age
          Image(systemName: "heart.fill")
            .font(.system(size: 15 + 6 * (1 - age)))
            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.55))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .opacity(1 - age * age)
            .position(
              x: heart.at.x + heart.drift * 22 * age, y: heart.at.y - 40 - rise)
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.35), trigger: pulse)
    .task(id: purr.isPurring) {
      // A purr is a soft flutter, about eleven beats a second, while the finger keeps stroking.
      while purr.isPurring, !Task.isCancelled {
        pulse += 1
        try? await Task.sleep(for: .milliseconds(90))
      }
    }
  }
}

/// When the room was last on screen, kept across launches, for the greeting after hours away.
enum CatSeen {
  static let key = "billet.cat.lastSeen"

  static var last: Date? {
    let seconds = UserDefaults.standard.double(forKey: key)
    return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
  }

  static func mark(_ now: Date = .now) {
    UserDefaults.standard.set(now.timeIntervalSince1970, forKey: key)
  }
}
