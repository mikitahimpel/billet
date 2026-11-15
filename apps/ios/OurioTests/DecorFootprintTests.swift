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
    /// The monstera is the exception: its footprint is its pot (`CORE` in tools/decor-lod/catalog.py), not its leaves.
    @Test(arguments: DecorItem.all.filter { !$0.isBase && $0.id != "monstera" })
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
        let layout = DecorLayout(stored: DecorLayout().stored).putting(
            Placement(item: "print", surface: .backWall, u: 3))
        let bounds = try await drawnBounds(of: "print", in: layout)
        #expect(abs(bounds.min.z + 0.5) < 0.002, "its back is on the wall: \(bounds.min.z)")
    }

    /// The seat hangs on the window wall on corbels, with nothing under it to the floor. At home, and wherever it is
    /// put back after a move, its back reaches the wall under the window.
    @Test(arguments: [false, true])
    func theWindowSeatsBackIsOnTheWallAndNothingStandsUnderIt(moved: Bool) async throws {
        var layout = DecorLayout()
        if moved {
            let home = try #require(layout.placement(of: "base-windowseat"))
            layout = layout.putting(home.moved(to: .floor, u: -2, v: 0))
            let back = try #require(layout.nearestFit(to: home))
            layout = layout.putting(back)
        }
        let bounds = try await drawnBounds(of: "base-windowseat", in: layout)
        #expect(bounds.min.x <= -0.5 + 0.002, "its back is on the wall: \(bounds.min.x)")
        #expect(bounds.min.y > 0.15, "nothing reaches down to the floor: \(bounds.min.y)")
    }

    private func drawnBounds(of id: String, in layout: DecorLayout) async throws -> BoundingBox {
        let stage = DecorStage()
        stage.apply(RoomDecor(layout: layout), receiver: nil)
        var holder: Entity?
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(50))
            stage.apply(RoomDecor(layout: layout), receiver: nil)
            holder = stage.root.children.first { $0.name == "decor.\(id)" }
            if holder?.children.isEmpty == false { break }
        }
        return try #require(holder).visualBounds(relativeTo: stage.root)
    }
}
