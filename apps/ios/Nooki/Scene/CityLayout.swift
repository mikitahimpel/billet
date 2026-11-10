import simd

/// Where the Bedroom's large furniture stands, in the room's pivot space (metres, the floor's top at y 0.014). The
/// scene builds from these and a test checks that no two pieces overlap and each stands inside the walls.
enum CityLayout {
    struct Piece {
        let name: String
        /// Centre on the floor.
        let at: SIMD2<Float>
        /// Half the length along x and z.
        let half: SIMD2<Float>
        /// Lowest and highest point above the pivot's origin.
        let height: ClosedRange<Float>
    }

    /// The inside faces of the walls, and the window wall's sill: the back wall is at z -0.5, the left wall at x -0.5.
    static let walls = (minX: Float(-0.5), minZ: Float(-0.5), maxX: Float(0.5), maxZ: Float(0.5))

    static let bed = Piece(name: "bed", at: [0.06, -0.17], half: [0.38, 0.18], height: 0.014...0.215)
    static let nightstand = Piece(name: "nightstand", at: [-0.415, -0.17], half: [0.067, 0.067], height: 0.014...0.29)
    /// The window sill with its apron and corbels: its front face is at z -0.37, over nothing.
    static let sill = Piece(name: "sill", at: [0, -0.44], half: [0.45, 0.07], height: 0.218...0.30)
    static let dresser = Piece(name: "dresser", at: [-0.44, 0.28], half: [0.06, 0.12], height: 0.014...0.184)
    static let catBed = Piece(name: "cat bed", at: [0.28, 0.27], half: [0.115, 0.115], height: 0.014...0.07)
    static let rug = (at: SIMD2<Float>(0.04, 0.24), radius: Float(0.22))

    static let pieces = [bed, nightstand, sill, dresser, catBed]

    static func overlap(_ a: Piece, _ b: Piece) -> Bool {
        abs(a.at.x - b.at.x) < a.half.x + b.half.x && abs(a.at.y - b.at.y) < a.half.y + b.half.y
            && a.height.overlaps(b.height)
    }

    static func inside(_ piece: Piece) -> Bool {
        piece.at.x - piece.half.x >= walls.minX && piece.at.x + piece.half.x <= walls.maxX
            && piece.at.y - piece.half.y >= walls.minZ && piece.at.y + piece.half.y <= walls.maxZ
    }

    /// The rug lies under the cat bed and beside the bed, so it must clear the bed's footprint only.
    static func rugClearsBed() -> Bool {
        let dx = max(abs(rug.at.x - bed.at.x) - bed.half.x, 0), dz = max(abs(rug.at.y - bed.at.y) - bed.half.y, 0)
        return (dx * dx + dz * dz).squareRoot() >= rug.radius
    }
}
