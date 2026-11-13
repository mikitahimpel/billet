import DecorInterface
import RealityKit

/// The Bedroom's own furniture, one entity tree per piece with its origin on the floor under its middle, so the stage
/// can stand each where the player put it. Meshes and materials are the shared ones the scene's primitives hand out.
enum BedroomFurniture {
    static let lampShade = "bedroomLampShade"
    static let lampLight = "bedroomLampLight"
    static let shadeTone: UInt32 = 0xF7ECD8

    static func build(_ item: DecorItem) -> Entity? {
        let piece = Entity()
        piece.name = item.id
        switch item.id {
        case "base-bedroom-bed": bed(piece)
        case "base-bedroom-nightstand": nightstand(piece)
        case "base-bedroom-dresser": dresser(piece)
        case "base-bedroom-catbed": Props.catBed(piece, at: .zero, scale: 0.6)
        case "base-bedroom-rug": rug(piece)
        case "base-bedroom-bowls": Props.catBowls(piece, at: .zero, rotation: .y(.pi / 2))
        case "base-bedroom-slippers": Props.slippers(piece, at: .zero, rotation: .y(-0.4))
        case "base-bedroom-books":
            Props.bookStack(piece, at: .zero, tones: [0x6F8FB0, 0xC0563A, 0xE3B45C], rotation: .y(-0.4))
        case "base-bedroom-mouse": Props.toyMouse(piece, at: [0, 0.009, 0], rotation: .y(0.8))
        default: return nil
        }
        return piece
    }

    /// Pillow on the left, blanket over the right, a plush against the wall.
    private static func bed(_ bed: Entity) {
        bed.box(0.76, 0.1, 0.36, r: 0.02, Clay.matte(0xE8D2B2), at: [0, 0.05, 0])
        bed.box(0.72, 0.07, 0.33, r: 0.03, Clay.matte(0xFBF0DE, roughness: 1), at: [0, 0.13, 0])
        let blanket = Clay.matte(0xE98A5B, roughness: 1)
        bed.box(0.44, 0.04, 0.35, r: 0.018, blanket, at: [0.15, 0.17, 0.005])
        bed.box(0.04, 0.08, 0.35, r: 0.018, blanket, at: [0.37, 0.13, 0.005])
        bed.box(0.15, 0.05, 0.25, r: 0.024, Clay.matte(0xF4E2C8, roughness: 1), at: [-0.26, 0.19, -0.01], rotation: .y(0.08))
        bed.box(0.12, 0.012, 0.2, r: 0.005, Clay.matte(0xF6C69E, roughness: 1), at: [-0.05, 0.172, 0.04])
        Props.plush(bed, at: [-0.22, 0.166, -0.11], rotation: .y(-0.8))
    }

    /// A slatted crate with the lamp on it. The shade and the light are found by name, to follow the hour.
    private static func nightstand(_ n: Entity) {
        let slat = Clay.matte(0xB84F30)
        n.box(0.13, 0.15, 0.13, r: 0.008, Clay.matte(0xD8653F), at: [0, 0.075, 0])
        for y: Float in [0.04, 0.09, 0.135] { n.box(0.134, 0.012, 0.134, r: 0.004, slat, at: [0, y, 0]) }
        n.cylinder(0.01, 0.03, Clay.matte(0x6D4C3A), at: [0, 0.155, 0])
        n.cylinder(0.08, 0.005, Clay.matte(0x6D4C3A), at: [0, 0.2, 0])
        n.cylinder(0.065, 0.0475, Clay.glow(shadeTone, intensity: 0.2), at: [0, 0.255, 0]).name = lampShade
        n.group(at: [0.02, 0.26, 0.03]).name = lampLight
        n.box(0.05, 0.03, 0.07, r: 0.004, Clay.matte(0x7C9A7E), at: [0.035, 0.165, 0.03], rotation: .y(0.2))
    }

    private static func dresser(_ d: Entity) {
        Props.dresser(d, at: .zero, length: 0.24)
        Props.radio(d, at: [0, 0.17, -0.08], rotation: .identity)
        Props.snakePlant(d, at: [0, 0.17, 0.07], pot: 0xE9D9B8)
        Props.bookStack(d, at: [0.01, 0.17, 0], tones: [0xE98A5B, 0xF2D3A0], rotation: .y(0.3))
    }

    /// Round, in rings like the Living room's rug; flat, so the cat walks over it.
    private static func rug(_ rug: Entity) {
        rug.cylinder(0.006, 0.22, Clay.matte(0xC39A69, roughness: 1), at: [0, 0.002, 0])
        rug.cylinder(0.008, 0.2, Clay.matte(0xDDB98A, roughness: 1), at: [0, 0.005, 0])
        rug.cylinder(0.009, 0.15, Clay.matte(0xEFC99C, roughness: 1), at: [0, 0.0055, 0])
        rug.cylinder(0.010, 0.11, Clay.matte(0xDDB98A, roughness: 1), at: [0, 0.006, 0])
    }
}
