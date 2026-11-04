import Foundation
import OSLog

#if canImport(UIKit)
  import QuartzCore
#endif

/// Steps a room once per display frame, with the time since the step before.
///
/// A room is stepped from the display, not from its scene's update events. With more than one
/// RealityView in the app, only one of them keeps updating its scene every frame; a view mounted
/// after another sends a few updates and then only redraws for touches, so a room stepped by its
/// own scene stops partway through its opening: lamp off, note missing, cat still asleep. Changes
/// made between a scene's updates still reach its next render.
@MainActor
final class FrameClock {
  /// The longest step, so a stall does not throw everything forward at once.
  static let longestStep: TimeInterval = 0.1
  static let framesPerSecond = 60.0

  private var step: (@MainActor (TimeInterval) -> Void)?
  private var lastTime: TimeInterval?
  private var stats = FrameStats()
  #if canImport(UIKit)
    private var link: CADisplayLink?
  #else
    private var timer: Timer?
  #endif

  /// Whether steps are held, as while the room is off screen. The time held does not count.
  var isPaused = false {
    didSet {
      guard isPaused != oldValue else { return }
      lastTime = nil
      #if canImport(UIKit)
        link?.isPaused = isPaused
      #endif
    }
  }

  var isRunning: Bool { step != nil }

  /// The most frames a second it steps, or nil for the display's own rate. See ``FramePace``.
  var rate: Float? = FramePace.moving {
    didSet {
      guard rate != oldValue else { return }
      applyRate()
    }
  }

  private func applyRate() {
    #if canImport(UIKit)
      link?.preferredFrameRateRange =
        rate.map { CAFrameRateRange(minimum: min(10, $0), maximum: $0, preferred: $0) } ?? .default
    #endif
  }

  /// Calls `step` on every frame from now on, in place of whatever it called before.
  func run(_ step: @escaping @MainActor (TimeInterval) -> Void) {
    self.step = step
    lastTime = nil
    #if canImport(UIKit)
      guard link == nil else { return }
      let link = CADisplayLink(
        target: FrameTarget(clock: self), selector: #selector(FrameTarget.fire))
      link.isPaused = isPaused
      link.add(to: .main, forMode: .common)
      self.link = link
      applyRate()
    #else
      guard timer == nil else { return }
      timer = Timer.scheduledTimer(withTimeInterval: 1 / Self.framesPerSecond, repeats: true) {
        [weak self] _ in
        MainActor.assumeIsolated { self?.fire(at: ProcessInfo.processInfo.systemUptime) }
      }
    #endif
  }

  func stop() {
    step = nil
    lastTime = nil
    #if canImport(UIKit)
      link?.invalidate()
      link = nil
    #else
      timer?.invalidate()
      timer = nil
    #endif
  }

  /// One frame at `time`, in seconds.
  func fire(at time: TimeInterval) {
    guard !isPaused, let step else { return }
    if let lastTime { stats.add(time - lastTime, at: time) }
    let delta = lastTime.map { min(time - $0, Self.longestStep) } ?? 1 / Self.framesPerSecond
    lastTime = time
    step(max(delta, 0))
  }
}

#if canImport(UIKit)
  /// The display link's target. The link keeps its target, so this holds the clock weakly and
  /// ends the link once the clock is gone.
  @MainActor
  private final class FrameTarget: NSObject {
    weak var clock: FrameClock?

    init(clock: FrameClock) {
      self.clock = clock
    }

    @objc func fire(_ link: CADisplayLink) {
      guard let clock else {
        link.invalidate()
        return
      }
      clock.fire(at: link.timestamp)
    }
  }
#endif

/// The time between frames, logged at debug level every few seconds as the average, the slowest
/// one in twenty and the slowest, so the cost of a change can be read from a log stream.
struct FrameStats {
  private var intervals: [TimeInterval] = []
  private var started: TimeInterval?

  static let every: TimeInterval = 5
  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "NookiScene")

  mutating func add(_ interval: TimeInterval, at time: TimeInterval) {
    intervals.append(interval)
    let start = started ?? time
    started = start
    guard time - start >= Self.every, let summary = Self.summary(intervals) else { return }
    Self.log.debug(
      "mark frames \(summary.average * 1000, format: .fixed(precision: 1), privacy: .public) ms average, \(summary.slowTwentieth * 1000, format: .fixed(precision: 1), privacy: .public) ms 95th, \(summary.slowest * 1000, format: .fixed(precision: 1), privacy: .public) ms slowest"
    )
    intervals.removeAll(keepingCapacity: true)
    started = time
  }

  /// The average interval, the one slower than 95% of the others, and the slowest.
  static func summary(_ intervals: [TimeInterval]) -> (
    average: TimeInterval, slowTwentieth: TimeInterval, slowest: TimeInterval
  )? {
    guard !intervals.isEmpty else { return nil }
    let sorted = intervals.sorted()
    let index = min(Int((Double(sorted.count) * 0.95).rounded(.down)), sorted.count - 1)
    return (
      intervals.reduce(0, +) / Double(intervals.count), sorted[index], sorted[sorted.count - 1]
    )
  }
}
