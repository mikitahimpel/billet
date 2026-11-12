import Foundation
import Observation
import QuartzCore
import notify

/// One frame the probe saw: how long after the frame before it, and when it ended, in seconds since launch.
struct ProbeFrame: Equatable {
  let gap: TimeInterval
  let at: TimeInterval
}

/// Which frames came late. A frame is late when its gap is longer than two frames at 60 Hz: at least one frame was
/// dropped on top of the late one. Only frames whose gap began at or after `start` count: before it the main thread
/// is the UI test harness's as much as the app's.
enum HitchRule {
  static let gap: TimeInterval = 2.1 / 60

  static func late(_ frames: [ProbeFrame], from start: TimeInterval) -> [ProbeFrame] {
    frames.filter { $0.at - $0.gap >= start && $0.gap > gap }
  }

  static func counted(_ frames: [ProbeFrame], from start: TimeInterval) -> Int {
    frames.filter { $0.at - $0.gap >= start }.count
  }

  /// A frame this late is a stall anyone sees.
  static let stall: TimeInterval = 0.1
  /// Late frames a shared CI runner adds on its own: main's runs show up to 3 of 41-66 ms on a script that has
  /// none locally. Tighter budgets are perf.yml's A/B, on one runner for both builds.
  static let lateBudget = 5

  /// Whether the welcome visibly janks: a stall, or more late frames than the runner's own.
  static func janks(_ late: [ProbeFrame]) -> Bool {
    late.contains { $0.gap > stall } || late.count > lateBudget
  }
}

/// Counts frames that came late while the welcome timeline plays, and how long the first one took. The UI test reads
/// it through `welcome.probe`, and measure.sh's welcome runs read its `PERF` lines; it is created only with the
/// `-uitestWelcomeProbe` launch argument.
@MainActor
@Observable
final class HitchProbe {
  /// Set once, when the timeline has played. Until then nothing here is observed, so counting a frame never
  /// re-evaluates a view or changes the accessibility tree.
  private(set) var summary: String?

  @ObservationIgnored private var firstFrameMs: Int?
  @ObservationIgnored private let created = CACurrentMediaTime()
  @ObservationIgnored private var last: Date?
  @ObservationIgnored private var frames: [ProbeFrame] = []
  /// Seconds since launch from which late frames count.
  @ObservationIgnored private var start = HitchProbe.harnessSettle
  @ObservationIgnored private var token: Int32 = NOTIFY_TOKEN_INVALID
  /// Called when the harness is done, so the welcome plays its script again from the start, all of it measured.
  @ObservationIgnored var restart: () -> Void = {}

  /// Posted by the UI test once `XCUIApplication.launch()` has returned. Until then XCUITest waits for the app to
  /// idle and snapshots its accessibility tree on the app's main thread: frames of 120-360 ms of its own, for up to
  /// a second on a CI runner.
  static let harnessDone = "com.ourio.app.uitest.launched"

  /// Without the UI test (measure.sh's plain launches): seconds after launch before late frames count.
  static let harnessSettle: TimeInterval = 0.5

  /// Seconds after the restart before late frames count. The restart builds the script's first frame again (its
  /// images and the clip's player), work a launch does before its first frame, which `firstFrameMs` budgets; on CI's
  /// iPhone SE it is one 49 ms frame 0.17 s in.
  static let restartSettle: TimeInterval = 0.25

  init(waitsForHarness: Bool = false) {
    guard waitsForHarness else { return }
    start = .infinity
    notify_register_dispatch(Self.harnessDone, &token, .main) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.start == .infinity else { return }
        self.start = CACurrentMediaTime() - self.created + Self.restartSettle
        self.restart()
      }
    }
  }

  func frame(_ now: Date) {
    guard summary == nil else { return }
    let elapsed = CACurrentMediaTime() - created
    if firstFrameMs == nil { firstFrameMs = Int(elapsed * 1000) }
    if let last { frames.append(ProbeFrame(gap: now.timeIntervalSince(last), at: elapsed)) }
    last = now
  }

  func finish() {
    guard summary == nil, start.isFinite else { return }
    if token != NOTIFY_TOKEN_INVALID { notify_cancel(token) }
    let lateFrames = HitchRule.late(frames, from: start)
    let late = lateFrames.map { "\(Int($0.gap * 1000))@\(Int($0.at * 1000))" }
    let startMs = start.isFinite ? Int(start * 1000) : -1
    let summary =
      "janks=\(HitchRule.janks(lateFrames) ? 1 : 0) hitches=\(late.count)"
      + " frames=\(HitchRule.counted(frames, from: start)) firstFrameMs=\(firstFrameMs ?? -1) startMs=\(startMs)"
      + " late=\(late.joined(separator: ","))"
    self.summary = summary
    FileHandle.standardError.write(Data("\nPERF phase welcome \(summary)\nPERF done\n".utf8))
  }
}
