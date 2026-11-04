import RealityKit
import UIKit
import simd

/// Clay props for the rooms, ported from idol-scenes/src/three/props.js. Each is built around its own origin with its
/// base on y = 0 (wall pieces: back on x = 0, facing +X).
enum Props {
    private enum Leaf {
        static let light: UInt32 = 0x93A86A
        static let dark: UInt32 = 0x6F8A4E
    }

    /// props.js's local cone helper: a frustum of two radii, or a real cone when the top is a point.
    @discardableResult
    private static func cone(_ parent: Entity, _ height: Float, _ top: Float, _ bottom: Float,
                             _ material: some Material, at position: SIMD3<Float>,
                             rotation: simd_quatf = .identity) -> ModelEntity {
        if top == 0 {
            return parent.model(MeshResource.generateCone(height: height, radius: bottom), material,
                                at: position, rotation: rotation)
        }
        return parent.cylinder(height, (top + bottom) / 2, material, at: position, rotation: rotation)
    }

    /// A small potted plant: a bunch of upright blades.
    static func snakePlant(_ parent: Entity, at position: SIMD3<Float>, pot: UInt32 = 0xC7744A) {
        let g = parent.group(at: position)
        cone(g, 0.05, 0.025, 0.02, Clay.matte(pot), at: [0, 0.025, 0])
        for i in 0..<7 {
            let a = Float(i) / 7 * 2 * .pi
            g.sphere(0.045, Clay.matte(i % 2 == 0 ? Leaf.light : Leaf.dark),
                     at: [cos(a) * 0.01, 0.085 + Float(i % 3) * 0.012, sin(a) * 0.01],
                     scale: [0.17, 1.15, 0.07],
                     rotation: .y(-a) * .z(-0.22 - Float(i % 3) * 0.1))
        }
    }

    static func cactus(_ parent: Entity, at position: SIMD3<Float>) {
        let g = parent.group(at: position)
        g.cylinder(0.03, 0.018, Clay.matte(0xD8653F), at: [0, 0.015, 0])
        g.sphere(0.016, Clay.matte(Leaf.light), at: [0, 0.045, 0], scale: [1, 1.5, 1])
        g.sphere(0.009, Clay.matte(Leaf.light), at: [0.014, 0.05, 0], scale: [1, 1.4, 1])
        g.sphere(0.005, Clay.matte(0xF3A0B5), at: [0, 0.07, 0])
    }

    /// Books standing in a row along +X, leaning a little at the end.
    static func bookRow(_ parent: Entity, at position: SIMD3<Float>, tones: [UInt32], rotation: simd_quatf) {
        let g = parent.group(at: position, rotation: rotation)
        var x: Float = 0
        for (i, tone) in tones.enumerated() {
            let h = 0.06 + Float((i * 7) % 3) * 0.01
            let w = 0.014 + Float(i % 2) * 0.005
            let lean: Float = i == tones.count - 1 ? -0.25 : 0
            g.box(w, h, 0.05, r: 0.003, Clay.matte(tone),
                  at: [x + w / 2 + (lean != 0 ? 0.008 : 0), h / 2, 0], rotation: .z(lean))
            x += w + 0.002
        }
    }

    static func bookStack(_ parent: Entity, at position: SIMD3<Float>, tones: [UInt32], rotation: simd_quatf) {
        let g = parent.group(at: position, rotation: rotation)
        var y: Float = 0
        for (i, tone) in tones.enumerated() {
            let h = 0.012 + Float(i % 2) * 0.004
            g.box(0.07 - Float(i) * 0.004, h, 0.05, r: 0.003, Clay.matte(tone), at: [0, y + h / 2, 0],
                  rotation: .y(Float((i * 5) % 3 - 1) * 0.12))
            y += h
        }
    }

    /// A framed picture on a wall facing +X: a tiny landscape with hills and a sun.
    static func picture(_ parent: Entity, at position: SIMD3<Float>, width: Float = 0.1, height: Float = 0.08,
                        sky: UInt32 = 0xF6C89A, hill: UInt32 = 0x9DB08A, sun: UInt32 = 0xF0663A) {
        let g = parent.group(at: position)
        g.box(0.008, height, width, r: 0.002, Clay.matte(0x8A5A3C), at: [0.004, 0, 0])
        g.box(0.004, height - 0.014, width - 0.014, r: 0.001, Clay.matte(sky, roughness: 1), at: [0.009, 0, 0])
        g.sphere(0.03, Clay.matte(hill, roughness: 1), at: [0.009, -height / 2 + 0.005, -width * 0.15],
                 scale: [0.1, 0.5, 1])
        g.sphere(0.025, Clay.matte(0x7F9A5A, roughness: 1), at: [0.01, -height / 2 + 0.004, width * 0.2],
                 scale: [0.1, 0.55, 1])
        g.sphere(0.009, Clay.matte(sun, roughness: 1), at: [0.011, height * 0.12, width * 0.18],
                 scale: [0.3, 1, 1])
    }

