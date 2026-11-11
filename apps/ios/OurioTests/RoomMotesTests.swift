import Foundation
import RealityKit
import Testing
@testable import Billet

/// Labs › Performance › Dust motes: off as shipped; every room's emitters follow the switch, in rooms built before it
/// and after.
@MainActor
struct RoomMotesTests {
    @Test func theMotesAreOffUntilTheSwitchTurnsThemOnInEveryRoom() throws {
        let defaults = try #require(UserDefaults(suiteName: "RoomMotesTests"))
        defer { defaults.removePersistentDomain(forName: "RoomMotesTests") }
        let controller = RoomController(usesStandIn: false, defaults: defaults)
        controller.load()
        let home = try #require(controller.home)
        #expect(emitters(in: home.root) == [false])

        controller.showMotes(true)
        #expect(emitters(in: home.root) == [true])
        controller.prepare(.city)
        let city = try #require(controller.city)
        #expect(!emitters(in: city.root).isEmpty)
        #expect(emitters(in: city.root).allSatisfy { $0 })

        controller.showMotes(false)
        #expect(emitters(in: home.root) == [false])
        #expect(emitters(in: city.root).allSatisfy { !$0 })
    }

    /// Whether each particle emitter under `entity` is enabled.
    private func emitters(in entity: Entity) -> [Bool] {
        (entity.components.has(ParticleEmitterComponent.self) ? [entity.isEnabled] : [])
            + entity.children.flatMap { emitters(in: $0) }
    }
}

/// Labs › Performance › Room sway, and the idle room that holds still by itself.
@MainActor
struct RoomSwayTests {
    @Test func anIdleRoomIsAStillFrame() throws {
        let controller = RoomController(usesStandIn: false)
        controller.load()
        let home = try #require(controller.home)
        for _ in 0..<120 { home.tick(1.0 / 60) }
        #expect(!home.isSwaying)
        #expect(home.pivot.orientation == simd_quatf.y(0))
    }

    @Test func aTouchSwaysItAndItEasesBackToRest() throws {
        let controller = RoomController(usesStandIn: false)
        controller.load()
        let home = try #require(controller.home)
        home.setYaw(0.1)
        home.tick(1.0 / 60)
        home.tick(1.0 / 60)
        #expect(home.isSwaying)
        for _ in 0..<(60 * 12) { home.tick(1.0 / 60) }
        #expect(!home.isSwaying)
    }

    @Test func theSwitchHoldsItStillEvenUnderATouch() throws {
        let controller = RoomController(usesStandIn: false)
        controller.load()
        let home = try #require(controller.home)
        controller.setSway(false)
        home.setYaw(0.1)
        for _ in 0..<30 { home.tick(1.0 / 60) }
        #expect(!home.isSwaying)
        controller.setSway(true)
        home.setYaw(0.1)
        home.tick(1.0 / 60)
        home.tick(1.0 / 60)
        #expect(home.isSwaying)
    }
}

struct SwayEnvelopeTests {
    @Test func itRisesWhileActiveAndFallsAfterTheQuietSeconds() {
        var sway = SwayEnvelope()
        for _ in 0..<60 { sway.update(dt: 1.0 / 60, active: true, enabled: true) }
        #expect(sway.strength > 0.7)
        // Quiet, but not yet for long enough: it holds.
        for _ in 0..<(60 * 2) { sway.update(dt: 1.0 / 60, active: false, enabled: true) }
        #expect(sway.strength > 0.9)
        for _ in 0..<(60 * 6) { sway.update(dt: 1.0 / 60, active: false, enabled: true) }
        #expect(sway.strength == 0)
    }

    @Test func disabledItNeverRises() {
        var sway = SwayEnvelope()
        for _ in 0..<60 { sway.update(dt: 1.0 / 60, active: true, enabled: false) }
        #expect(sway.strength == 0)
    }

    @Test func aThrottleFiresFirstThenOnceAnInterval() {
        var throttle = Throttle(interval: 0.1)
        #expect(throttle.fires(1.0 / 60))
        let fired = (0..<60).filter { _ in throttle.fires(1.0 / 60) }.count
        #expect(fired == 9 || fired == 10)
    }
}
