import RealityKit
import UIKit

/// The kitchen the feed and water games are played in: two walls meeting in a corner behind her, a counter run along
/// both, a window with curtains, a shelf of jars, hanging utensils, a pendant lamp, a stool and a sack, on wood planks
/// and a rug. Built once from merged static meshes (a dozen draws, no lights, nothing moving) with baked contact blobs
/// where things meet the floor.
///
/// Built in the corner's own frame, metres: x along the back wall, z toward the player, y up from the floor. The
/// frame is turned by `yaw` about the play area so the left wall shows to the camera.
enum KitchenSet {
    static let yaw: Float = -0.45
    private static let backZ: Float = -0.40
    private static let leftX: Float = -0.40
    private static let counterDepth: Float = 0.14
    private static let counterTop: Float = 0.204
    private static let run: Float = 1.0

    private static let wood = 0xC4946A as UInt32
    private static let door = 0x9DB88A as UInt32
    private static let steel = 0xD6DEE4 as UInt32
    private static let cream = 0xFFF3E2 as UInt32

    @discardableResult
    static func build(in pivot: Entity, floorTop: Float) -> Entity {
        let root = pivot.group()
        root.box(3, 0.04, 3, r: 0.002, Clay.matte(0xD9AE78, roughness: 0.8), at: [0, 0, 0])
        let k = root.group(at: [0, floorTop, 0], rotation: .y(yaw))
        var b = MeshBatch()
        floor(&b)
        rug(&b)
        backCounter(&b)
        leftCounter(&b)
        window(&b)
        shelf(&b)
        utensils(&b)
        pendant(&b)
        fruitBowl(&b)
        stool(&b)
        sack(&b)
        b.commit(into: k)

        k.fadedWall(from: [leftX, 1.2], to: [leftX, backZ], height: 1.7, top: 0xD2B08A, bottom: 0xF6E6D0)
        k.fadedWall(from: [leftX, backZ], to: [run + 0.6, backZ], height: 1.7, top: 0xD2B08A, bottom: 0xF6E6D0)

        let shadows: [(SIMD3<Float>, Float, Float)] = [
            ([0.45, 0, backZ + 0.13], 2.0, 0.2), ([leftX + 0.13, 0, 0.3], 0.2, 1.4),
            ([0.24, 0, -0.19], 0.14, 0.14), ([-0.22, 0, -0.2], 0.17, 0.12), ([0.04, 0, -0.02], 0.62, 0.5),
        ]
        for (at, width, depth) in shadows { k.contactBlob(at: at, width: width, depth: depth, lift: 0.0026) }
        return root
    }

    private static func floor(_ b: inout MeshBatch) {
        let seam = 0xB98A5E as UInt32
        let tones: [UInt32] = [0xD9AE78, 0xCFA26A, 0xE0B884]
        let width: Float = 0.07
        var z = backZ
        var row = 0
        while z < 1.2 {
            b.box([2.2, 0.0016, width - 0.003], at: [0.5, 0.0008, z + width / 2], tones[row % 3], roughness: 0.75)
            b.box([2.2, 0.0018, 0.003], at: [0.5, 0.0009, z + width], seam, roughness: 0.9)
            var x = leftX + Float(row % 4) * 0.13
            while x < 1.5 {
                b.box([0.003, 0.0018, width], at: [x, 0.0009, z + width / 2], seam, roughness: 0.9)
                x += 0.52
            }
            z += width
            row += 1
        }
    }

    private static func rug(_ b: inout MeshBatch) {
        let center = SIMD3<Float>(0.04, 0, -0.02)
        b.box([0.56, 0.004, 0.44], at: center + [0, 0.0034, 0], 0xE9C9A0, roughness: 1)
        b.box([0.5, 0.0044, 0.38], at: center + [0, 0.0038, 0], 0xF3E6D2, roughness: 1)
        b.box([0.46, 0.0048, 0.01], at: center + [0, 0.0042, 0.15], 0xA9C27E, roughness: 1)
        b.box([0.46, 0.0048, 0.01], at: center + [0, 0.0042, -0.15], 0xA9C27E, roughness: 1)
        for i in 0..<18 {
            let x = center.x - 0.27 + Float(i) * 0.0318
            b.box([0.004, 0.003, 0.02], at: [x, 0.002, center.z + 0.23], 0xE9C9A0, roughness: 1)
            b.box([0.004, 0.003, 0.02], at: [x, 0.002, center.z - 0.23], 0xE9C9A0, roughness: 1)
        }
    }

