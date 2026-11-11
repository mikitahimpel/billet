import DecorInterface
import RealityKit
import Testing
import simd

@testable import Billet

struct RoomPiecesTests {
    private func at(_ id: String, _ u: Int, _ v: Int, _ turns: Int = 0) -> Placement {
        Placement(item: id, surface: .floor, u: u, v: v, quarterTurns: turns)
    }

    @Test func aPieceAtHomeMapsEveryPointToItself() throws {
        let frame = try #require(PieceFrame("base-cattree", in: DecorLayout()))
        let point: SIMD3<Float> = [0.36, 0.396, -0.36]
        #expect(simd_distance(frame.map(point), point) < 1e-5)
    }

    @Test func aMovedPieceCarriesItsPointsAlong() throws {
        let frame = try #require(PieceFrame("base-cattree", in: DecorLayout().putting(at("base-cattree", 7, 0))))
        let top = frame.map([0.36, 0.396, -0.36])
        #expect(abs(top.x - 0.36) < 1e-5 && abs(top.z - 0.34) < 1e-5 && top.y == 0.396)
    }

    @Test func aTurnedPieceSwingsItsPointsAroundItsMiddle() throws {
        let frame = try #require(PieceFrame("base-basket", in: DecorLayout().putting(at("base-basket", 7, 7, 2))))
        let visit = frame.map([0.27, 0.014, 0.26])
        #expect(abs(visit.x - 0.43) < 1e-4 && abs(visit.z - 0.44) < 1e-4)
    }

    @Test func aStoredPieceHasNoFrame() {
        #expect(PieceFrame("base-cattree", in: DecorLayout().storing("base-cattree")) == nil)
    }

    @MainActor @Test func everyBaseModelIsInTheBundle() async throws {
        for item in DecorItem.baseItems {
            _ = try await Entity(named: item.assetName, in: .main)
        }
    }
}
