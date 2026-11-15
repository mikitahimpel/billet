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
    /// The warm bokeh drifting behind the room, redrawn at 10 Hz under the room layer and the glass; off, it holds still.
    case drift
    /// The cat's splats cut to about 55%, the least important first. Read when she loads.
    case splatLean
    /// The cat's splats rewritten and re-sorted at most 30 times a second instead of every frame.
    case splatRate
    /// The room swaying under the sun and the bulbs and flame pulsing; off, a still room.
    case sway
    /// Four samples a pixel on the room's edges.
    case msaa
    /// The room drawn in the wide colour range; off, the standard one.
    case hdr
    /// The room drawn by our own renderer and frame loop, at 30 frames a second when nothing moves and none when it
    /// is not on screen, in place of RealityView. On; off puts the room back on RealityView. Read at launch.
    case ownLoop
    /// Metal's performance overlay (fps, GPU ms) over the app; read at launch, off unless switched on.
    case metalHud
    /// The room's static furniture drawn as one mesh per material while the player is not arranging it.
    case mergeFurniture
    /// The blobs under the pieces drawn as one baked layer while the player is not arranging.
    case bakedBlobs
    /// The sun's shadow map left out, so the room is not drawn a second time from the light.
    case noSunShadow
    /// Each room's widest point light kept and the others off.
    case fewerLights
    /// The bloom pass over the glowing bulbs, flame and window left out (iOS 27 only).
    case noBloom
    /// The rooms' boxes and spheres drawn as RealityKit makes them, 13,068 triangles a box and 8,064 a sphere, in place
    /// of the facets their size on screen can show. The furniture models are the lean ones either way.
    case fullMeshes

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
        case .drift: "Backdrop bokeh drift"
        case .splatLean: "Cat splats cut to 55% (next launch)"
        case .splatRate: "Cat splats updated at 30 Hz"
        case .sway: "Room sway and light pulse"
        case .msaa: "Antialiasing (4 samples)"
        case .hdr: "HDR rendering"
        case .ownLoop: "Room on its own capped frame loop (off: RealityView; next launch)"
        case .metalHud: "Metal HUD overlay (fps, GPU; next launch)"
        case .mergeFurniture: "Furniture merged per material (outside Decorate)"
        case .bakedBlobs: "One baked contact-shadow layer (outside Decorate)"
        case .noSunShadow: "No sun shadow map"
        case .fewerLights: "Only the widest point light"
        case .noBloom: "No bloom (iOS 27)"
        case .fullMeshes: "Full-detail boxes and spheres (RealityKit's)"
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
        case .drift: "circle.dotted"
        case .splatLean: "scissors"
        case .splatRate: "metronome"
        case .sway: "waveform.path"
        case .msaa: "square.dashed"
        case .hdr: "sun.max"
        case .ownLoop: "gauge.with.dots.needle.33percent"
        case .metalHud: "chart.xyaxis.line"
        case .mergeFurniture: "square.on.square.squareshape.controlhandles"
        case .bakedBlobs: "circle.lefthalf.filled"
        case .noSunShadow: "sun.min"
        case .fewerLights: "lightbulb.slash"
        case .noBloom: "light.max"
        case .fullMeshes: "cube"
        }
    }

    /// `flatten` is an extra step, not something shipped; the dust and the antialiasing are cut, and start off. The
    /// others start on.
    var shippedOn: Bool {
        switch self {
        case .barGlass, .pageGlass, .scrollEdges, .shadows, .shine, .splatCat, .drift, .sway, .hdr: true
        case .flatten, .motes, .msaa, .ownLoop, .metalHud, .splatLean, .splatRate, .mergeFurniture, .bakedBlobs,
            .noSunShadow, .fewerLights, .noBloom, .fullMeshes: false
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
        /// The quality tier Labs holds the room at, or nil to follow the phone's heat. Not saved: a forced `critical`
        /// holds the room still, and it must not outlive the session that asked for it.
        var forcedTier: RoomQualityTier?

        private enum CodingKeys: String, CodingKey { case changed, meter }

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
        case force(RoomQualityTier?)
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
        case .force(let tier):
            guard state.forcedTier != tier else { return (state, []) }
            next.forcedTier = tier
        case .reset:
            guard state != .shipped else { return (state, []) }
            next = .shipped
        }
        return (next, [.save(next)])
    }

    /// One line to paste into a message: what is switched and the meter's last reading.
    static func summary(_ state: State, reading: FrameStats?, energy: EnergyStats? = nil,
                        tabs: TabSwitchTimes? = nil, day: MetricsDigest? = nil, room: String? = nil,
                        governor: String? = nil) -> String {
        let changed = PerfSuspect.allCases.filter { state.changed.contains($0) }
            .map { "\($0.rawValue) \(state.isOn($0) ? "on" : "off")" }
        let forced = state.forcedTier.map { "tier \($0.title) forced" }
        let switches = changed.isEmpty && forced == nil ? "as shipped" : (changed + [forced].compactMap { $0 }).joined(separator: ", ")
        return (["Perf lab: \(switches)"] + [reading?.line, energy?.line, tabs?.line, day?.line, room, governor].compactMap { $0 })
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

/// Follows the phone's heat, Low Power Mode, battery and how long the room has been left alone, and says which
/// ``RoomQualityTier`` the room should draw at, degrading at once and recovering slowly (``RoomQualityPolicy``). It reads
/// when the system says something changed and every two seconds besides, for the quiet.
@MainActor
@Observable
final class QualityMonitor {
    private(set) var tier: RoomQualityTier
    private(set) var conditions: RoomConditions
    private(set) var reason: RoomConditions.Reason = .none
    private(set) var recovering = false

    /// Seconds since the room was touched or moved, and whether a change of look would show; the room's own reading.
    @ObservationIgnored var quiet: (@MainActor () -> (idle: TimeInterval, busy: Bool))?
    /// Called after the tier changed.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    @ObservationIgnored private var policy: RoomQualityPolicy
    @ObservationIgnored private let info: ProcessInfo
    @ObservationIgnored private let device: UIDevice
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init(info: ProcessInfo = .processInfo, device: UIDevice = .current) {
        self.info = info
        self.device = device
        device.isBatteryMonitoringEnabled = true
        let conditions = Self.read(info, device, quiet: nil)
        var policy = RoomQualityPolicy()
        tier = policy.update(conditions, at: info.systemUptime)
        reason = policy.reason
        self.conditions = conditions
        self.policy = policy
        let names: [Notification.Name] = [
            ProcessInfo.thermalStateDidChangeNotification, .NSProcessInfoPowerStateDidChange,
            UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification,
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
        }
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.sample()
            }
        }
    }

    func sample() {
        let now = Self.read(info, device, quiet: quiet?())
        if now != conditions { conditions = now }
        let next = policy.update(now, at: info.systemUptime)
        if policy.reason != reason { reason = policy.reason }
        if policy.isRecovering != recovering { recovering = policy.isRecovering }
        if next != tier {
            tier = next
            onChange?()
        }
    }

    private static func read(_ info: ProcessInfo, _ device: UIDevice, quiet: (idle: TimeInterval, busy: Bool)?)
        -> RoomConditions
    {
        var conditions = RoomConditions(info)
        if device.batteryLevel >= 0, device.batteryState != .unknown {
            conditions.battery = .init(
                level: Double(device.batteryLevel),
                charging: device.batteryState == .charging || device.batteryState == .full)
        }
        if let quiet {
            conditions.idle = quiet.idle
            conditions.busy = quiet.busy
        }
        return conditions
    }
}

