import Foundation
import GamesInterface
import RoomInterface
import Testing
@testable import Billet

/// Labs → Performance: its switches, the copy line and the frame meter's arithmetic.
@MainActor
struct PerfLabTests {
    typealias State = PerfLabMachine.State

    @Test func everythingShipsOnButTheExtraStepsTheDustAndTheAntialiasing() {
        let state = State.shipped
        for suspect in PerfSuspect.allCases {
            #expect(state.isOn(suspect) == ![.flatten, .motes, .msaa, .ownLoop, .metalHud, .splatLean, .splatRate, .mergeFurniture, .bakedBlobs, .noSunShadow, .fewerLights, .noBloom].contains(suspect))
        }
        #expect(!state.meter)
    }

    nonisolated static let accepted: [(State, PerfLabMachine.Event, State)] = [
        (.shipped, .set(.shadows, on: false), State(changed: [.shadows])),
        (.shipped, .set(.flatten, on: true), State(changed: [.flatten])),
        (State(changed: [.shadows, .shine]), .set(.shadows, on: true), State(changed: [.shine])),
        (State(changed: [.flatten]), .set(.flatten, on: false), .shipped),
        (.shipped, .meter(true), State(meter: true)),
        (.shipped, .force(.serious), State(forcedTier: .serious)),
        (State(forcedTier: .serious), .force(nil), .shipped),
        (State(forcedTier: .serious), .force(.fair), State(forcedTier: .fair)),
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
        (.shipped, .force(nil)),
        (State(forcedTier: .fair), .force(.fair)),
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

    @Test func theCopyLineNamesAForcedTier() {
        #expect(PerfLabMachine.summary(State(forcedTier: .serious), reading: nil) == "Perf lab: tier serious forced")
    }

    @Test func theCopyLineCarriesTheGovernor() {
        let line = GovernorReadout.line(tier: .fair, forced: false, reason: "Low Power Mode", changes: 3)
        #expect(line == "governor fair (Low Power Mode), 3 changes")
        #expect(PerfLabMachine.summary(.shipped, reading: nil, governor: line)
            == "Perf lab: as shipped · governor fair (Low Power Mode), 3 changes")
    }

