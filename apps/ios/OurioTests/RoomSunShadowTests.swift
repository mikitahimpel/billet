import RealityKit
import Testing
import UIKit

@testable import Billet

/// The Home rooms' sun casts into a fixed box: a map that does not follow what moves, and that holds the whole room.
@MainActor
struct RoomSunShadowTests {
    private static func sun(of room: CatRoom) -> (Entity, DirectionalLightComponent.Shadow)? {
        var found: (Entity, DirectionalLightComponent.Shadow)?
        room.root.forEachDescendant {
            if let shadow = $0.components[DirectionalLightComponent.Shadow.self] { found = ($0, shadow) }
        }
        return found
    }

    @Test func everyHomeSunCastsIntoAFixedBox() {
        for room in [DioramaScene() as CatRoom, CityRoomScene(), BoardRoomScene()] {
            var maps = 0
            room.root.forEachDescendant { if $0.components.has(DirectionalLightComponent.Shadow.self) { maps += 1 } }
            #expect(maps == 1, "\(type(of: room))")
            #expect(Self.sun(of: room)?.1.shadowProjection == CatRoom.sunShadowProjection, "\(type(of: room))")
        }
    }

    /// Everything in the room lies inside the box, so no shadow ends at its edge: the Bedroom's at every hour of its
    /// sun (placed as `CityRoomScene.applyLight` does), the others at their one sun.
    @Test func theBoxHoldsTheWholeRoom() throws {
        guard case .fixed(let near, let far, let scale) = CatRoom.sunShadowProjection else {
            Issue.record("not a fixed box")
            return
        }
        func check(_ room: CatRoom, _ label: String) throws {
            let (sun, _) = try #require(Self.sun(of: room))
            let bounds = room.pivot.visualBounds(relativeTo: sun)
            let side = max(abs(bounds.min.x), abs(bounds.max.x), abs(bounds.min.y), abs(bounds.max.y))
            #expect(side < scale, "\(label): the room reaches \(side) m off the sun's axis")
            #expect(-bounds.max.z > near && -bounds.min.z < far, "\(label): depth \(-bounds.max.z) to \(-bounds.min.z) m")
        }
        try check(DioramaScene(), "living")
        try check(BoardRoomScene(), "desk")
        let bedroom = CityRoomScene()
        let (sun, _) = try #require(Self.sun(of: bedroom))
        for hour in 0..<24 {
            sun.look(at: .zero, from: Daylight.sample(Float(hour)).lightDirection * 3, relativeTo: bedroom.pivot)
            try check(bedroom, "bedroom at \(hour):00")
        }
    }
}
