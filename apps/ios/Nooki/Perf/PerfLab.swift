import BilletKit
import Foundation
import Observation
import QuartzCore
import SwiftUI

/// What Labs → Performance can switch off while the app runs, to find what costs a phone its frames.
enum PerfSuspect: String, CaseIterable, Codable, Sendable {
    /// The header and the tab bar drawn as Liquid Glass; off, a flat surface.
    case barGlass
    /// Glass drawn inside pages, such as the Shop's featured card; off, a flat surface.
    case pageGlass
    /// The soft edge effect where a page scrolls under the bars.
    case scrollEdges
    /// Shadows under prints, cards, posters and the rarity glow.
    case shadows
    /// The sweep across epic and legendary shop cards.
    case shine
    /// Prints and shop cards drawn flat into one layer (`drawingGroup`), when on.
    case flatten

    var title: String {
        switch self {
        case .barGlass: "Glass header and tab bar"
        case .pageGlass: "Glass inside pages"
        case .scrollEdges: "Soft scroll edges"
        case .shadows: "Shadows"
        case .shine: "Shine on rare cards"
        case .flatten: "Flatten prints and cards"
        }
    }

    var symbol: String {
        switch self {
        case .barGlass: "rectangle.topthird.inset.filled"
        case .pageGlass: "rectangle.on.rectangle"
        case .scrollEdges: "square.bottomhalf.filled"
        case .shadows: "shadow"
        case .shine: "sparkles"
        case .flatten: "square.stack.3d.down.right"
        }
    }

    /// `flatten` is an extra step, not something shipped: it starts off, the others start on.
    var shippedOn: Bool {
        switch self {
        case .barGlass, .pageGlass, .scrollEdges, .shadows, .shine: true
        case .flatten: false
        }
    }
}

/// The Performance lab: which suspects are switched against how the app ships, and whether the frame meter shows.
nonisolated enum PerfLabMachine: Machine {
    struct State: Equatable, Codable, Sendable {
        /// The suspects set the other way from how they ship.
        var changed: Set<PerfSuspect> = []
        var meter = false

        static let shipped = State()

        func isOn(_ suspect: PerfSuspect) -> Bool { changed.contains(suspect) != suspect.shippedOn }
    }

    enum Event: Equatable, Sendable {
        case set(PerfSuspect, on: Bool)
        case meter(Bool)
        case reset
    }

    enum Output: Equatable, Sendable {
        case save(State)
    }

    static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
        var next = state
        switch event {
        case .set(let suspect, let on):
            guard state.isOn(suspect) != on else { return (state, []) }
            if on == suspect.shippedOn { next.changed.remove(suspect) } else { next.changed.insert(suspect) }
        case .meter(let shows):
            guard state.meter != shows else { return (state, []) }
            next.meter = shows
        case .reset:
            guard state != .shipped else { return (state, []) }
            next = .shipped
        }
        return (next, [.save(next)])
    }

    /// One line to paste into a message: what is switched and the meter's last reading.
    static func summary(_ state: State, reading: FrameStats?) -> String {
        let changed = PerfSuspect.allCases.filter { state.changed.contains($0) }
            .map { "\($0.rawValue) \(state.isOn($0) ? "on" : "off")" }
        let switches = changed.isEmpty ? "as shipped" : changed.joined(separator: ", ")
        guard let reading else { return "Perf lab: \(switches)" }
        return "Perf lab: \(switches) · \(reading.line)"
    }
}

/// The frames of a moment, from the screen's own timestamps.
struct FrameStats: Equatable, Sendable {
    var fps: Double
    /// The 95th percentile of the frame times, in milliseconds.
    var p95: Double
    /// Frames the screen showed late: each gap of more than 1.5 refresh intervals counts the frames it skipped.
    var dropped: Int

    /// `gaps` in seconds between frames; `interval` is the screen's refresh interval, in seconds.
    init?(gaps: [Double], interval: Double) {
        guard !gaps.isEmpty, interval > 0 else { return nil }
        let total = gaps.reduce(0, +)
        fps = Double(gaps.count) / total
        let sorted = gaps.sorted()
        p95 = sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)] * 1000
        dropped = gaps.reduce(0) { sum, gap in gap > interval * 1.5 ? sum + Int((gap / interval).rounded()) - 1 : sum }
    }

    var line: String { String(format: "%.0f fps, p95 %.1f ms, %d dropped", fps, p95, dropped) }
}

/// Runs ``PerfLabMachine`` and keeps its state on this phone.
@MainActor
@Observable
final class PerfLab {
    static let key = "labs.perf"

    private let store: Store<PerfLabMachine>

    var state: PerfLabMachine.State { store.state }

    init(defaults: UserDefaults) {
        let saved = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(PerfLabMachine.State.self, from: $0) } ?? .shipped
        // On the main actor, so saves land in the order the switches were flipped.
        store = Store(initial: saved) { @MainActor [defaults] output in
            switch output {
            case .save(let state):
                defaults.set(try? JSONEncoder().encode(state), forKey: Self.key)
            }
            return nil
        }
    }

    func isOn(_ suspect: PerfSuspect) -> Bool { state.isOn(suspect) }

    func binding(_ suspect: PerfSuspect) -> Binding<Bool> {
        Binding { self.isOn(suspect) } set: { self.store.send(.set(suspect, on: $0)) }
    }

    var meter: Binding<Bool> {
        Binding { self.state.meter } set: { self.store.send(.meter($0)) }
    }

    func reset() { store.send(.reset) }

    func settled() async { await store.settled() }
}

extension EnvironmentValues {
    /// Labs → Performance's switches the pages read; each is on as shipped.
    @Entry var perfShadows = true
    @Entry var perfShine = true
    @Entry var perfFlatten = false
}

extension View {
    /// The lab's switches for a page: its glass, shadows, shine and flattening. The bars take theirs in `HomeView`.
    func perfLab(_ lab: PerfLab) -> some View {
        environment(\.glassRendering, lab.isOn(.pageGlass) ? .liquid : .flat)
            .environment(\.softScrollEdges, lab.isOn(.scrollEdges))
            .environment(\.perfShadows, lab.isOn(.shadows))
            .environment(\.perfShine, lab.isOn(.shine))
            .environment(\.perfFlatten, lab.isOn(.flatten))
    }

    /// Drawn into one layer while the lab's Flatten switch is on.
    func perfFlattened() -> some View { modifier(PerfFlatten()) }

    /// A shadow the lab's Shadows switch can take away.
    func perfShadow(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        modifier(PerfShadow(color: color, radius: radius, x: x, y: y))
    }
}

private struct PerfShadow: ViewModifier {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
    @Environment(\.perfShadows) private var shows

    func body(content: Content) -> some View {
        content.shadow(color: shows ? color : .clear, radius: shows ? radius : 0, x: x, y: y)
    }
}

private struct PerfFlatten: ViewModifier {
    @Environment(\.perfFlatten) private var flatten

    @ViewBuilder func body(content: Content) -> some View {
        if flatten { content.drawingGroup() } else { content }
    }
}
