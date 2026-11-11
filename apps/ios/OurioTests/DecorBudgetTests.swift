import DecorInterface
import RealityKit
import Testing

@testable import Billet

/// What keeps the pieces a player stands in the room cheap: each light model is one small mesh, so a full room
/// stays inside the draw budget of a phone.
@MainActor
struct DecorBudgetTests {
    private func counts(_ entity: Entity) -> (triangles: Int, parts: Int) {
        var triangles = 0, parts = 0
        func visit(_ entity: Entity) {
            if let mesh = entity.components[ModelComponent.self]?.mesh {
                for model in mesh.contents.models {
                    for part in model.parts {
                        parts += 1
                        triangles += (part.triangleIndices?.count ?? 0) / 3
                    }
                }
            }
            entity.children.forEach(visit)
        }
        visit(entity)
        return (triangles, parts)
    }

    @Test(arguments: DecorItem.all.filter { !$0.isBase })
    func everyPieceFitsItsBudget(item: DecorItem) async throws {
        let model = try await Entity(named: item.assetName, in: .main)
        let (triangles, parts) = counts(model)
        #expect(triangles > 0)
        #expect(triangles <= DecorItem.triangleBudget, "\(item.id) has \(triangles) triangles")
        #expect(parts <= DecorItem.partBudget, "\(item.id) has \(parts) parts")
    }

    /// The room's own pieces were one model of about this many triangles before they were split; split they stay
    /// under it.
    @Test func theRoomsOwnPiecesAreNoHeavierThanTheModelTheyCameFrom() async throws {
        var triangles = 0
        for item in DecorItem.baseItems {
            triangles += counts(try await Entity(named: item.assetName, in: .main)).triangles
        }
        #expect(triangles > 0)
        #expect(triangles <= 150_000, "\(triangles) triangles")
    }

    @Test func aFullRoomStaysInTheWholeBudget() {
        #expect(DecorLayout.maxPlaced * DecorItem.triangleBudget <= 40_000)
    }
}
