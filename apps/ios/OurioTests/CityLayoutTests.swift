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
}
