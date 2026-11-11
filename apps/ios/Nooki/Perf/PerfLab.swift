import BilletKit
import Foundation
import Observation
import OSLog
import QuartzCore
import RoomInterface
import SwiftUI

/// What Labs → Performance can switch off while the app runs, to find what costs a phone its frames.
nonisolated enum PerfSuspect: String, CaseIterable, Codable, Sendable {
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
    /// The dust drifting through the room.
    case motes
    /// The cat drawn as 131,000 splats; off, as the skinned mesh the Simulator draws. Read at launch.
    case splatCat
    /// The room swaying under the sun and the bulbs and flame pulsing; off, a still room.
    case sway
    /// Four samples a pixel on the room's edges.
    case msaa
    /// The room drawn in the wide colour range; off, the standard one.
    case hdr
    /// The room drawn by our own renderer and frame loop, at 30 frames a second when nothing moves and none when it
    /// is not on screen, in place of RealityView. A spike; read at launch.
    case ownLoop

    var title: String {
        switch self {
        case .barGlass: "Glass header and tab bar"
        case .pageGlass: "Glass inside pages"
        case .scrollEdges: "Soft scroll edges"
        case .shadows: "Shadows"
        case .shine: "Shine on rare cards"
        case .flatten: "Flatten prints and cards"
        case .motes: "Dust motes in the room"
        case .splatCat: "Cat as splats (mesh when off; next launch)"
        case .sway: "Room sway and light pulse"
        case .msaa: "Antialiasing (4 samples)"
        case .hdr: "HDR rendering"
        case .ownLoop: "Room on its own 30 fps loop (spike; next launch)"
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
        case .motes: "sparkle"
        case .splatCat: "cat"
        case .sway: "waveform.path"
        case .msaa: "square.dashed"
        case .hdr: "sun.max"
        case .ownLoop: "gauge.with.dots.needle.33percent"
        }
    }

    /// `flatten` is an extra step, not something shipped; the dust and the antialiasing are cut, and start off. The
    /// others start on.
    var shippedOn: Bool {
        switch self {
        case .barGlass, .pageGlass, .scrollEdges, .shadows, .shine, .splatCat, .sway, .hdr: true
        case .flatten, .motes, .msaa, .ownLoop: false
        }
    }
}

