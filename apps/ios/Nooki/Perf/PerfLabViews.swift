#if DEBUG || LABS_YES
import Design
import OurioShared
import QuartzCore
import SwiftUI
import Darwin
import RoomInterface
import UIKit

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

/// Reads the app's CPU, the thermal state and Low Power Mode once a second while the meter is up.
@MainActor
@Observable
final class EnergyMeter {
    private(set) var cpu: Double?

    @ObservationIgnored private var last: (busy: Double, at: Double)?

    func sample() {
        guard let busy = Self.busySeconds() else { return }
        let now = CACurrentMediaTime()
        if let last, let cpu = EnergyStats.cpu(busy: last.busy, busy, elapsed: now - last.at) { self.cpu = cpu }
        last = (busy, now)
    }

    func reading(room: RoomVisibility) -> EnergyStats? {
        guard let cpu else { return nil }
        let info = ProcessInfo.processInfo
        return EnergyStats(cpu: cpu, room: EnergyStats.Room(room), heat: Self.heat(info.thermalState),
                           lowPower: info.isLowPowerModeEnabled)
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
    @State private var meter = FrameMeter()
    @State private var energy = EnergyMeter()
    @State private var opened = false

    private var line: String {
        [meter.reading?.line ?? "measuring…", energy.reading(room: room)?.line].compactMap { $0 }
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
                    .background(Ink.surface, in: .rect(cornerRadius: Radius.inner))
                    .overlay(RoundedRectangle(cornerRadius: Radius.inner).strokeBorder(Ink.hairline, lineWidth: 1))
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Frame meter")
            .accessibilityValue(line)
            .accessibilityHint("Shows the performance switches")

            if opened {
                PerfLabSwitches(lab: lab, reading: meter.reading, energy: energy.reading(room: room))
                    .frame(maxWidth: 320)
                    .transition(.opacity)
            }
        }
        .onAppear { meter.start() }
        .onDisappear { meter.stop() }
        .task {
            while !Task.isCancelled {
                energy.sample()
                try? await Task.sleep(for: .seconds(1))
            }
        }
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

/// Each suspect's switch, the copy line and a reset, in one card: on Home under the meter and in Settings › Labs.
struct PerfLabSwitches: View {
    let lab: PerfLab
    var reading: FrameStats?
    var energy: EnergyStats?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(PerfSuspect.allCases, id: \.self) { suspect in
                    ToggleRow(suspect.title, symbol: suspect.symbol, tint: UsTint.honey.color, isOn: lab.binding(suspect))
                }
                HStack(spacing: Space.s) {
                    SecondaryButton("Copy settings", fullWidth: true) {
                        UIPasteboard.general.string = PerfLabMachine.summary(lab.state, reading: reading,
                                                                             energy: energy)
                    }
                    SecondaryButton("Reset", fullWidth: false) { lab.reset() }
                }
            }
        }
    }
}
#endif
