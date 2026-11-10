import Foundation
import RealityKit
import Testing
@testable import Billet

/// Labs › Performance › Dust motes: every room's emitters follow the switch, in rooms built before it and after.
@MainActor
struct RoomMotesTests {
    @Test func theMotesFollowTheSwitchInEveryRoom() throws {
        let defaults = try #require(UserDefaults(suiteName: "RoomMotesTests"))
        defer { defaults.removePersistentDomain(forName: "RoomMotesTests") }
        let controller = RoomController(usesStandIn: false, defaults: defaults)
        controller.load()
        let home = try #require(controller.home)
        #expect(emitters(in: home.root) == [true])

        controller.showMotes(false)
        #expect(emitters(in: home.root) == [false])
        controller.prepare(.city)
        let city = try #require(controller.city)
        #expect(!emitters(in: city.root).isEmpty)
        #expect(emitters(in: city.root).allSatisfy { !$0 })

        controller.showMotes(true)
        #expect(emitters(in: home.root) == [true])
        #expect(emitters(in: city.root).allSatisfy { $0 })
    }

    /// Whether each particle emitter under `entity` is enabled.
    private func emitters(in entity: Entity) -> [Bool] {
        (entity.components.has(ParticleEmitterComponent.self) ? [entity.isEnabled] : [])
            + entity.children.flatMap { emitters(in: $0) }
    }
}
