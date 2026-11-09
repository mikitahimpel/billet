import Foundation
import QuartzCore
import Observation

/// Counts frames that came late while the welcome timeline plays, and how long the first one took. The UI test reads
/// it through `welcome.probe`, and measure.sh's welcome runs read its `PERF` lines; it is created only with the
/// `-uitestWelcomeProbe` launch argument.
@MainActor
@Observable
final class HitchProbe {
    /// Set once, when the timeline has played. Until then nothing here is observed, so counting a frame never
    /// re-evaluates a view or changes the accessibility tree.
    private(set) var summary: String?

    @ObservationIgnored private var hitches = 0
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var firstFrameMs: Int?
    @ObservationIgnored private let created = CACurrentMediaTime()
    @ObservationIgnored private var last: Date?

    /// A gap longer than two frames at 60 Hz: at least one frame was dropped on top of the late one.
    static let hitchGap: TimeInterval = 2.1 / 60

    /// Seconds after launch before late frames count. An XCUITest launch waits for the app to idle and snapshots its
    /// accessibility tree on the main thread in this window, a 120-160 ms frame of the harness's own; launched
    /// without XCUITest the same build has no such frame. Frames ending after it count, even if they started before.
    static let harnessSettle: TimeInterval = 0.5

    func frame(_ now: Date) {
        guard summary == nil else { return }
        let elapsed = CACurrentMediaTime() - created
        if firstFrameMs == nil { firstFrameMs = Int(elapsed * 1000) }
        defer { last = now }
        guard elapsed >= Self.harnessSettle else { return }
        frames += 1
        if let last, now.timeIntervalSince(last) > Self.hitchGap { hitches += 1 }
    }

    func finish() {
        guard summary == nil else { return }
        let summary = "hitches=\(hitches) frames=\(frames) firstFrameMs=\(firstFrameMs ?? -1)"
        self.summary = summary
        FileHandle.standardError.write(Data("\nPERF phase welcome \(summary)\nPERF done\n".utf8))
    }
}
