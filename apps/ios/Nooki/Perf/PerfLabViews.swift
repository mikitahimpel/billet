#if DEBUG || LABS_YES
import Design
import MomentsInterface
import WidgetInterface
import WidgetUI
import QuartzCore
import SwiftUI
import Darwin
import RoomInterface
import UIKit
import UsInterface

/// Times every frame the screen shows while the meter is up, and reads them out twice a second over the last two
/// seconds. It counts frames the app was late to hand over; a frame the GPU drops after that shows only by eye.
@MainActor
@Observable
final class FrameMeter {
    private(set) var reading: FrameStats?

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var gaps: [(gap: Double, at: Double)] = []
    @ObservationIgnored private var last: CFTimeInterval?
    @ObservationIgnored private var lastRead: CFTimeInterval = 0
    @ObservationIgnored private var target = LinkTarget()

    func start() {
        guard link == nil else { return }
        target.tick = { [weak self] link in self?.frame(link) }
        let link = CADisplayLink(target: target, selector: #selector(LinkTarget.frame))
        // The fastest the screen can go, so a ProMotion phone is measured at 120 Hz as it scrolls.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        last = nil
        gaps = []
        reading = nil
    }

    private func frame(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { last = now }
        guard let last else { return }
        gaps.append((now - last, now))
        gaps.removeAll { $0.at < now - 2 }
        guard now - lastRead >= 0.5 else { return }
        lastRead = now
        reading = FrameStats(gaps: gaps.map(\.gap), interval: max(1.0 / 120, link.targetTimestamp - link.timestamp))
    }
}

/// Reads the app's CPU, its busiest threads, the thermal state, Low Power Mode and the battery every two seconds,
/// from launch.
@MainActor
final class EnergyMeter {
    private(set) var cpu: Double?
    private var threads: [ThreadLoad] = []
    private var thermal = ThermalClock()
    private var battery = BatteryTrack()

    private var last: (busy: Double, at: Double)?
    private var lastThreads: [ThreadLoad.Sample] = []

    func sample() {
        let now = CACurrentMediaTime()
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        battery.record(level: Double(device.batteryLevel),
                       charging: device.batteryState == .charging || device.batteryState == .full, at: now)
        thermal.record(Self.heat(ProcessInfo.processInfo.thermalState), at: now)
        let samples = Self.threadSamples()
        if let last { threads = ThreadLoad.busiest(from: lastThreads, to: samples, elapsed: now - last.at) }
        lastThreads = samples
        guard let busy = Self.busySeconds() else { return }
        if let last, let cpu = EnergyStats.cpu(busy: last.busy, busy, elapsed: now - last.at) { self.cpu = cpu }
        last = (busy, now)
    }

    func reading(room: RoomVisibility) -> EnergyStats? {
        guard let cpu else { return nil }
        let info = ProcessInfo.processInfo
        return EnergyStats(cpu: cpu, room: EnergyStats.Room(room), heat: Self.heat(info.thermalState),
                           lowPower: info.isLowPowerModeEnabled, threads: threads, battery: battery.drain,
                           secondsToFair: thermal.secondsToFair)
    }

    private static func heat(_ state: ProcessInfo.ThermalState) -> EnergyStats.Heat {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .critical
        }
    }

    /// CPU time per thread alive now. The first thread is the main one; the others are named by what made them.
    private static func threadSamples() -> [ThreadLoad.Sample] {
        var list: thread_act_array_t?
        var count = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS, let list else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: list)),
                          vm_size_t(Int(count) * MemoryLayout<thread_act_t>.size))
        }
        func seconds(_ t: time_value_t) -> Double { Double(t.seconds) + Double(t.microseconds) / 1e6 }
        var samples: [ThreadLoad.Sample] = []
        for index in 0..<Int(count) {
            let port = list[index]
            defer { mach_port_deallocate(mach_task_self_, port) }
            var basic = thread_basic_info()
            var basicCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
            let basicResult = withUnsafeMutablePointer(to: &basic) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) {
                    thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &basicCount)
                }
            }
            var identity = thread_identifier_info()
            var identityCount = mach_msg_type_number_t(
                MemoryLayout<thread_identifier_info>.size / MemoryLayout<integer_t>.size)
            let identityResult = withUnsafeMutablePointer(to: &identity) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(identityCount)) {
                    thread_info(port, thread_flavor_t(THREAD_IDENTIFIER_INFO), $0, &identityCount)
                }
            }
            guard basicResult == KERN_SUCCESS, identityResult == KERN_SUCCESS else { continue }
            var name = ""
            if let thread = pthread_from_mach_thread_np(port) {
                var buffer = [CChar](repeating: 0, count: 64)
                if pthread_getname_np(thread, &buffer, buffer.count) == 0 { name = String(cString: buffer) }
            }
            if index == 0 { name = "main" } else if name.isEmpty { name = "#\(identity.thread_id % 10_000)" }
            samples.append(.init(id: identity.thread_id, name: name,
                                 seconds: seconds(basic.user_time) + seconds(basic.system_time)))
        }
        return samples
    }

    /// The CPU time the app has used since launch, in seconds: its threads alive now and those that ended.
    private static func busySeconds() -> Double? {
        func count<T>(_: T.Type) -> mach_msg_type_number_t {
            mach_msg_type_number_t(MemoryLayout<T>.size / MemoryLayout<natural_t>.size)
        }
        var live = task_thread_times_info_data_t()
        var liveCount = count(task_thread_times_info_data_t.self)
        let liveResult = withUnsafeMutablePointer(to: &live) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(liveCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), $0, &liveCount)
            }
        }
        var ended = mach_task_basic_info_data_t()
        var endedCount = count(mach_task_basic_info_data_t.self)
        let endedResult = withUnsafeMutablePointer(to: &ended) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(endedCount)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &endedCount)
            }
        }
        guard liveResult == KERN_SUCCESS, endedResult == KERN_SUCCESS else { return nil }
        func seconds(_ t: time_value_t) -> Double { Double(t.seconds) + Double(t.microseconds) / 1e6 }
        return seconds(live.user_time) + seconds(live.system_time) + seconds(ended.user_time)
            + seconds(ended.system_time)
    }
}

