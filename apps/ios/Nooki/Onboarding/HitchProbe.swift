import Foundation
import QuartzCore
import Observation

/// Counts frames that came late while the welcome timeline plays, and how long the first one took. The UI test reads
/// it through `welcome.probe`, and measure.sh's welcome runs read its `PERF` lines; it is created only with the
/// `-uitestWelcomeProbe` launch argument.
/// Which frames came late. A frame is late when its gap is over two of the display's frames, so at least one frame
/// was dropped on top of the late one. The display's frame is the run's median gap: a Simulator without a GPU draws
/// at 20-30 Hz, where a fixed 60 Hz gap would call every frame late or, near it, a few at random. The floor keeps the
/// 60 Hz gap on faster displays, where a 120 Hz frame's double is shorter than anyone sees; past the ceiling a frame
/// is a stall at any rate.
enum HitchRule {
    static let floor: TimeInterval = 2.1 / 60
    static let ceiling: TimeInterval = 0.1
    static let dropped = 2.1

    static func cadence(_ gaps: [TimeInterval]) -> TimeInterval {
        guard !gaps.isEmpty else { return 0 }
        let sorted = gaps.sorted()
        return sorted[sorted.count / 2]
    }

    static func limit(_ gaps: [TimeInterval]) -> TimeInterval {
        min(ceiling, max(floor, dropped * cadence(gaps)))
    }

    /// The indexes of the late gaps.
    static func late(_ gaps: [TimeInterval]) -> [Int] {
        let limit = limit(gaps)
        return gaps.indices.filter { gaps[$0] > limit }
    }
}

@MainActor
@Observable
final class HitchProbe {
    /// Set once, when the timeline has played. Until then nothing here is observed, so counting a frame never
    /// re-evaluates a view or changes the accessibility tree.
    private(set) var summary: String?

    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var firstFrameMs: Int?
    @ObservationIgnored private let created = CACurrentMediaTime()
    @ObservationIgnored private var last: Date?
    /// Each counted frame's gap since the one before, and seconds since launch when it ended.
    @ObservationIgnored private var gaps: [(gap: TimeInterval, at: TimeInterval)] = []

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
        if let last { gaps.append((now.timeIntervalSince(last), elapsed)) }
    }

    func finish() {
        guard summary == nil else { return }
        let intervals = gaps.map(\.gap)
        let late = HitchRule.late(intervals).map { "\(Int(gaps[$0].gap * 1000))@\(Int(gaps[$0].at * 1000))" }
        let summary = "hitches=\(late.count) frames=\(frames) firstFrameMs=\(firstFrameMs ?? -1)"
            + " cadenceMs=\(Int(HitchRule.cadence(intervals) * 1000)) late=\(late.joined(separator: ","))"
        self.summary = summary
        FileHandle.standardError.write(Data("\nPERF phase welcome \(summary)\nPERF done\n".utf8))
    }
}
