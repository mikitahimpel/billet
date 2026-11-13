import RealityKit
import Testing
import UIKit
import simd

@testable import Billet

@MainActor
struct IdleGateTests {
    @Test func aChangeGatePassesOnlyANewValue() {
        var gate = ChangeGate<Float>()
        let results = [gate.passes(1), gate.passes(1), gate.passes(2), gate.passes(2)]
        gate.reopen()
        let again = gate.passes(2)
        #expect(results == [true, false, true, false])
        #expect(again)
    }

    @Test func aStillRoomWritesTheBodyScaleOnceNotPerFrame() {
        var gate = ChangeGate<SIMD3<Float>>()
        let writes = (0..<600).filter { _ in gate.passes([1, 1, 1]) }.count
        #expect(writes == 1)
    }

    @Test func aThrottleFollowsAnIntervalThatChanges() {
        var throttle = Throttle(interval: PulseRates.active.flame)
        _ = throttle.fires(1.0 / 60)
        let active = (0..<120).filter { _ in throttle.fires(1.0 / 60) }.count
        throttle.interval = PulseRates.idle.flame
        let idle = (0..<120).filter { _ in throttle.fires(1.0 / 60) }.count
        #expect(active >= 55 && active <= 61)
        #expect(idle >= 18 && idle <= 21)
    }

    @Test func theIdleRatesAreSlowerThanTheActiveOnesAndNeverStop() {
        let active = PulseRates.at(active: true), idle = PulseRates.at(active: false)
        #expect(idle.flame > active.flame && idle.candle > active.candle && idle.bulbs > active.bulbs)
        #expect(idle.flame <= 0.25 && idle.candle <= 0.5 && idle.bulbs <= 0.25)
    }

    @Test func theClockHandsStandWhereTheHourPutsThem() {
        let parent = Entity()
        let set = Props.wallClock(parent, at: .zero)
        var hands: [Entity] = []
        parent.forEachDescendant { entity in
            if entity.components.has(ShellLive.self) { hands.append(entity) }
        }
        #expect(hands.count == 2)
        set(15.5)
        let hour = simd_quatf.x(-(3.5 / 12) * .pi * 2), minute = simd_quatf.x(-0.5 * .pi * 2)
        #expect(abs(simd_dot(hands[0].orientation, hour)) > 0.9999)
        #expect(abs(simd_dot(hands[1].orientation, minute)) > 0.9999)
    }

    @Test func theBedroomKeepsTheClockOnTheTimeWhileItReadsItOnceASecond() {
        let room = CityRoomScene()
        for _ in 0..<180 { room.tick(1.0 / 60) }
        var live: [Entity] = []
        room.root.forEachDescendant { entity in
            if entity.components.has(ShellLive.self) { live.append(entity) }
        }
        let now = Daylight.localHour()
        let minute = simd_quatf.x(-(now.truncatingRemainder(dividingBy: 1)) * .pi * 2)
        #expect(live.contains { abs(simd_dot($0.orientation, minute)) > 0.9995 })
    }

    @Test func printsTheSceneWritesPerSecondOfAnIdleRoom() {
        let bedroom = CityRoomScene(), living = DioramaScene()
        _ = SceneWrites.drainRates()
        for _ in 0..<(30 * 30) { bedroom.tick(1.0 / 30) }
        print("scene writes: bedroom idle", SceneWrites.drainRates())
        for _ in 0..<(30 * 10) { living.tick(1.0 / 30) }
        _ = SceneWrites.drainRates()
        for _ in 0..<(30 * 30) { living.tick(1.0 / 30) }
        print("scene writes: living idle", SceneWrites.drainRates())
    }

    @Test func theWindowIsProjectedAgainOnlyWhenSomethingItDependsOnMoved() {
        let room = CityRoomScene()
        let surface = CountingSurface()
        room.placeWindow(surface)
        let first = surface.projections
        #expect(first >= 13)
        surface.projections = 0
        room.placeWindow(surface)
        #expect(surface.projections == 1)

        surface.projections = 0
        room.pivot.orientation = .y(0.1)
        room.placeWindow(surface)
        #expect(surface.projections == first)

        surface.projections = 0
        surface.shift = 5
        room.placeWindow(surface)
        #expect(surface.projections == first)
    }
}

private final class CountingSurface: RoomSurface {
    var projections = 0
    var shift: CGFloat = 0

    func updates(_ handler: @escaping (SceneEvents.Update) -> Void) -> EventSubscription {
        fatalError("not stepped in these tests")
    }

    func project(_ point: SIMD3<Float>) -> CGPoint? {
        projections += 1
        return CGPoint(x: CGFloat(point.x) * 100 + shift, y: CGFloat(point.y) * 100)
    }

    func unproject(_ point: CGPoint, ontoPlane plane: simd_float4x4) -> SIMD3<Float>? { nil }
}