    private static func cabinet(_ b: inout MeshBatch, center: SIMD3<Float>, width: Float, facing: Float, handle: Bool = true) {
        let turn = simd_quatf.y(facing)
        let height = counterTop - 0.014
        // The body stops under the worktop's underside: a top at the worktop's own height would be coplanar with it.
        let body = height - 0.014
        b.box([width, body, counterDepth - 0.01], at: center + turn.act([0, body / 2, 0]), rotation: turn, 0xE9DCC6)
        b.box([width - 0.012, height - 0.034, 0.008], at: center + turn.act([0, height / 2 + 0.008, counterDepth / 2 - 0.004]),
              rotation: turn, door, roughness: 0.6)
        if handle {
            b.box([0.05, 0.005, 0.008], at: center + turn.act([0, height - 0.026, counterDepth / 2 + 0.003]),
                  rotation: turn, steel, roughness: 0.3)
        }
    }

    private static func backCounter(_ b: inout MeshBatch) {
        b.box([run + 0.4, 0.014, counterDepth + 0.01], at: [(run - 0.4) / 2, counterTop - 0.007, backZ + (counterDepth + 0.01) / 2],
              wood, roughness: 0.6)
        b.box([run + 0.4, 0.014, 0.1], at: [(run - 0.4) / 2, 0.007, backZ + 0.06], 0x5B3A28, roughness: 0.9)
        var x = leftX + 0.07
        while x < run {
            cabinet(&b, center: [x, 0.014, backZ + counterDepth / 2], width: 0.14, facing: 0)
            x += 0.14
        }
        // Splashback of cream tiles with grout lines, up to the window's sill.
        b.box([run + 0.4, 0.056, 0.006], at: [(run - 0.4) / 2, counterTop + 0.028, backZ + 0.003], 0xCFE0D2, roughness: 0.35)
        for line in 0..<3 {
            b.box([run + 0.4, 0.0016, 0.0075], at: [(run - 0.4) / 2, counterTop + 0.014 + Float(line) * 0.018, backZ + 0.003],
                  cream, roughness: 0.6)
        }
        var x2 = leftX + 0.04
        var odd = false
        while x2 < run {
            for line in 0..<3 {
                let shift: Float = (line % 2 == 0) == odd ? 0 : 0.03
                b.box([0.0016, 0.018, 0.0075], at: [x2 + shift, counterTop + 0.005 + Float(line) * 0.018, backZ + 0.003],
                      cream, roughness: 0.6)
            }
            x2 += 0.06
            odd.toggle()
        }
        // A sink with a mixer tap, behind her left.
        b.box([0.17, 0.003, 0.1], at: [-0.2, counterTop + 0.0008, backZ + 0.075], steel, roughness: 0.25)
        b.box([0.145, 0.004, 0.078], at: [-0.2, counterTop + 0.003, backZ + 0.075], 0x8E9AA4, roughness: 0.3)
        b.cylinder(height: 0.07, radius: 0.005, at: [-0.2, counterTop + 0.035, backZ + 0.02], steel, roughness: 0.2)
        b.cylinder(height: 0.05, radius: 0.004, at: [-0.2, counterTop + 0.07, backZ + 0.045],
                   rotation: .x(.pi / 2), steel, roughness: 0.2)
        b.box([0.006, 0.02, 0.006], at: [-0.17, counterTop + 0.012, backZ + 0.02], 0xE8A08A, roughness: 0.4)
    }

    private static func leftCounter(_ b: inout MeshBatch) {
        // Starts where the back run's worktop ends, so the two tops never overlap in the corner.
        let start = backZ + counterDepth + 0.01
        let end: Float = 1.0
        b.box([counterDepth + 0.01, 0.014, end - start], at: [leftX + (counterDepth + 0.01) / 2, counterTop - 0.007, (start + end) / 2],
              wood, roughness: 0.6)
        b.box([0.1, 0.014, end - start], at: [leftX + 0.06, 0.007, (start + end) / 2], 0x5B3A28, roughness: 0.9)
        var z = start + 0.07
        while z < end {
            cabinet(&b, center: [leftX + counterDepth / 2, 0.014, z], width: 0.14, facing: .pi / 2)
            z += 0.14
        }
        // A two-ring hob with a pot on it.
        let hob = SIMD3<Float>(leftX + 0.075, counterTop, 0.02)
        b.box([0.11, 0.004, 0.12], at: hob + [0, 0.002, 0], 0x2B323A, roughness: 0.3)
        for z: Float in [-0.03, 0.03] {
            b.cylinder(height: 0.003, radius: 0.025, at: hob + [0, 0.0045, z], 0x4A5560, roughness: 0.4)
            b.cylinder(height: 0.004, radius: 0.012, at: hob + [0, 0.0055, z], 0x2B323A, roughness: 0.4)
        }
        b.cylinder(height: 0.05, radius: 0.03, at: hob + [0, 0.029, -0.03], 0xE98A5B, roughness: 0.35)
        b.cylinder(height: 0.006, radius: 0.032, at: hob + [0, 0.057, -0.03], 0xD8653F, roughness: 0.35)
        b.sphere(radius: 0.006, at: hob + [0, 0.064, -0.03], 0xFFF3E2, roughness: 0.4)
        for side: Float in [-1, 1] {
            b.box([0.014, 0.006, 0.006], at: hob + [0, 0.04, -0.03 + side * 0.034], 0x5B3A28, roughness: 0.6)
        }
        // Tiles behind the hob, on the left wall.
        b.box([0.006, 0.056, end - start], at: [leftX + 0.003, counterTop + 0.028, (start + end) / 2], 0xCFE0D2, roughness: 0.35)
    }

