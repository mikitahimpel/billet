import CoreGraphics
import Pet

/// The cars on the street behind the City room's window, as plain numbers: a fixed pool of slots, each free or a car at
/// some point along its lane. The scene draws them; this knows nothing of RealityKit. Lengths are room units, times
/// seconds.
struct CityTraffic {
    struct Lane: Equatable {
        /// Across the street, in the room's pivot space.
        let z: Float
        /// +1 drives towards +x, -1 towards -x.
        let direction: Float
    }

    struct Car: Equatable {
        var lane: Int
        /// The car's middle along the street.
        var x: Float
        /// Always positive; the lane gives the direction.
        var speed: Float
        /// Into the scene's palette.
        var colour: Int
    }

    struct Plan: Equatable {
        var lanes: [Lane]
        /// Where cars appear and vanish; both ends are out of sight behind the wall.
        var span: ClosedRange<Float>
        var speeds: ClosedRange<Float>
        /// Seconds from one car entering a lane to the next.
        var waits: ClosedRange<Float>
        /// The closest two cars in a lane come, middle to middle.
        var gap: Float
        var capacity: Int
        var colours: Int
    }

    let plan: Plan
    /// One per pool slot, `nil` when free; never grows past `plan.capacity`.
    private(set) var slots: [Car?]
    /// Seconds until each lane's next car may enter.
    private(set) var waits: [Float]
    /// Seeded, so the street runs the same each launch and tests can say what comes.
    private var random: SplitMix64

    init(plan: Plan, seed: UInt64) {
        self.plan = plan
        slots = Array(repeating: nil, count: plan.capacity)
        var random = SplitMix64(seed: seed)
        // Staggered, so the lanes don't start together.
        var waits: [Float] = []
        for _ in plan.lanes { waits.append(Float.random(in: 0...plan.waits.upperBound, using: &random)) }
        self.waits = waits
        self.random = random
    }

    /// The longest step taken at once, so a late frame doesn't jump a car past the one ahead.
    static let maxStep: Float = 0.1

    mutating func step(_ dt: Float) {
        let dt = min(max(dt, 0), Self.maxStep)
        drive(dt)
        for lane in plan.lanes.indices {
            waits[lane] -= dt
            // A lane whose way in is blocked or whose pool is full tries again next step.
            guard waits[lane] <= 0, enter(lane) else { continue }
            waits[lane] = Float.random(in: plan.waits, using: &random)
        }
    }

    /// One car standing still at `x` and the street otherwise empty, for Reduce Motion. Stepping again drives it on.
    mutating func park(lane: Int, x: Float, colour: Int) {
        for index in slots.indices { slots[index] = nil }
        slots[0] = Car(lane: lane, x: x, speed: plan.speeds.lowerBound, colour: colour)
    }

    private mutating func drive(_ dt: Float) {
        for index in slots.indices {
            guard var car = slots[index] else { continue }
            let direction = plan.lanes[car.lane].direction
            var x = car.x + direction * car.speed * dt
            // A faster car closes up on the one ahead and then keeps its pace.
            if let ahead = leader(of: index) {
                let limit = ahead.x - direction * plan.gap
                if (x - limit) * direction > 0 {
                    x = limit
                    car.speed = min(car.speed, ahead.speed)
                }
            }
            car.x = x
            let past = direction > 0 ? x > plan.span.upperBound : x < plan.span.lowerBound
            slots[index] = past ? nil : car
        }
    }

    /// The nearest car in front in the same lane.
    private func leader(of index: Int) -> Car? {
        guard let car = slots[index] else { return nil }
        let direction = plan.lanes[car.lane].direction
        var nearest: Car?
        for other in slots.indices where other != index {
            guard let candidate = slots[other], candidate.lane == car.lane else { continue }
            let ahead = (candidate.x - car.x) * direction
            guard ahead >= 0 else { continue }
            if let best = nearest, (best.x - car.x) * direction <= ahead { continue }
            nearest = candidate
        }
        return nearest
    }

    private mutating func enter(_ lane: Int) -> Bool {
        guard let free = slots.firstIndex(where: { $0 == nil }) else { return false }
        let direction = plan.lanes[lane].direction
        let start = direction > 0 ? plan.span.lowerBound : plan.span.upperBound
        let blocked = slots.contains { car in
            guard let car, car.lane == lane else { return false }
            return abs(car.x - start) < plan.gap
        }
        guard !blocked else { return false }
        let colour = Int.random(in: 0..<plan.colours, using: &random)
        slots[free] = Car(lane: lane, x: start, speed: Float.random(in: plan.speeds, using: &random), colour: colour)
        return true
    }
}

/// Whether something behind the City room's back wall can be drawn without showing beside the room: every corner of
/// it on screen must fall inside the wall's outline, which then hides all of it but what the window shows.
enum BehindWall {
    /// `outline` is a convex polygon in either winding; a point on its edge counts as inside.
    static func contains(_ outline: [CGPoint], _ point: CGPoint) -> Bool {
        guard outline.count > 2 else { return false }
        var sign: CGFloat = 0
        for index in outline.indices {
            let a = outline[index], b = outline[(index + 1) % outline.count]
            let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
            if cross == 0 { continue }
            if sign == 0 { sign = cross > 0 ? 1 : -1 }
            if cross * sign < 0 { return false }
        }
        return true
    }
}
