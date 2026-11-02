import Foundation

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