/// The Performance lab: which suspects are switched against how the app ships, and whether the frame meter shows.
nonisolated enum PerfLabMachine: Machine {
    static let saveKey = "labs.perf"

    struct State: Equatable, Codable, Sendable {
        /// The suspects set the other way from how they ship.
        var changed: Set<PerfSuspect> = []
        var meter = false

        static let shipped = State()

        /// What Labs saved on this phone; where a part of the app reads a switch before the lab itself exists.
        static func saved(in defaults: UserDefaults) -> State {
            defaults.data(forKey: PerfLabMachine.saveKey)
                .flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? .shipped
        }

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
    static func summary(_ state: State, reading: FrameStats?, energy: EnergyStats? = nil,
                        tabs: TabSwitchTimes? = nil, day: MetricsDigest? = nil) -> String {
        let changed = PerfSuspect.allCases.filter { state.changed.contains($0) }
            .map { "\($0.rawValue) \(state.isOn($0) ? "on" : "off")" }
        let switches = changed.isEmpty ? "as shipped" : changed.joined(separator: ", ")
        return (["Perf lab: \(switches)"] + [reading?.line, energy?.line, tabs?.line, day?.line].compactMap { $0 })
            .joined(separator: " · ")
    }
}

/// The frames of a moment, from the screen's own timestamps.
nonisolated struct FrameStats: Equatable, Sendable {
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

/// What warms the phone: the app's CPU, whether the room draws, and how the system rates its own heat.
nonisolated struct EnergyStats: Equatable, Sendable {
    enum Room: String, Sendable {
        /// On screen and drawing.
        case drawing
        /// Under a sheet or a cover, held still.
        case paused
        /// On another tab or in the background, nothing to draw.
        case off
    }

    enum Heat: String, Sendable {
        case nominal, fair, serious, critical
    }

    /// The app's CPU over the last sample, summed over its threads: 100 is one core kept busy.
    var cpu: Double
    var room: Room
    var heat: Heat
    var lowPower: Bool
    /// The busiest threads over the last sample, busiest first.
    var threads: [ThreadLoad] = []
    var battery: BatteryDrain?
    /// How long after the app started the phone first left nominal.
    var secondsToFair: Double?

    /// `busy` is the app's total CPU time in seconds, read at two moments `elapsed` seconds apart.
    static func cpu(busy from: Double, _ to: Double, elapsed: Double) -> Double? {
        guard elapsed > 0, to >= from else { return nil }
        return (to - from) / elapsed * 100
    }

    var line: String {
        let base = "CPU \(Int(cpu.rounded()))% · room \(room.rawValue) · \(heat.rawValue)\(lowPower ? " · low power" : "")"
        let threadsLine = threads.isEmpty ? nil : "threads " + threads.map(\.line).joined(separator: ", ")
        let fair = secondsToFair.map { String(format: "fair after %.0f min", $0 / 60) }
        return ([base, fair, battery?.line, threadsLine].compactMap { $0 }).joined(separator: " · ")
    }
}

/// One thread's share of the app's CPU over a moment: 100 is one core.
nonisolated struct ThreadLoad: Equatable, Sendable {
    nonisolated struct Sample: Equatable, Sendable {
        var id: UInt64
        var name: String
        /// CPU time the thread has used, in seconds.
        var seconds: Double
    }

    var name: String
    var cpu: Double

    /// The `count` busiest threads between two readings `elapsed` seconds apart; a thread in only one of them, or
    /// under one point, is left out.
    static func busiest(from: [Sample], to: [Sample], elapsed: Double, count: Int = 3) -> [ThreadLoad] {
        guard elapsed > 0 else { return [] }
        let before = Dictionary(from.map { ($0.id, $0.seconds) }, uniquingKeysWith: { first, _ in first })
        return to.compactMap { sample -> ThreadLoad? in
            guard let was = before[sample.id], sample.seconds >= was else { return nil }
            let cpu = (sample.seconds - was) / elapsed * 100
            return cpu >= 1 ? ThreadLoad(name: sample.name, cpu: cpu) : nil
        }
        .sorted { $0.cpu > $1.cpu }
        .prefix(count)
        .map { $0 }
    }

    var line: String { "\(name) \(Int(cpu.rounded()))" }
}

/// What the battery lost per ten minutes while unplugged: the one number that includes the GPU, the display and the
/// radios. It counts from the moment the phone was last unplugged or the level last rose, and shows after five minutes.
nonisolated struct BatteryDrain: Equatable, Sendable {
    static let minimumSeconds = 300.0

    /// Percentage points lost per ten minutes.
    var per10Minutes: Double
    var minutes: Double

    var line: String { String(format: "battery -%.1f%%/10 min over %.0f min", per10Minutes, minutes) }
}

nonisolated struct BatteryTrack: Equatable, Sendable {
    private struct Point: Equatable, Sendable {
        var level: Double
        var at: Double
    }

    private var start: Point?
    private var latest: Point?

    /// `level` is 0...1, negative when the system does not say; `at` is in seconds.
    mutating func record(level: Double, charging: Bool, at: Double) {
        guard level >= 0, !charging else {
            start = nil
            latest = nil
            return
        }
        if let start, level > start.level { self.start = nil }
        if start == nil { start = Point(level: level, at: at) }
        latest = Point(level: level, at: at)
    }

    var drain: BatteryDrain? {
        guard let start, let latest, latest.at - start.at >= BatteryDrain.minimumSeconds else { return nil }
        let seconds = latest.at - start.at
        return BatteryDrain(per10Minutes: (start.level - latest.level) * 100 / seconds * 600, minutes: seconds / 60)
    }
}

/// Seconds from the first reading, taken at launch, to the first one above nominal. A phone already warm at launch
/// says nothing about the app, so it never reports.
nonisolated struct ThermalClock: Equatable, Sendable {
    private var first: Double?
    private var warmAtStart = false
    private(set) var secondsToFair: Double?

    mutating func record(_ heat: EnergyStats.Heat, at: Double) {
        guard let first else {
            first = at
            warmAtStart = heat != .nominal
            return
        }
        guard secondsToFair == nil, !warmAtStart, heat != .nominal else { return }
        secondsToFair = at - first
    }
}

/// MetricKit's day for this build, boiled down: how much of the foreground the GPU and CPU were busy and how often a
/// frame was late. The system delivers it about once a day, for the day before.
nonisolated struct MetricsDigest: Equatable, Codable, Sendable {
    var gpuSeconds: Double
    var cpuSeconds: Double
    var foregroundSeconds: Double
    /// Seconds of late frames per second of animation, where the system reports it.
    var hitchRatio: Double?
    var day: Date

    /// Percent of the foreground the GPU was busy, or nil with no foreground time.
    var gpuDuty: Double? { foregroundSeconds > 0 ? gpuSeconds / foregroundSeconds * 100 : nil }
    var cpuDuty: Double? { foregroundSeconds > 0 ? cpuSeconds / foregroundSeconds * 100 : nil }

    var line: String? {
        guard let gpuDuty, let cpuDuty else { return nil }
        let hitch = hitchRatio.map { String(format: ", hitch %.1f ms/s", $0 * 1000) } ?? ""
        return String(format: "day GPU %.0f%% (%.0f min), CPU %.0f%% of %.0f min foreground%@", gpuDuty,
                      gpuSeconds / 60, cpuDuty, foregroundSeconds / 60, hitch)
    }
}

extension EnergyStats.Room {
    init(_ visibility: RoomVisibility) {
        switch visibility {
        case .visible: self = .drawing
        case .covered: self = .paused
        case .hidden: self = .off
        }
    }
}

/// How long the last tab switches took, from the tap to the first frame of the new tab on screen.
nonisolated struct TabSwitchTimes: Equatable, Sendable {
    static let kept = 20

    /// Milliseconds, oldest first; at most `kept`.
    private(set) var recent: [Double] = []

    mutating func add(_ milliseconds: Double) {
        recent.append(milliseconds)
        if recent.count > Self.kept { recent.removeFirst(recent.count - Self.kept) }
    }

    var last: Double? { recent.last }
    var p50: Double? { percentile(0.5) }
    var p95: Double? { percentile(0.95) }

    /// The nearest-rank percentile.
    private func percentile(_ p: Double) -> Double? {
        guard !recent.isEmpty else { return nil }
        let sorted = recent.sorted()
        return sorted[max(0, Int((Double(sorted.count) * p).rounded(.up)) - 1)]
    }

    var line: String? {
        guard let last, let p50, let p95 else { return nil }
        return String(format: "tab %.0f ms, p50 %.0f, p95 %.0f of %d", last, p50, p95, recent.count)
    }
}

/// Times each tab switch to its first frame on screen: an os_signpost interval for Instruments, a log line, and
/// ``TabSwitchTimes`` for Labs. The state change and the tap that made it run in the same turn of the main loop, and
/// the new tab is built and committed before the display link next fires, so that fire's target time, or the moment
/// it fires if later, is when the first frame with the new tab is shown.
@MainActor
@Observable
final class TabSwitchClock {
    private(set) var times = TabSwitchTimes()

    @ObservationIgnored private let signposter = OSSignposter(subsystem: "com.ourio.app", category: "tabs")
    @ObservationIgnored private let log = Logger(subsystem: "com.ourio.app", category: "tabs")
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var target = TabSwitchLinkTarget()
    @ObservationIgnored private var started: (at: CFTimeInterval, tab: String, interval: OSSignpostIntervalState)?

    func began(_ tab: String) {
        link?.invalidate()
        if let started { signposter.endInterval("tab switch", started.interval, "cut short") }
        started = (CACurrentMediaTime(), tab, signposter.beginInterval("tab switch", id: signposter.makeSignpostID(),
                                                                       "\(tab)"))
        target.tick = { [weak self] link in self?.shown(link) }
        let link = CADisplayLink(target: target, selector: #selector(TabSwitchLinkTarget.frame))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func shown(_ link: CADisplayLink) {
        link.invalidate()
        self.link = nil
        guard let started else { return }
        self.started = nil
        // A main thread held up past a frame calls the link late, with the target of the frame it missed.
        let milliseconds = (max(link.targetTimestamp, CACurrentMediaTime()) - started.at) * 1000
        signposter.endInterval("tab switch", started.interval)
        log.info("tab switch \(started.tab, privacy: .public) \(milliseconds, format: .fixed(precision: 0)) ms")
        times.add(milliseconds)
    }
}

/// A display link holds its target strongly; this keeps that target from being the clock.
private final class TabSwitchLinkTarget: NSObject {
    var tick: (CADisplayLink) -> Void = { _ in }

    @objc func frame(_ link: CADisplayLink) { tick(link) }
}

/// Runs ``PerfLabMachine`` and keeps its state on this phone.
@MainActor
@Observable
final class PerfLab {
    static let key = PerfLabMachine.saveKey

    private let store: Store<PerfLabMachine>

    var state: PerfLabMachine.State { store.state }

    /// MetricKit's latest day for this build, once the system has delivered one.
    private(set) var day: MetricsDigest?
    #if DEBUG || LABS_YES
    @ObservationIgnored let energy = EnergyMeter()
    @ObservationIgnored private var metrics: MetricsReceiver?
    @ObservationIgnored private var sampling: Task<Void, Never>?
    #endif

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
        #if DEBUG || LABS_YES
        SplatLoader.setMeshOnly(!saved.isOn(.splatCat))
        day = MetricsReceiver.saved(in: defaults)
        let receiver = MetricsReceiver(defaults: defaults) { [weak self] digest in self?.day = digest }
        receiver.start()
        metrics = receiver
        // Started with the app, not with the meter: the time to a warm phone and the battery's slope run from launch.
        sampling = Task { @MainActor [energy] in
            while !Task.isCancelled {
                energy.sample()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        #endif
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
