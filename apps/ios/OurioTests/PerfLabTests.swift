import Foundation
import RoomInterface
import Testing
@testable import Billet

/// Labs → Performance: its switches, the copy line and the frame meter's arithmetic.
@MainActor
struct PerfLabTests {
    typealias State = PerfLabMachine.State

    @Test func everythingShipsOnButFlatten() {
        let state = State.shipped
        for suspect in PerfSuspect.allCases {
            #expect(state.isOn(suspect) == (suspect != .flatten))
        }
        #expect(!state.meter)
    }

    nonisolated static let accepted: [(State, PerfLabMachine.Event, State)] = [
        (.shipped, .set(.shadows, on: false), State(changed: [.shadows])),
        (.shipped, .set(.flatten, on: true), State(changed: [.flatten])),
        (State(changed: [.shadows, .shine]), .set(.shadows, on: true), State(changed: [.shine])),
        (State(changed: [.flatten]), .set(.flatten, on: false), .shipped),
        (.shipped, .meter(true), State(meter: true)),
        (State(meter: true), .meter(false), .shipped),
        (State(changed: [.barGlass, .scrollEdges], meter: true), .reset, .shipped),
    ]

    @Test(arguments: accepted)
    func acceptedEventsChangeAndSave(from: State, event: PerfLabMachine.Event, to: State) {
        let (next, outputs) = PerfLabMachine.transition(from, event)
        #expect(next == to)
        #expect(outputs == [.save(to)])
    }

    nonisolated static let rejected: [(State, PerfLabMachine.Event)] = [
        (.shipped, .set(.shadows, on: true)),
        (.shipped, .set(.flatten, on: false)),
        (State(changed: [.pageGlass]), .set(.pageGlass, on: false)),
        (State(changed: [.flatten]), .set(.flatten, on: true)),
        (.shipped, .meter(false)),
        (State(meter: true), .meter(true)),
        (.shipped, .reset),
    ]

    @Test(arguments: rejected)
    func rejectedEventsChangeNothing(state: State, event: PerfLabMachine.Event) {
        let (next, outputs) = PerfLabMachine.transition(state, event)
        #expect(next == state)
        #expect(outputs.isEmpty)
    }

    @Test func theCopyLineNamesWhatIsSwitchedAndTheReading() {
        let reading = FrameStats(gaps: Array(repeating: 1.0 / 60, count: 60), interval: 1.0 / 60)
        #expect(PerfLabMachine.summary(.shipped, reading: nil) == "Perf lab: as shipped")
        #expect(PerfLabMachine.summary(State(changed: [.shine, .barGlass, .flatten]), reading: reading)
            == "Perf lab: barGlass off, shine off, flatten on · 60 fps, p95 16.7 ms, 0 dropped")
    }

    @Test func theCopyLineEndsWithTheEnergyReading() {
        let energy = EnergyStats(cpu: 41.6, room: .off, heat: .fair, lowPower: true)
        #expect(PerfLabMachine.summary(.shipped, reading: nil, energy: energy)
            == "Perf lab: as shipped · CPU 42% · room off · fair · low power")
        #expect(EnergyStats(cpu: 3, room: .drawing, heat: .nominal, lowPower: false).line
            == "CPU 3% · room drawing · nominal")
    }

    @Test func cpuIsTheTimeUsedOverTheTimePassed() throws {
        // A second and a half of CPU over three seconds, from threads on two cores: 50% of one core.
        #expect(try abs(#require(EnergyStats.cpu(busy: 10, 11.5, elapsed: 3)) - 50) < 0.001)
        #expect(try abs(#require(EnergyStats.cpu(busy: 10, 13, elapsed: 1)) - 300) < 0.001)
        #expect(EnergyStats.cpu(busy: 10, 11, elapsed: 0) == nil)
        #expect(EnergyStats.cpu(busy: 10, 9, elapsed: 1) == nil)
    }

    @Test func theRoomReadsAsItIsShown() {
        #expect(EnergyStats.Room(.visible) == .drawing)
        #expect(EnergyStats.Room(.covered) == .paused)
        #expect(EnergyStats.Room(.hidden) == .off)
    }

    @Test func tabSwitchesKeepTheLastTwentyAndTheirPercentiles() {
        var times = TabSwitchTimes()
        #expect(times.line == nil)
        for ms in 1...25 { times.add(Double(ms * 10)) }
        // 60...250 ms are kept: the median of twenty is the tenth, the 95th percentile the nineteenth.
        #expect(times.recent.count == 20)
        #expect(times.last == 250)
        #expect(times.p50 == 150)
        #expect(times.p95 == 240)
        #expect(times.line == "tab 250 ms, p50 150, p95 240 of 20")
        #expect(PerfLabMachine.summary(.shipped, reading: nil, tabs: times)
            == "Perf lab: as shipped · tab 250 ms, p50 150, p95 240 of 20")
    }

    @Test func aSteadyScreenDropsNothing() throws {
        let stats = try #require(FrameStats(gaps: Array(repeating: 1.0 / 120, count: 240), interval: 1.0 / 120))
        #expect(abs(stats.fps - 120) < 0.01)
        #expect(abs(stats.p95 - 8.33) < 0.01)
        #expect(stats.dropped == 0)
    }

    @Test func aLongGapCountsTheFramesItSkipped() throws {
        // 18 frames on time, then one frame of four intervals and one of two: three skipped, then one.
        let interval = 1.0 / 60
        let gaps = Array(repeating: interval, count: 18) + [interval * 4, interval * 2]
        let stats = try #require(FrameStats(gaps: gaps, interval: interval))
        #expect(stats.dropped == 4)
        #expect(abs(stats.p95 - interval * 2 * 1000) < 0.01)
        #expect(abs(stats.fps - 20 / (interval * 24)) < 0.01)
    }

    @Test func noFramesIsNoReading() {
        #expect(FrameStats(gaps: [], interval: 1.0 / 60) == nil)
        #expect(FrameStats(gaps: [0.01], interval: 0) == nil)
    }

    @Test func theSwitchesOutliveALaunch() async throws {
        let defaults = try #require(UserDefaults(suiteName: "PerfLabTests"))
        defer { defaults.removePersistentDomain(forName: "PerfLabTests") }
        let lab = PerfLab(defaults: defaults)
        lab.binding(.shadows).wrappedValue = false
        lab.meter.wrappedValue = true
        await lab.settled()
        let again = PerfLab(defaults: defaults)
        #expect(again.state == State(changed: [.shadows], meter: true))
        again.reset()
        await again.settled()
        #expect(PerfLab(defaults: defaults).state == .shipped)
    }
}