    /// A round wall clock facing +X; the returned setter takes the hour and moves the hands.
    static func wallClock(_ parent: Entity, at position: SIMD3<Float>, radius: Float = 0.045) -> (Float) -> Void {
        let g = parent.group(at: position)
        let facing = simd_quatf.z(.pi / 2)
        g.cylinder(0.012, radius, Clay.matte(0xD8653F), at: [0.006, 0, 0], rotation: facing)
        g.cylinder(0.004, radius * 0.86, Clay.matte(0xFBF1E3, roughness: 0.6), at: [0.013, 0, 0], rotation: facing)
        for i in 0..<12 {
            let a = Float(i) / 12 * .pi * 2
            g.box(0.002, i % 3 == 0 ? 0.01 : 0.005, 0.003, r: 0.0005, Clay.matte(0x5B3A28),
                  at: [0.016, cos(a) * radius * 0.7, -sin(a) * radius * 0.7], rotation: .x(-a))
        }
        let hand = { (length: Float, width: Float, x: Float) -> Entity in
            let pivot = g.group(at: [x, 0, 0])
            pivot.box(0.002, length, width, r: 0.0008, Clay.matte(0x5B3A28), at: [0, length / 2 - 0.004, 0])
            return pivot
        }
        let hours = hand(radius * 0.5, 0.005, 0.017)
        let minutes = hand(radius * 0.72, 0.0035, 0.019)
        g.sphere(0.004, Clay.matte(0xD8653F), at: [0.02, 0, 0])
        // Seen from +X, clockwise runs from +Y toward -Z: a negative turn about +X.
        return { hour in
            hours.orientation = .x(-((hour.truncatingRemainder(dividingBy: 12)) / 12) * .pi * 2)
            minutes.orientation = .x(-(hour.truncatingRemainder(dividingBy: 1)) * .pi * 2)
        }
    }

    /// A wall shelf facing +X on two brackets, `length` along Z.
    static func wallShelf(_ parent: Entity, at position: SIMD3<Float>, length: Float = 0.3) {
        let g = parent.group(at: position)
        let wood = Clay.matte(0xC4946A)
        g.box(0.07, 0.014, length, r: 0.004, wood, at: [0.035, 0, 0])
        for z: Float in [-length / 2 + 0.04, length / 2 - 0.04] {
            g.box(0.045, 0.006, 0.008, r: 0.002, Clay.matte(0x5B3A28), at: [0.023, -0.02, z], rotation: .z(0.75))
        }
    }

    /// Two bunched curtains hanging from a rod across the window, `width` along X, facing +Z.
    static func curtains(_ parent: Entity, at position: SIMD3<Float>, width: Float, drop: Float,
                         tone: UInt32 = 0xF4D6B8) {
        let g = parent.group(at: position)
        g.cylinder(width + 0.1, 0.005, Clay.matte(0x8A5A3C), at: [0, 0, 0], rotation: .z(.pi / 2))
        for side: Float in [-1, 1] {
            g.sphere(0.01, Clay.matte(0x8A5A3C), at: [side * (width / 2 + 0.05), 0, 0])
            let fabric = Clay.matte(tone, roughness: 1)
            for i in 0..<5 {
                let x = side * (width / 2 - 0.005 - Float(i) * 0.014)
                let sway = Float(i % 2) * 0.006
                g.cylinder(drop, 0.011, fabric, at: [x, -drop / 2, sway])
            }
            // Tie-back gathering the folds two thirds of the way down.
            g.box(0.08, 0.012, 0.03, r: 0.005, Clay.matte(0xF0663A),
                  at: [side * (width / 2 - 0.03), -drop * 0.62, 0.008])
        }
    }

    static func slippers(_ parent: Entity, at position: SIMD3<Float>, rotation: simd_quatf,
                         tone: UInt32 = 0xF3B0B0) {
        let g = parent.group(at: position, rotation: rotation)
        for z: Float in [-0.022, 0.022] {
            g.box(0.075, 0.016, 0.034, r: 0.008, Clay.matte(tone, roughness: 1), at: [0, 0.008, z])
            g.sphere(0.018, Clay.matte(0xFBF1E3, roughness: 1), at: [0.025, 0.018, z], scale: [1.3, 0.6, 1])
        }
    }

    /// Mochi's round bed: a plush base inside a ring of soft lumps, like the app room's. Her seat is 0.072 up.
    static func catBed(_ parent: Entity, at position: SIMD3<Float>, scale: Float) {
        let bed = parent.group(at: position)
        bed.scale = SIMD3(repeating: scale)
        let plush = Clay.matte(0xFBF1E3, roughness: 1)
        let shade = Clay.matte(0xEADBC6, roughness: 1)
        bed.cylinder(0.05, 0.19, shade, at: [0, 0.03, 0])
        bed.cylinder(0.03, 0.15, plush, at: [0, 0.06, 0])
        for i in 0..<24 {
            let a = Float(i) / 24 * 2 * .pi
            bed.sphere(0.06 * (1 + 0.06 * sin(Float(i) * 2.7)), i % 2 == 0 ? plush : shade,
                       at: [cos(a) * 0.165, 0.085, sin(a) * 0.165], scale: [1, 0.82, 1])
        }
    }