/// What Labs → Performance and the copy line say about the quality governor, as text.
nonisolated enum GovernorReadout {
    static func why(_ reason: RoomConditions.Reason, recovering: Bool, forced: Bool) -> String {
        if forced { return "forced in Labs" }
        let asked: String =
            switch reason {
            case .none: "nothing asks for less"
            case .heat(let heat): "heat \(heat)"
            case .lowPower: "Low Power Mode"
            case .battery: "low battery"
            case .idle: "room left alone"
            }
        return recovering ? "\(asked), recovering" : asked
    }

    static func inputs(_ c: RoomConditions) -> String {
        let battery = c.battery.map { "\(Int(($0.level * 100).rounded()))% \($0.charging ? "charging" : "unplugged")" } ?? "unknown"
        return "heat \(c.heat), low power \(c.lowPower ? "on" : "off"), battery \(battery), idle \(Int(c.idle)) s, "
            + "busy \(c.busy ? "yes" : "no")"
    }

    static func plan(_ p: RoomQualityPlan) -> String {
        func on(_ flag: Bool) -> String { flag ? "on" : "off" }
        let scale = String(format: "%g", p.scale)
        let slow = String(format: "%g", p.pulseSlowdown)
        return "\(p.activeRate)/\(p.idleRate) fps, \(scale)x, bloom \(on(p.bloom)), sun shadow \(on(p.sunShadow)), "
            + "lights \(p.widestLightOnly ? "widest" : "all"), hdr \(on(p.hdr)), ambient +\(String(format: "%g", p.ambientLift)), "
            + "pulse x\(slow)\(p.still ? ", still" : "")"
    }

    /// One line for Copy settings.
    static func line(tier: RoomQualityTier, forced: Bool, reason: String, changes: Int) -> String {
        "governor \(tier.title)\(forced ? " (forced)" : "") (\(reason)), \(changes) changes"
    }
}

