import FeatureGames
import RealityKit
import Testing

@testable import Billet

/// The corner a game is played in: its lights cast no shadow map, and its floor tops out where the games stand their
/// props and lay their blobs.
@MainActor
struct CornerFloorTests {
    @Test(arguments: GameScenery.allCases)
    func theCornersLightsCastNoShadowMap(scenery: GameScenery) {
        let room = TabletopRoom(scenery: scenery)
        var lights = 0
        var maps = 0
        room.root.forEachDescendant {
            if $0.components.has(DirectionalLightComponent.self) { lights += 1 }
            if $0.components.has(DirectionalLightComponent.Shadow.self) { maps += 1 }
        }
        #expect(lights == 2)
        #expect(maps == 0)
    }

    /// A blob a game lays 1.5 mm over `floorTop` must lie over the floor, not inside a plank: the kitchen's planks and
    /// seams reach `floorTop` and no higher, like the plain floors of the other sceneries, and every blob of the set
    /// and of the games played there clears it.
    @Test(arguments: GameScenery.allCases)
    func theFloorTopsOutAtFloorTopAndEveryBlobClearsIt(scenery: GameScenery) {
        let room = TabletopRoom(scenery: scenery)
        let deck = GameDeck()
        let stages: [any GameStage] = [FeedStage(room: room, deck: deck), WaterStage(room: room, deck: deck)]
        let top = TabletopRoom.floorTop
        var highest: Float = -1
        var layers = 0
        var blobs = 0
        var lowestBlob = Float.infinity
        room.pivot.forEachDescendant { entity in
            // Feed's mound waits disabled in the bowl, a unit sphere squashed by its scale.
            guard entity.isEnabled, let model = entity.components[ModelComponent.self] else { return }
            let bounds = entity.visualBounds(relativeTo: room.pivot)
            if model.materials.contains(where: { $0 is UnlitMaterial }), bounds.extents.y < 0.001, bounds.max.y < top + 0.01 {
                blobs += 1
                lowestBlob = min(lowestBlob, bounds.min.y)
            } else if bounds.extents.x > 2, bounds.extents.z > 2, bounds.extents.y < 0.05 {
                // A floor layer spans the corner and is flat, wherever it lies; walls are tall, furniture is small.
                layers += 1
                highest = max(highest, bounds.max.y)
            }
        }
        #expect(layers >= 1)
        #expect(abs(highest - top) < 1e-4, "the floor tops out at \(highest) m, not \(top)")
        #expect(blobs >= 4)
        #expect(lowestBlob > top + 0.0005, "a blob lies \(lowestBlob - top) m over the floor's top")
        withExtendedLifetime(stages) {}
    }
}