    @Test func theGovernorReadoutSaysWhyAndWhatItDraws() {
        #expect(GovernorReadout.why(.heat(.serious), recovering: false, forced: false) == "heat serious")
        #expect(GovernorReadout.why(.idle, recovering: true, forced: false) == "room left alone, recovering")
        #expect(GovernorReadout.why(.none, recovering: false, forced: true) == "forced in Labs")
        let conditions = RoomConditions(
            heat: .fair, lowPower: true, battery: .init(level: 0.18, charging: false), idle: 75.4, busy: false)
        #expect(GovernorReadout.inputs(conditions)
            == "heat fair, low power on, battery 18% unplugged, idle 75 s, busy no")
        #expect(GovernorReadout.plan(RoomQualityTier.serious.plan)
            == "30/20 fps, 1.25x, bloom off, sun shadow off, lights all, hdr on, ambient +0.15, pulse x3")
    }

    @Test func aQuietRoomIsIdleAndADragOrAGameStartIsBusy() {
        let controller = RoomController(usesStandIn: true, defaults: UserDefaults(suiteName: "governor.\(UUID())")!)
        let start = ProcessInfo.processInfo.systemUptime
        controller.looked()
        #expect(controller.quiet(now: start + 100).idle >= 99)
        #expect(!controller.quiet(now: start + 100).busy)
        controller.fingerMoved(true)
        #expect(controller.quiet(now: ProcessInfo.processInfo.systemUptime + 1).busy)
        controller.fingerMoved(false)
        #expect(!controller.quiet(now: ProcessInfo.processInfo.systemUptime + 1).busy)
        #expect(controller.quiet(now: ProcessInfo.processInfo.systemUptime + 1).idle < 2.5)
        controller.play(.feed)
        #expect(controller.quiet(now: ProcessInfo.processInfo.systemUptime + 1).busy)
        #expect(!controller.quiet(now: ProcessInfo.processInfo.systemUptime + RoomController.gameGrace + 1).busy)
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

    @Test func theNewSwitchesShipOn() {
        #expect(State.shipped.isOn(.splatCat))
        #expect(State.shipped.isOn(.sway))
        #expect(PerfLabMachine.transition(.shipped, .set(.sway, on: false)).0 == State(changed: [.sway]))
    }

    @Test func threadsAreRankedByTheirOwnCPUAndAnythingIdleOrNewIsLeftOut() {
        let before: [ThreadLoad.Sample] = [
            .init(id: 1, name: "main", seconds: 10), .init(id: 2, name: "render", seconds: 5),
            .init(id: 3, name: "idle", seconds: 2),
        ]
        let after: [ThreadLoad.Sample] = [
            .init(id: 1, name: "main", seconds: 10.2), .init(id: 2, name: "render", seconds: 5.6),
            .init(id: 3, name: "idle", seconds: 2.001), .init(id: 4, name: "new", seconds: 9),
        ]
        let busiest = ThreadLoad.busiest(from: before, to: after, elapsed: 2)
        #expect(busiest.map(\.name) == ["render", "main"])
        #expect(abs(busiest[0].cpu - 30) < 0.001)
        #expect(abs(busiest[1].cpu - 10) < 0.001)
        #expect(ThreadLoad.busiest(from: before, to: after, elapsed: 0).isEmpty)
        #expect(ThreadLoad.busiest(from: before, to: after, elapsed: 2, count: 1).count == 1)
    }

    @Test func theBatteryDrainShowsAfterFiveMinutesUnplugged() throws {
        var track = BatteryTrack()
        track.record(level: 0.80, charging: false, at: 0)
        track.record(level: 0.79, charging: false, at: 200)
        #expect(track.drain == nil)
        track.record(level: 0.78, charging: false, at: 600)
        let drain = try #require(track.drain)
        // Two points in ten minutes.
        #expect(abs(drain.per10Minutes - 2) < 0.001)
        #expect(abs(drain.minutes - 10) < 0.001)
        #expect(drain.line == "battery -2.0%/10 min over 10 min")
    }

    @Test func chargingOrAnUnknownLevelOrARiseStartsTheDrainOver() {
        var track = BatteryTrack()
        track.record(level: 0.8, charging: false, at: 0)
        track.record(level: 0.7, charging: false, at: 400)
        #expect(track.drain != nil)
        track.record(level: 0.7, charging: true, at: 500)
        #expect(track.drain == nil)
        track.record(level: 0.7, charging: false, at: 600)
        track.record(level: 0.6, charging: false, at: 1000)
        #expect(track.drain != nil)
        track.record(level: -1, charging: false, at: 1100)
        #expect(track.drain == nil)
        track.record(level: 0.5, charging: false, at: 1200)
        track.record(level: 0.6, charging: false, at: 1600)
        #expect(track.drain == nil)
    }

    @Test func theClockCountsFromANominalStartToTheFirstWarmth() {
        var clock = ThermalClock()
        clock.record(.nominal, at: 100)
        clock.record(.nominal, at: 400)
        #expect(clock.secondsToFair == nil)
        clock.record(.fair, at: 1000)
        clock.record(.serious, at: 1200)
        #expect(clock.secondsToFair == 900)
        var warm = ThermalClock()
        warm.record(.fair, at: 0)
        warm.record(.serious, at: 60)
        #expect(warm.secondsToFair == nil)
    }

    @Test func theEnergyLineCarriesTheExtrasInOrder() {
        let energy = EnergyStats(
            cpu: 30, room: .drawing, heat: .fair, lowPower: false,
            threads: [ThreadLoad(name: "main", cpu: 22.4), ThreadLoad(name: "render", cpu: 9)],
            battery: BatteryDrain(per10Minutes: 1.5, minutes: 12), secondsToFair: 840)
        #expect(energy.line == "CPU 30% · room drawing · fair · fair after 14 min · battery -1.5%/10 min over 12 min"
            + " · threads main 22, render 9")
    }

    @Test func aMetricKitDayIsTheGPUAndCPUShareOfTheForeground() throws {
        let day = MetricsDigest(gpuSeconds: 1800, cpuSeconds: 900, foregroundSeconds: 3600, hitchRatio: 0.0021,
                                day: Date(timeIntervalSince1970: 0))
        #expect(try abs(#require(day.gpuDuty) - 50) < 0.001)
        #expect(day.line == "day GPU 50% (30 min), CPU 25% of 60 min foreground, hitch 2.1 ms/s")
        #expect(MetricsDigest(gpuSeconds: 1, cpuSeconds: 1, foregroundSeconds: 0, hitchRatio: nil, day: day.day).line == nil)
        #expect(PerfLabMachine.summary(.shipped, reading: nil, day: day).hasSuffix(" · " + (day.line ?? "")))
        let data = try JSONEncoder().encode(day)
        #expect(try JSONDecoder().decode(MetricsDigest.self, from: data) == day)
    }
}
