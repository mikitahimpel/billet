import DecorInterface
import RealityKit
import simd

/// Where one of the room's own pieces stands now, against where it was built: a point modelled at the piece's
/// home follows it when it moves or turns.
struct PieceFrame: Equatable {
    let home: SIMD2<Float>
    let now: SIMD2<Float>
    let turns: Int

    /// Nil while the piece is stored.
    init?(_ id: String, in layout: DecorLayout) {
        guard let base = DecorItem.item(shopID: id)?.base, let placement = layout.placement(of: id) else { return nil }
        home = SIMD2(Float(DecorGrid.metres(base.u)), Float(DecorGrid.metres(base.v)))
        now = SIMD2(Float(DecorGrid.metres(placement.u)), Float(DecorGrid.metres(placement.v)))
        turns = placement.quarterTurns
    }

    var yaw: Float { Float(turns) * .pi / 2 }
    var orientation: simd_quatf { .y(yaw) }

    func map(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let local = SIMD2(point.x, point.z) - home
        let c = cos(yaw), s = sin(yaw)
        let turned = SIMD2(local.x * c + local.y * s, -local.x * s + local.y * c)
        let at = now + turned
        return [at.x, point.y, at.y]
    }
}

enum RoomPieces {
    /// The models' Glow_ parts and the light each gives off.
    static let glows: [String: (tone: UInt32, intensity: Float)] = [
        "Glow_window": (0xFFE0A0, 1.2), "Glow_lamp": (0xFFE2AE, 1.1), "Glow_jar": (0xFFE7B8, 0.6),
    ]
}