    private static func window(_ b: inout MeshBatch) {
        let c = SIMD3<Float>(0.06, 0.375, backZ)
        let w: Float = 0.28, h: Float = 0.2
        b.box([w + 0.03, h + 0.03, 0.01], at: c + [0, 0, 0.005], cream, roughness: 0.5)
        b.box([w, h, 0.012], at: c + [0, 0, 0.006], 0xFFE2B0, roughness: 0.2)
        b.box([0.008, h, 0.016], at: c + [0, 0, 0.008], cream, roughness: 0.5)
        b.box([w, 0.008, 0.016], at: c + [0, 0.02, 0.008], cream, roughness: 0.5)
        b.box([w + 0.06, 0.012, 0.045], at: c + [0, -h / 2 - 0.016, 0.022], cream, roughness: 0.5)
        // The sill's plant: a terracotta pot and a fan of leaves.
        let pot = c + SIMD3<Float>(-0.07, -h / 2 + 0.002, 0.03)
        b.cylinder(height: 0.034, radius: 0.019, at: pot + [0, 0.012, 0], 0xC7744A, roughness: 0.7)
        b.cylinder(height: 0.008, radius: 0.022, at: pot + [0, 0.032, 0], 0xB8643C, roughness: 0.7)
        for i in 0..<7 {
            let t = Float(i) / 6 - 0.5
            let tone: UInt32 = i % 2 == 0 ? 0x6F8A4E : 0x93A86A
            b.box([0.012, 0.07 + Float(i % 3) * 0.012, 0.004], at: pot + [t * 0.05, 0.075, Float(i % 2) * 0.006 - 0.003],
                  rotation: .z(-t * 0.9), tone, roughness: 0.8)
        }
        // Curtains on a rod: two panels, folds as stripes, tied back.
        let rod = c + SIMD3<Float>(0, h / 2 + 0.035, 0.035)
        b.cylinder(height: w + 0.12, radius: 0.004, at: rod, rotation: .z(.pi / 2), 0x8A5A3C)
        for side: Float in [-1, 1] {
            for i in 0..<4 {
                let x = side * (w / 2 + 0.005 - Float(i) * 0.011)
                b.cylinder(height: 0.2, radius: 0.0075, at: rod + [x + (side * 0.012), -0.1, Float(i % 2) * 0.005],
                           i % 2 == 0 ? 0xF4D6B8 : 0xEBC9A8, roughness: 1, sides: 8)
            }
            b.box([0.05, 0.008, 0.02], at: rod + [side * (w / 2 - 0.02), -0.125, 0.008], 0xF0663A, roughness: 0.6)
        }
    }

    private static func shelf(_ b: inout MeshBatch) {
        let y: Float = 0.34
        b.box([0.2, 0.012, 0.06], at: [-0.22, y, backZ + 0.03], wood, roughness: 0.6)
        for x: Float in [-0.3, -0.14] {
            b.box([0.006, 0.03, 0.012], at: [x, y - 0.02, backZ + 0.008], 0x5B3A28, roughness: 0.8)
        }
        let jars: [(Float, UInt32, Float)] = [(-0.3 + 0.026, 0xE9C9A0, 0.05), (-0.236, 0xF2A65E, 0.04), (-0.19, 0xA9C27E, 0.058), (-0.15, 0xE8A08A, 0.036)]
        for (x, tone, height) in jars {
            b.cylinder(height: height, radius: 0.016, at: [x, y + 0.006 + height / 2, backZ + 0.032], tone, roughness: 0.3)
            b.cylinder(height: 0.008, radius: 0.017, at: [x, y + 0.006 + height + 0.004, backZ + 0.032], 0xC96F4A, roughness: 0.6)
        }
    }

