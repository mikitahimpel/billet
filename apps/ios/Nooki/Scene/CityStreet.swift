import RealityKit
import UIKit

/// The cars driving past behind the City room's window: a few clay cars, built once and reused as `CityTraffic` moves
/// them. They live behind the back wall, so each is drawn only while the wall hides all of it but what the window shows.
@MainActor
final class CityStreet {
    private enum Tone {
        static let paints: [UInt32] = [0xE0554A, 0xE3B45C, 0x6F8FB0, 0x7C9A7E, 0xF2E6D2, 0xD8653F]
        static let cabin: UInt32 = 0xC9D6DE
        static let tyre: UInt32 = 0x4A3B36
        static let lamp: UInt32 = 0xFFE3A8
        static let tail: UInt32 = 0xE0554A
    }

    /// Room units: length along the street, height to the roof, width across it.
    static let size: SIMD3<Float> = [0.1, 0.044, 0.048]
    /// The street's height and its lanes' depth put the cars just above the sill on screen, where the window view's
    /// own street is, from the room's usual angle round to facing the window.
    static let ground: Float = 0.1
    static let plan = CityTraffic.Plan(
        lanes: [.init(z: -0.9, direction: -1), .init(z: -1.0, direction: 1)],
        span: -1.7...0.9, speeds: 0.09...0.17, waits: 2.5...7, gap: 0.19, capacity: 4,
        colours: Tone.paints.count)
    /// Where Reduce Motion parks its one car: in the window at the room's usual angle.
    static let parking = (lane: 0, x: Float(-0.3), colour: 1)

    private let root: Entity
    private var traffic = CityTraffic(plan: plan, seed: 0xC17_CA25)
    private var cars: [Car] = []
    private let paints: [PhysicallyBasedMaterial]
    private let lampsOff = Clay.matte(Tone.lamp, roughness: 0.4)
    private let lampsOn = Clay.glow(Tone.lamp, intensity: 6)
    private let tailsOff = Clay.matte(Tone.tail, roughness: 0.5)
    private let tailsOn = Clay.glow(Tone.tail, intensity: 2.5)
    private var lit = false
    private var parked = false
    /// Reused each frame for the back wall's outline on screen.
    private var front: [CGPoint] = []
    private var back: [CGPoint] = []

    private struct Car {
        let entity: Entity
        let body: ModelEntity
        let lamps: ModelEntity
        let tails: ModelEntity
        var colour: Int
    }

    /// A car's box corners about the point it stands on.
    private static let corners: [SIMD3<Float>] = {
        let half = SIMD3<Float>(size.x / 2, size.y, size.z / 2)
        var corners: [SIMD3<Float>] = []
        for x: Float in [-1, 1] {
            for y: Float in [0, 1] {
                for z: Float in [-1, 1] { corners.append(SIMD3(x, y, z) * half) }
            }
        }
        return corners
    }()
    private static let facing = (forward: simd_quatf.identity, back: simd_quatf.y(.pi))

    /// Under `pivot`; always built live, whatever the room's shell.
    init(in pivot: Entity) {
        let root = pivot.group()
        root.components.set(ShellLive())
        self.root = root
        let paints = Tone.paints.map { Clay.matte($0, roughness: 0.7) }
        self.paints = paints
        let cabin = Clay.matte(Tone.cabin, roughness: 0.35)
        let tyre = Clay.matte(Tone.tyre, roughness: 0.95)
        let s = Self.size
        for _ in 0..<Self.plan.capacity {
            let car = root.group()
            car.isEnabled = false
            // Low and soft like the room's furniture: a rounded body, a cabin set back, an axle of wheels each end.
            let body = car.box(s.x, s.y * 0.46, s.z, r: 0.012, paints[0], at: [0, s.y * 0.36, 0])
            car.box(s.x * 0.52, s.y * 0.42, s.z * 0.86, r: 0.01, cabin, at: [-s.x * 0.06, s.y * 0.76, 0])
            for x in [-s.x * 0.3, s.x * 0.3] {
                car.cylinder(s.z * 1.02, 0.011, tyre, at: [x, 0.011, 0], rotation: .x(.pi / 2))
            }
            let lamps = car.box(0.006, 0.008, s.z * 0.8, r: 0.003, lampsOff, at: [s.x / 2, s.y * 0.4, 0])
            let tails = car.box(0.006, 0.008, s.z * 0.8, r: 0.003, tailsOff, at: [-s.x / 2, s.y * 0.4, 0])
            cars.append(Car(entity: car, body: body, lamps: lamps, tails: tails, colour: 0))
        }
    }

    /// Reduce Motion parks one car in view and holds it there; turned off, that car drives on.
    func tick(_ dt: Float, reduceMotion: Bool) {
        if reduceMotion {
            if !parked {
                let p = Self.parking
                traffic.park(lane: p.lane, x: p.x, colour: p.colour)
                parked = true
            }
        } else {
            parked = false
            traffic.step(dt)
        }
        for index in cars.indices {
            guard let state = traffic.slots[index] else {
                cars[index].entity.isEnabled = false
                continue
            }
            let lane = Self.plan.lanes[state.lane]
            let car = cars[index]
            car.entity.position = [state.x, Self.ground, lane.z]
            car.entity.orientation = lane.direction > 0 ? Self.facing.forward : Self.facing.back
            if car.colour != state.colour {
                car.body.model?.materials = [paints[state.colour]]
                cars[index].colour = state.colour
            }
        }
    }

    /// Headlights and tail lights come on with the room's lamps.
    func light(lampsOn on: Bool) {
        guard on != lit else { return }
        lit = on
        for car in cars {
            car.lamps.model?.materials = [on ? lampsOn : lampsOff]
            car.tails.model?.materials = [on ? tailsOn : tailsOff]
        }
    }

    /// After the camera has moved: shows each car only while every corner of it lands inside both faces of the back
    /// wall on screen, and its box on screen meets the window's; behind the wall elsewhere it would cost a draw for
    /// nothing. `front` and `back` are the wall's faces in pivot space, `window` the hole's corners on screen, and
    /// `project` takes pivot space to screen points.
    func gate(front frontCorners: [SIMD3<Float>], back backCorners: [SIMD3<Float>], window: [CGPoint],
              project: (SIMD3<Float>) -> CGPoint?) {
        guard traffic.slots.contains(where: { $0 != nil }) else { return }
        Self.outline(frontCorners, into: &front, project)
        Self.outline(backCorners, into: &back, project)
        let hole = Self.bounds(window)
        for index in cars.indices {
            guard let state = traffic.slots[index] else { continue }
            let lane = Self.plan.lanes[state.lane]
            let origin = SIMD3<Float>(state.x, Self.ground, lane.z)
            var shown = front.count == 4 && back.count == 4
            var box = CGRect.null
            for corner in Self.corners where shown {
                guard let point = project(origin + corner) else {
                    shown = false
                    break
                }
                shown = BehindWall.contains(front, point) && BehindWall.contains(back, point)
                box = box.union(CGRect(origin: point, size: .zero))
            }
            cars[index].entity.isEnabled = shown && box.intersects(hole)
        }
    }

    private static func bounds(_ points: [CGPoint]) -> CGRect {
        var box = CGRect.null
        for point in points { box = box.union(CGRect(origin: point, size: .zero)) }
        return box
    }

    private static func outline(_ corners: [SIMD3<Float>], into points: inout [CGPoint],
                                _ project: (SIMD3<Float>) -> CGPoint?) {
        points.removeAll(keepingCapacity: true)
        for corner in corners {
            guard let point = project(corner) else { continue }
            points.append(point)
        }
    }
}
