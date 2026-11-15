import DecorInterface
import Testing
@testable import Billet

struct CityLayoutTests {
    @Test func noTwoPiecesOfBedroomFurnitureOverlap() {
        let pieces = CityLayout.pieces
        for a in pieces.indices {
            for b in pieces.indices where b > a {
                #expect(!CityLayout.overlap(pieces[a], pieces[b]), "\(pieces[a].name) overlaps \(pieces[b].name)")
            }
        }
    }

    @Test func theBedStandsClearOfTheSillOnFreeFloor() {
        let bed = CityLayout.bed, sill = CityLayout.sill
        // Its back edge is in front of the sill's front face, so nothing hangs over it.
        #expect(bed.at.y - bed.half.y >= sill.at.y + sill.half.y)
    }

    @Test func everyFloorStandingPieceIsInsideTheWalls() {
        for piece in CityLayout.pieces where piece.name != "sill" {
            #expect(CityLayout.inside(piece), "\(piece.name) pokes into a wall")
        }
    }

    @Test func theRugLiesBesideTheBedNotUnderIt() {
        #expect(CityLayout.rugClearsBed())
    }

    @Test func theBedroomCatalogStartsWhereTheSceneBuildsIt() {
        let built: [(String, SIMD2<Float>)] = [
            ("base-bedroom-bed", CityLayout.bed.at), ("base-bedroom-nightstand", CityLayout.nightstand.at),
            ("base-bedroom-dresser", CityLayout.dresser.at), ("base-bedroom-catbed", CityLayout.catBed.at),
            ("base-bedroom-rug", CityLayout.rug.at),
        ]
        let layout = DecorLayout()
        for (id, at) in built {
            let spot = layout.placement(of: id)
            #expect(spot != nil, "\(id)")
            guard let spot else { continue }
            #expect(abs(Float(DecorGrid.metres(spot.u)) - at.x) <= Float(DecorGrid.step), "\(id) x")
            #expect(abs(Float(DecorGrid.metres(spot.v)) - at.y) <= Float(DecorGrid.step), "\(id) z")
        }
    }
}