    private static func utensils(_ b: inout MeshBatch) {
        let rail = SIMD3<Float>(0.285, 0.44, backZ + 0.02)
        b.cylinder(height: 0.12, radius: 0.0035, at: rail, rotation: .z(.pi / 2), steel, roughness: 0.3)
        b.sphere(radius: 0.006, at: rail + [-0.06, 0, 0], steel, roughness: 0.3)
        b.sphere(radius: 0.006, at: rail + [0.06, 0, 0], steel, roughness: 0.3)
        // A ladle, a spatula and a whisk on hooks.
        b.cylinder(height: 0.09, radius: 0.0025, at: rail + [-0.04, -0.05, 0.002], 0x8A5A3C)
        b.sphere(radius: 0.014, at: rail + [-0.04, -0.105, 0.002], scale: [1, 0.6, 1], steel, roughness: 0.3)
        b.cylinder(height: 0.08, radius: 0.0025, at: rail + [0, -0.045, 0.002], 0x8A5A3C)
        b.box([0.024, 0.04, 0.003], at: rail + [0, -0.1, 0.002], 0xE98A5B, roughness: 0.5)
        b.cylinder(height: 0.05, radius: 0.0025, at: rail + [0.04, -0.03, 0.002], 0x8A5A3C)
        b.sphere(radius: 0.014, at: rail + [0.04, -0.075, 0.002], scale: [0.8, 1.3, 0.5], steel, roughness: 0.3)
    }

    private static func pendant(_ b: inout MeshBatch) {
        let at = SIMD3<Float>(0.06, 0.42, backZ + 0.18)
        b.cylinder(height: 1.4, radius: 0.0012, at: at + [0, 0.7, 0], 0x2B323A)
        b.cylinder(height: 0.045, radius: 0.036, at: at + [0, 0.0225, 0], 0xE98A5B, roughness: 0.4, sides: 18)
        b.cylinder(height: 0.006, radius: 0.037, at: at + [0, 0.002, 0], cream, roughness: 0.4, sides: 18)
        b.sphere(radius: 0.012, at: at + [0, -0.008, 0], 0xFFE9B8, roughness: 0.3)
    }

    private static func fruitBowl(_ b: inout MeshBatch) {
        let at = SIMD3<Float>(0.14, counterTop, backZ + 0.085)
        b.cylinder(height: 0.02, radius: 0.036, at: at + [0, 0.01, 0], 0xD8653F, roughness: 0.4, sides: 18)
        b.cylinder(height: 0.006, radius: 0.044, at: at + [0, 0.023, 0], 0xE98A5B, roughness: 0.4, sides: 18)
        let fruit: [(SIMD3<Float>, UInt32)] = [([-0.014, 0.038, 0], 0xE04F3A), ([0.014, 0.037, 0.005], 0xF2A65E),
                                               ([0, 0.04, -0.012], 0xE9D24F), ([0.002, 0.05, 0.004], 0x93A86A),
                                               ([-0.008, 0.038, 0.014], 0xE04F3A)]
        for (offset, tone) in fruit { b.sphere(radius: 0.015, at: at + offset, tone, roughness: 0.45) }
    }

    private static func stool(_ b: inout MeshBatch) {
        let at = SIMD3<Float>(0.24, 0, -0.19)
        b.cylinder(height: 0.012, radius: 0.045, at: at + [0, 0.114, 0], wood, roughness: 0.6, sides: 18)
        b.cylinder(height: 0.008, radius: 0.04, at: at + [0, 0.124, 0], 0xE98A5B, roughness: 0.9, sides: 18)
        for i in 0..<4 {
            let a = Float(i) * .pi / 2 + .pi / 4
            b.box([0.008, 0.11, 0.008], at: at + [cos(a) * 0.03, 0.055, sin(a) * 0.03],
                  rotation: simd_quatf.z(-cos(a) * 0.12) * simd_quatf.x(sin(a) * 0.12), 0x8A5A3C, roughness: 0.7)
        }
    }

    private static func sack(_ b: inout MeshBatch) {
        let turn = simd_quatf.y(0.5)
        let at = SIMD3<Float>(-0.22, 0, -0.2)
        b.box([0.07, 0.11, 0.045], at: at + [0, 0.055, 0], rotation: turn, 0xC96F4A, roughness: 0.85)
        b.box([0.072, 0.014, 0.036], at: at + turn.act([0, 0.116, 0]), rotation: turn, 0xA8573A, roughness: 0.9)
        b.box([0.044, 0.05, 0.002], at: at + turn.act([0, 0.055, 0.0235]), rotation: turn, cream, roughness: 0.7)
        b.sphere(radius: 0.007, at: at + turn.act([0, 0.05, 0.0255]), scale: [1.2, 1, 0.3], 0xC96F4A)
    }
}
