import DecorInterface
import RealityKit
import RoomInterface
import Testing

@testable import Billet

/// A piece lies where the layout says it does: the model the stage draws is the size the catalog (and so the
/// placement rules) say, and a wall piece's back lies on the wall.
@MainActor
struct DecorFootprintTests {
    /// The catalog's footprint was measured on the full-detail model; the lean copy the room draws must match it, or
    /// a piece stands off the wall it is placed against.
    @Test(arguments: DecorItem.all.filter { !$0.isBase })
    func theModelTheStageDrawsIsTheSizeTheCatalogSays(item: DecorItem) async throws {
        let model = try await Entity(named: item.assetName, in: .main)
        let bounds = model.visualBounds(relativeTo: nil)
        let measure = item.fit == .width ? bounds.extents.x : bounds.extents.y
        let scale = Float(item.size) / measure
        let tolerance: Float = 0.012
        #expect(abs(bounds.extents.x * scale - Float(item.width)) <= tolerance, "\(item.id) width")
        if item.mount == .floor {
            #expect(abs(bounds.extents.z * scale - Float(item.depth)) <= tolerance, "\(item.id) depth")
            #expect(abs(bounds.extents.y * scale - Float(item.height)) <= 0.02, "\(item.id) height")
        }
    }

    @Test func aWallPieceLiesAgainstTheWallItIsHungOn() async throws {
        let stage = DecorStage()
        let layout = DecorLayout(stored: DecorLayout().stored).putting(
            Placement(item: "print", surface: .backWall, u: 3))
        stage.apply(RoomDecor(layout: layout), receiver: nil)
        var holder: Entity?
        for _ in 0..<200 where holder?.children.contains(where: { $0.name != "" }) != true {
            try await Task.sleep(for: .milliseconds(50))
            stage.apply(RoomDecor(layout: layout), receiver: nil)
            holder = stage.root.children.first { $0.name == "decor.print" }
            if holder?.children.isEmpty == false { break }
        }
        let piece = try #require(holder)
        let bounds = piece.visualBounds(relativeTo: stage.root)
        #expect(abs(bounds.min.z + 0.5) < 0.002, "its back is on the wall: \(bounds.min.z)")
    }
}