/// Runs ``PerfLabMachine`` and keeps its state on this phone.
@MainActor
@Observable
final class PerfLab {
    static let key = PerfLabMachine.saveKey

    private let store: Store<PerfLabMachine>

    var state: PerfLabMachine.State { store.state }

    @ObservationIgnored let quality = QualityMonitor()
    /// How many times the tier the room draws at has changed since launch, by the phone or by Labs.
    private(set) var tierChanges = 0
    @ObservationIgnored private var lastTier: RoomQualityTier?

    /// The tier the room draws at: the one Labs forces, else the one the phone's heat and power ask for.
    var tier: RoomQualityTier { state.forcedTier ?? quality.tier }

    /// MetricKit's latest day for this build, once the system has delivered one.
    private(set) var day: MetricsDigest?
    #if DEBUG || LABS_YES
    @ObservationIgnored let energy = EnergyMeter()
    /// Counts of the visible room's live scene, read when Labs asks (set by the screen that owns the room).
    @ObservationIgnored var statsSource: (@MainActor (RoomQualityTier) -> RoomStats?)?
    private(set) var roomStats: RoomStats?
    private(set) var previousStats: RoomStats?
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
        lastTier = tier
        quality.onChange = { [weak self] in self?.noteTier() }
    }

    func isOn(_ suspect: PerfSuspect) -> Bool { state.isOn(suspect) }

    #if DEBUG || LABS_YES
    /// Walks the room again; the reading before it is kept to show what changed.
    func refreshRoomStats() {
        guard let stats = statsSource?(tier) else { return }
        if stats != roomStats { previousStats = roomStats }
        roomStats = stats
    }
    #endif

    func binding(_ suspect: PerfSuspect) -> Binding<Bool> {
        Binding { self.isOn(suspect) } set: { self.store.send(.set(suspect, on: $0)) }
    }

    var meter: Binding<Bool> {
        Binding { self.state.meter } set: { self.store.send(.meter($0)) }
    }

    func force(_ tier: RoomQualityTier?) {
        store.send(.force(tier))
        noteTier()
    }

    private func noteTier() {
        let now = self.tier
        if let lastTier, lastTier != now { tierChanges += 1 }
        lastTier = now
    }

    var governorLine: String {
        GovernorReadout.line(
            tier: tier, forced: state.forcedTier != nil,
            reason: GovernorReadout.why(quality.reason, recovering: quality.recovering, forced: state.forcedTier != nil),
            changes: tierChanges)
    }

    func reset() { store.send(.reset) }

    func settled() async { await store.settled() }
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
}
