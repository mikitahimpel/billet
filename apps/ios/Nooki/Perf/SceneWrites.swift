import Foundation

/// What the scenes write per second while nothing moves, counted where they write. Labs → Performance reads it; the
/// release build keeps the call sites and drops the counting.
enum SceneWrite: String, CaseIterable, Sendable {
    case hourRead, hourSample, clockHands, lights, ambient, shellTint, windowProject
    case flameScale, candleLight, bulbScale, catBodyScale
}

#if DEBUG || LABS_YES
@MainActor
enum SceneWrites {
    private static var counts: [SceneWrite: Int] = [:]
    private static var since = Date()

    static func note(_ write: SceneWrite, _ times: Int = 1) { counts[write, default: 0] += times }

    /// Per-second rates since the last call, and starts over.
    static func drainRates(now: Date = .now) -> [String] {
        let seconds = max(now.timeIntervalSince(since), 0.001)
        defer {
            counts = [:]
            since = now
        }
        let parts = SceneWrite.allCases.compactMap { write in
            counts[write].map { "\(write.rawValue) \(String(format: "%.1f", Double($0) / seconds))" }
        }
        guard !parts.isEmpty else { return [] }
        return ["scene writes/s over \(Int(seconds.rounded())) s: " + parts.joined(separator: ", ")]
    }
}
#else
@MainActor
enum SceneWrites {
    @inline(__always) static func note(_ write: SceneWrite, _ times: Int = 1) {}
}
#endif