    /// Mochi's food and water bowls on a little mat.
    static func catBowls(_ parent: Entity, at position: SIMD3<Float>, rotation: simd_quatf) {
        let g = parent.group(at: position, rotation: rotation)
        g.box(0.13, 0.004, 0.07, r: 0.002, Clay.matte(0x9DB08A, roughness: 1), at: [0, 0.002, 0])
        let bowls: [(x: Float, tone: UInt32, fill: UInt32)] = [
            (-0.032, 0xF0663A, 0xB5733F),
            (0.032, 0x6F8FB0, 0xBFE0FF),
        ]
        for bowl in bowls {
            cone(g, 0.022, 0.026, 0.02, Clay.matte(bowl.tone), at: [bowl.x, 0.015, 0])
            g.cylinder(0.002, 0.022, Clay.matte(bowl.fill, roughness: bowl.fill == 0xBFE0FF ? 0.1 : 1),
                       at: [bowl.x, 0.025, 0])
        }
        for i in 0..<6 {
            g.sphere(0.004, Clay.matte(0x9A5B2E),
                     at: [-0.032 + cos(Float(i)) * 0.01, 0.028, sin(Float(i) * 1.7) * 0.01])
        }
    }

    static func toyMouse(_ parent: Entity, at position: SIMD3<Float>, rotation: simd_quatf) {
        let g = parent.group(at: position, rotation: rotation)
        g.sphere(0.014, Clay.matte(0xB8B0A8, roughness: 1), at: [0, 0.01, 0], scale: [1.5, 0.8, 1])
        for z: Float in [-0.007, 0.007] {
            g.sphere(0.005, Clay.matte(0xF3B0B0, roughness: 1), at: [0.013, 0.02, z], scale: [0.4, 1, 1])
        }
        g.cylinder(0.04, 0.0015, Clay.matte(0xF3B0B0), at: [-0.035, 0.004, 0], rotation: .z(.pi / 2 - 0.15))
    }

    /// A plush bunny sitting up.
    static func plush(_ parent: Entity, at position: SIMD3<Float>, rotation: simd_quatf,
                      tone: UInt32 = 0xF6E6D4) {
        let g = parent.group(at: position, rotation: rotation)
        let fur = Clay.matte(tone, roughness: 1)
        g.sphere(0.028, fur, at: [0, 0.025, 0], scale: [1, 0.95, 0.9])
        g.sphere(0.022, fur, at: [0, 0.066, 0])
        for z: Float in [-0.009, 0.009] {
            g.sphere(0.008, fur, at: [0, 0.1, z], scale: [0.6, 2.2, 0.8], rotation: .x(z * 18))
        }
        for z: Float in [-0.008, 0.008] {
            g.sphere(0.0032, Clay.matte(0x3A2A20), at: [0.02, 0.07, z])
        }
        g.sphere(0.004, Clay.matte(0xF3A0B5), at: [0.022, 0.062, 0])
    }

    /// A retro radio facing +X.
    static func radio(_ parent: Entity, at position: SIMD3<Float>, rotation: simd_quatf) {
        let g = parent.group(at: position, rotation: rotation)
        g.box(0.05, 0.05, 0.08, r: 0.008, Clay.matte(0x7C9A7E), at: [0, 0.025, 0])
        g.cylinder(0.004, 0.015, Clay.matte(0xF2E6D2), at: [0.026, 0.027, -0.018], rotation: .z(.pi / 2))
        g.box(0.004, 0.012, 0.03, r: 0.002, Clay.matte(0xF2E6D2), at: [0.026, 0.03, 0.02])
        g.cylinder(0.07, 0.0015, Clay.matte(0x5B3A28), at: [0, 0.08, 0.03], rotation: .x(-0.4))
    }

    /// A low two-drawer dresser facing +X, `length` along Z.
    static func dresser(_ parent: Entity, at position: SIMD3<Float>, length: Float = 0.22) {
        let g = parent.group(at: position)
        let wood = Clay.matte(0xC4946A)
        g.box(0.12, 0.17, length, r: 0.008, wood, at: [0, 0.085, 0])
        for y: Float in [0.05, 0.12] {
            g.box(0.006, 0.055, length - 0.02, r: 0.003, Clay.matte(0xD8AA7C), at: [0.061, y, 0])
            g.sphere(0.007, Clay.matte(0x8A5A3C), at: [0.066, y, 0])
        }
        for z: Float in [-length / 2 + 0.012, length / 2 - 0.012] {
            g.box(0.1, 0.012, 0.012, r: 0.003, Clay.matte(0x8A5A3C), at: [0, 0.006, z])
        }
    }

    /// A glass candle jar with a flickering flame; the flame is the returned model.
    @discardableResult
    static func candleJar(_ parent: Entity, at position: SIMD3<Float>) -> ModelEntity {
        let g = parent.group(at: position)
        g.cylinder(0.032, 0.016, Clay.matte(0xFFF3E0, roughness: 0.5), at: [0, 0.016, 0])
        return g.sphere(0.006, Clay.glow(0xFFB347, intensity: 6), at: [0, 0.04, 0], scale: [0.85, 1.5, 0.85])
    }
}