/// A display link holds its target strongly; this keeps that target from being the meter.
private final class LinkTarget: NSObject {
    var tick: (CADisplayLink) -> Void = { _ in }

    @objc func frame(_ link: CADisplayLink) { tick(link) }
}

/// The meter's reading over Home; a tap opens the switches, so one can be flipped and the page scrolled at once.
struct PerfLabMeter: View {
    let lab: PerfLab
    let room: RoomVisibility
    let tabs: TabSwitchTimes
    @State private var meter = FrameMeter()
    @State private var opened = false

    private var line: String {
        [meter.reading?.line ?? "measuring…", lab.energy.reading(room: room)?.line, tabs.line].compactMap { $0 }
            .joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: Space.s) {
            Button { withAnimation(Motion.fade()) { opened.toggle() } } label: {
                Text(line)
                    .font(.ourioMicro.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Ink.text)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs)
                    .frame(minHeight: 24)
                    .cornerFill(.inner, Ink.surface)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Frame meter")
            .accessibilityValue(line)
            .accessibilityHint("Shows the performance switches")

            if opened {
                PerfLabSwitches(lab: lab, reading: meter.reading, energy: lab.energy.reading(room: room), tabs: tabs)
                    .frame(maxWidth: 320)
                    .transition(.opacity)
            }
        }
        .onAppear { meter.start() }
        .onDisappear { meter.stop() }
    }
}

/// Settings › Labs › Performance: the meter over Home, and the same switches it opens.
struct PerfLabPage: View {
    let lab: PerfLab

    var body: some View {
        Page {
            GroupedSection(header: "Meter",
                           footer: "Shows frames per second and the app's CPU over Home, with whether the room draws "
                               + "and how warm the phone is; tap it there to flip these switches while you scroll a "
                               + "page. Copy settings puts the switches and the reading on the clipboard.") {
                ToggleRow("Frame meter", symbol: "speedometer", tint: UsTint.sage.color, isOn: lab.meter)
            }
            PerfLabSwitches(lab: lab)
        }
        .navigationTitle("Performance")
    }
}

/// The tier the room draws at now and the control that holds it at one.
private struct QualityTierPicker: View {
    let lab: PerfLab

    var body: some View {
        let forced = lab.state.forcedTier
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Quality tier: \(lab.tier.title)\(forced == nil ? " (follows heat and Low Power Mode)" : " (forced)")")
                .font(.ourioMicro)
                .foregroundStyle(Ink.textSecondary)
            Picker("Quality tier", selection: Binding(get: { forced }, set: { lab.force($0) })) {
                Text("Auto").tag(RoomQualityTier?.none)
                ForEach(RoomQualityTier.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }
            .pickerStyle(.segmented)
            .font(.ourioMicro)
        }
    }
}

/// Each suspect's switch, the copy line and a reset, in one card: on Home under the meter and in Settings › Labs.
struct PerfLabSwitches: View {
    let lab: PerfLab
    var reading: FrameStats?
    var energy: EnergyStats?
    var tabs: TabSwitchTimes?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(PerfSuspect.allCases, id: \.self) { suspect in
                    ToggleRow(suspect.title, symbol: suspect.symbol, tint: UsTint.honey.color, isOn: lab.binding(suspect))
                }
                QualityTierPicker(lab: lab)
                Text(lab.day?.line ?? "MetricKit: no day delivered yet; the system sends one about once a day.")
                    .font(.ourioMicro)
                    .foregroundStyle(Ink.textSecondary)
                HStack(spacing: Space.s) {
                    SecondaryButton("Copy settings", fullWidth: true) {
                        UIPasteboard.general.string = PerfLabMachine.summary(lab.state, reading: reading,
                                                                             energy: energy, tabs: tabs, day: lab.day)
                    }
                    if let json = MetricsReceiver.savedJSON() {
                        SecondaryButton("Copy MetricKit", fullWidth: false) { UIPasteboard.general.string = json }
                    }
                    SecondaryButton("Reset", fullWidth: false) { lab.reset() }
                }
            }
        }
    }
}
#endif
