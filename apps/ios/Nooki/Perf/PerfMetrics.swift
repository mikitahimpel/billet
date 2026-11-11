#if DEBUG || LABS_YES
import Foundation
import MetricKit

/// Receives MetricKit's daily payloads, the only numbers that include the GPU's time on a phone away from a Mac.
/// The system delivers them on a background queue about once a day, for the day before.
final class MetricsReceiver: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let key = "labs.perf.metrics"
    private static let file = "metrickit-latest.json"

    private let defaults: UserDefaults
    private let changed: @MainActor @Sendable (MetricsDigest) -> Void

    init(defaults: UserDefaults, changed: @escaping @MainActor @Sendable (MetricsDigest) -> Void) {
        self.defaults = defaults
        self.changed = changed
    }

    func start() {
        MXMetricManager.shared.add(self)
        receive(MXMetricManager.shared.pastPayloads)
    }

    func didReceive(_ payloads: [MXMetricPayload]) { receive(payloads) }

    private func receive(_ payloads: [MXMetricPayload]) {
        guard let latest = payloads.max(by: { $0.timeStampEnd < $1.timeStampEnd }) else { return }
        let digest = Self.digest(latest)
        defaults.set(try? JSONEncoder().encode(digest), forKey: Self.key)
        try? latest.jsonRepresentation().write(to: Self.fileURL, options: .atomic)
        Task { @MainActor [changed] in changed(digest) }
    }

    static func digest(_ payload: MXMetricPayload) -> MetricsDigest {
        func seconds(_ measurement: Measurement<UnitDuration>?) -> Double {
            measurement?.converted(to: .seconds).value ?? 0
        }
        var hitch = payload.animationMetrics.map { $0.scrollHitchTimeRatio.value }
        if #available(iOS 26, *), let ratio = payload.animationMetrics?.hitchTimeRatio.value { hitch = ratio }
        return MetricsDigest(
            gpuSeconds: seconds(payload.gpuMetrics?.cumulativeGPUTime),
            cpuSeconds: seconds(payload.cpuMetrics?.cumulativeCPUTime),
            foregroundSeconds: seconds(payload.applicationTimeMetrics?.cumulativeForegroundTime),
            hitchRatio: hitch, day: payload.timeStampEnd)
    }

    static func saved(in defaults: UserDefaults) -> MetricsDigest? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(MetricsDigest.self, from: $0) }
    }

    /// The whole payload as MetricKit wrote it, for pasting into a message.
    static func savedJSON() -> String? {
        (try? Data(contentsOf: fileURL)).map { String(decoding: $0, as: UTF8.self) }
    }

    private static var fileURL: URL {
        URL.cachesDirectory.appending(path: file)
    }
}
#endif
