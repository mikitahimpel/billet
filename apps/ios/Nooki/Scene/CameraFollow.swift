import CoreGraphics
import Foundation
import simd

/// Where the room's camera looks, and how what floats over Mochi follows her on screen.
enum CameraFollow {
    /// The point the camera looks at: the framing's own target, drawn toward `cat` by `zoom` and `follow`. With no
    /// `follow` the room's framing holds whatever the cat does; `follow` is 1 only for a camera that follows her.
    static func target(framing: SIMD3<Float>, cat: SIMD3<Float>, zoom: Float, follow: Float) -> SIMD3<Float> {
        framing + (cat - framing) * zoom * follow
    }

    /// `follow` moved toward 1 while a camera follows her or the owner is zooming, and back toward 0 after.
    static func follow(_ follow: Float, active: Bool, dt: Float) -> Float {
        guard dt > 0 else { return follow }
        let goal: Float = active ? 1 : 0
        let next = follow + (goal - follow) * (1 - exp(-3 * dt))
        return abs(goal - next) < 0.001 ? goal : next
    }
}

/// A point on screen that follows its input without trembling: eased with a time constant, so the same however
/// frames are timed, and put on the pixel grid once it comes to rest.
struct ScreenSmoother {
    private static let rate: CGFloat = 18
    private static let restRadius: CGFloat = 0.35
    private static let jump: CGFloat = 120

    var scale: CGFloat = 3
    private(set) var value: CGPoint?

    mutating func step(_ input: CGPoint, dt: Float) -> CGPoint {
        guard let old = value, dt > 0 else {
            value = value ?? input
            return value ?? input
        }
        let gap = hypot(input.x - old.x, input.y - old.y)
        // A point that lands far from where it was is a different place (another room), not a move.
        guard gap < Self.jump else {
            value = input
            return input
        }
        let share = 1 - exp(-Self.rate * CGFloat(dt))
        let next = CGPoint(x: old.x + (input.x - old.x) * share, y: old.y + (input.y - old.y) * share)
        value = next
        return gap < Self.restRadius ? CGPoint(x: (next.x * scale).rounded() / scale,
                                               y: (next.y * scale).rounded() / scale) : next
    }

    mutating func reset() { value = nil }
}
