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
  /// Whether the cat purrs on its own, happy and close, with no finger on it.
  var brainPurring = false
  /// Either purr, for the haptic.
  var purrs: Bool { isPurring || brainPurring }
  private(set) var hearts: [Heart] = []
  /// How strong the purr under the finger is, from 0 to 1: the chin purrs hardest.
  var strength = 0.5
  /// The last one-off haptic asked for, numbered so the same one twice still plays.
  private(set) var felt: (serial: Int, haptic: CatHaptic)?
  @ObservationIgnored private var next = 0
  @ObservationIgnored private var petting = CatPetting()

  /// A stroke at `clock`, with the cat at `point` on screen. Returns whether the cat should roll.
  func touch(at clock: Double, cat point: CGPoint?) -> Bool {
    apply(petting.touch(at: clock), cat: point)
  }

  /// Plays `haptic` under the finger. A purr only changes the purr's strength.
  func feel(_ haptic: CatHaptic) {
    if case .purr(let strength) = haptic {
      self.strength = strength
      return
    }
    felt = ((felt?.serial ?? 0) + 1, haptic)
  }

  /// A heart rising from `point`, for care that is not a stroke.
  func heart(at point: CGPoint?) {
    guard let point else { return }
    next += 1
    hearts.append(Heart(id: next, at: point, born: .now, drift: sin(Double(next) * 2.4)))
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
        heart(at: point)
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
    .sensoryFeedback(trigger: pulse) { _, _ in .impact(flexibility: .soft, intensity: pulseLevel) }
    .sensoryFeedback(trigger: beat) { _, _ in beatFeedback }
    .task(id: purr.purrs) {
      // A purr rumbles in breaths: a lighter flutter breathing in, a fuller one breathing out,
      // as strong as the spot under the finger makes it.
      var start = ContinuousClock.now
      while purr.purrs, !Task.isCancelled {
        let into = (ContinuousClock.now - start) / CatPurrOverlay.breath
        if into >= 1 { start = .now }
        let breathingIn = into.truncatingRemainder(dividingBy: 1) < 0.45
        let strength = purr.isPurring ? purr.strength : 0.35
        pulseLevel = strength * (breathingIn ? 0.5 : 0.85)
        pulse += 1
        try? await Task.sleep(for: .milliseconds(breathingIn ? 85 : 65))
      }
    }
    .task(id: purr.felt?.serial) {
      guard let haptic = purr.felt?.haptic else { return }
      for (index, feedback) in CatPurrOverlay.pattern(haptic).enumerated() {
        if index > 0 {
          try? await Task.sleep(for: .milliseconds(CatPurrOverlay.patternGap(haptic)))
        }
        guard !Task.isCancelled else { return }
        beatFeedback = feedback
        beat += 1
      }
    }
  }

  @State private var pulseLevel = 0.4
  @State private var beat = 0
  @State private var beatFeedback = SensoryFeedback.impact(weight: .light)

  static let breath = Duration.seconds(2)

  /// The taps a one-off haptic is made of.
  static func pattern(_ haptic: CatHaptic) -> [SensoryFeedback] {
    switch haptic {
    case .purr: []
    case .nudge:
      [.impact(flexibility: .soft, intensity: 0.45), .impact(flexibility: .soft, intensity: 0.3)]
    case .grab:
      [
        .impact(flexibility: .rigid, intensity: 0.7), .impact(flexibility: .rigid, intensity: 0.5),
        .impact(flexibility: .rigid, intensity: 0.6),
      ]
    case .pounce: [.impact(weight: .medium, intensity: 0.9)]
    case .chomp: Array(repeating: .impact(flexibility: .solid, intensity: 0.35), count: 4)
    case .lift: [.impact(weight: .light, intensity: 0.6)]
    case .settle: [.impact(weight: .heavy, intensity: 0.45)]
    case .trick: [.success]
    }
  }

  static func patternGap(_ haptic: CatHaptic) -> Int {
    switch haptic {
    case .chomp: 380
    case .grab: 110
    case .purr, .nudge, .pounce, .lift, .settle, .trick: 140
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
