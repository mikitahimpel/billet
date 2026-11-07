import Foundation
import QuartzCore
import Observation

/// Counts frames that came late while the welcome timeline plays, and how long the first one took. The UI test reads
/// it through `welcome.probe`; it is created only with the `-uitestWelcomeProbe` launch argument.
@MainActor
@Observable
final class HitchProbe {
    private(set) var hitches = 0
    private(set) var frames = 0
    private(set) var firstFrameMs: Int?

    @ObservationIgnored private let created = CACurrentMediaTime()
    @ObservationIgnored private var last: Date?

    /// A gap longer than two frames at 60 Hz: at least one frame was dropped on top of the late one.
    static let hitchGap: TimeInterval = 2.1 / 60

    func frame(_ now: Date) {
        frames += 1
        if firstFrameMs == nil { firstFrameMs = Int((CACurrentMediaTime() - created) * 1000) }
        if let last, now.timeIntervalSince(last) > Self.hitchGap { hitches += 1 }
        last = now
    }

    var summary: String { "hitches=\(hitches) frames=\(frames) firstFrameMs=\(firstFrameMs ?? -1)" }
}
