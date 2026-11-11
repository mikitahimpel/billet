import DecorInterface
import Pet
import RealityKit
import RoomInterface
import SwiftUI

/// The pieces the player stands in the Home room: what is drawn, what the cat avoids, and where a finger
/// puts a piece. The arrangement itself lives with the shell; the room draws what it is told.
extension RoomController {
    func showDecor(_ next: RoomDecor) {
        decor = next
        guard let home else { return }
        decorStage.apply(next, receiver: home.iblReceiver)
        if home.iblReceiver == nil, decorRetries < 6 {
            decorRetries += 1
            Task {
                try? await Task.sleep(for: .seconds(1))
                showDecor(decor)
            }
        }
        let occupancy = next.layout.occupancy()
        if occupancy != home.avoid { home.avoid = occupancy }
        var cut: Set<NookiSpot> = []
        for (name, spot) in [("ball", NookiSpot.ball), ("basket", .basket), ("sill", .sill)]
        where !next.layout.canVisit(name) { cut.insert(spot) }
        if cut != home.cutOff { home.cutOff = cut }
        let places = Self.cat(places: next.layout, occupancy: occupancy)
        if Set(places.keys) != Set(home.placedSpots.keys) || places.values.map(\.id) != home.placedSpots.values.map(\.id) {
            home.placedSpots = places
        }
        home.arrange(next.layout)
    }

    /// Where the cat goes to use each kind of piece the player stood: round whatever is in the way to the floor
    /// beside it, then up onto a seat.
    private static func cat(places layout: DecorLayout, occupancy: Occupancy) -> [NookiSpot: CatWalker.Destination] {
        let floor: Float = 0.023
        var spots: [NookiSpot: CatWalker.Destination] = [:]
        for plan in layout.catSpots() {
            func waypoint(_ point: Occupancy.Point) -> CatWalker.Waypoint {
                .init(at: [Float(point.x), floor, Float(point.z)])
            }
            var path = (occupancy.route(from: layout.spawn(), to: plan.approach) ?? []).map(waypoint)
            path.append(waypoint(plan.approach))
            var yaw = Float.pi * 0.75
            if let top = plan.top {
                path.append(.init(at: [Float(top.point.x), 0.014 + Float(top.height), Float(top.point.z)], move: .jump))
            } else if let item = DecorItem.item(shopID: plan.item), let placement = layout.placement(of: item.id) {
                let dx = DecorGrid.metres(placement.u) - plan.approach.x
                let dz = DecorGrid.metres(placement.v) - plan.approach.z
                yaw = Float(atan2(-dx, -dz))
            }
            let spot: NookiSpot =
                switch plan.use {
                case .sofa: .sofa
                case .windowSeat: .windowSeat
                case .post: .post
                case .catBed: .catBed
                case .crate: .crate
                }
            spots[spot] = CatWalker.Destination(id: "placed.\(plan.use.rawValue)", path: path, rest: yaw)
        }
        return spots
    }

    // MARK: Touch

    private func world(_ point: CGPoint, onto plane: simd_float4x4) -> SIMD3<Float>? {
        guard let home, let unproject = home.unprojector, let hit = unproject(point, plane) else { return nil }
        return home.pivot.convert(position: hit, from: nil)
    }

    private enum Plane {
        case floor, back, left

        func matrix(_ pivot: Entity) -> simd_float4x4 {
            let base = pivot.transformMatrix(relativeTo: nil)
            switch self {
            case .floor:
                return base * Self.translation([0, DecorStage.floorY, 0])
            case .back:
                return base * Self.translation([0, 0, -0.49]) * simd_float4x4(simd_quatf.x(.pi / 2))
            case .left:
                return base * Self.translation([-0.49, 0, 0]) * simd_float4x4(simd_quatf.z(-.pi / 2))
            }
        }

        private static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
            var m = matrix_identity_float4x4
            m.columns.3 = SIMD4(t, 1)
            return m
        }
    }

    private func hit(_ point: CGPoint, _ plane: Plane) -> SIMD3<Float>? {
        guard let home else { return nil }
        return world(point, onto: plane.matrix(home.pivot))
    }

    /// The piece under the screen point, a wall piece first.
    func decorPiece(at point: CGPoint) -> String? {
        if let back = hit(point, .back), let id = decorStage.wallPiece(at: back, on: .backWall) { return id }
        if let left = hit(point, .left), let id = decorStage.wallPiece(at: left, on: .leftWall) { return id }
        if let floor = hit(point, .floor) { return decorStage.floorPiece(at: floor) }
        return nil
    }

    /// How many cells the piece's middle is from where the finger first touched, so it does not jump.
    func decorGrab(_ item: String, at point: CGPoint) -> (du: Int, dv: Int) {
        guard let placement = decor.layout.placement(of: item) else { return (0, 0) }
        switch placement.surface {
        case .floor:
            guard let p = hit(point, .floor) else { return (0, 0) }
            return (placement.u - DecorGrid.cell(Double(p.x)), placement.v - DecorGrid.cell(Double(p.z)))
        case .backWall:
            guard let p = hit(point, .back) else { return (0, 0) }
            return (placement.u - DecorGrid.cell(Double(p.x)), 0)
        case .leftWall:
            guard let p = hit(point, .left) else { return (0, 0) }
            return (placement.u - DecorGrid.cell(Double(p.z)), 0)
        }
    }

    /// Where the finger puts `item`, snapped to the grid; a wall piece may cross to the other wall.
    func decorSpot(for item: String, at point: CGPoint, grab: (du: Int, dv: Int)) -> Placement? {
        guard let placement = decor.layout.placement(of: item) else { return nil }
        let limit = Occupancy.reach
        func clamped(_ cell: Int) -> Int { min(max(cell, -limit), limit) }
        switch placement.surface {
        case .floor:
            guard let p = hit(point, .floor) else { return nil }
            return placement.moved(
                to: .floor, u: clamped(DecorGrid.cell(Double(p.x)) + grab.du),
                v: clamped(DecorGrid.cell(Double(p.z)) + grab.dv))
        case .backWall, .leftWall:
            let back = hit(point, .back).flatMap { $0.x >= -0.49 && $0.x <= 0.49 && $0.y > 0.05 && $0.y < 0.8 ? $0 : nil }
            let left = hit(point, .left).flatMap { $0.z >= -0.49 && $0.z <= 0.49 && $0.y > 0.05 && $0.y < 0.8 ? $0 : nil }
            let onBack = placement.surface == .backWall
            if let back, onBack || left == nil {
                return placement.moved(to: .backWall, u: clamped(DecorGrid.cell(Double(back.x)) + grab.du), v: 0)
            }
            if let left {
                return placement.moved(to: .leftWall, u: clamped(DecorGrid.cell(Double(left.z)) + grab.du), v: 0)
            }
            return nil
        }
    }
}

/// Over the room while the pieces are arranged: a touch on a piece chooses it, a drag moves it, and the
/// room itself does not turn.
struct DecorTouchLayer: View {
    let controller: RoomController

    private struct Touch {
        let item: String?
        var dragging = false
        var grab = (du: 0, dv: 0)
        var last: Placement?
    }

    @State private var touch: Touch?

    var body: some View {
        Color.clear
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        var current = touch ?? Touch(item: controller.decorPiece(at: value.startLocation))
                        defer { touch = current }
                        guard let item = current.item else { return }
                        let moved = hypot(value.translation.width, value.translation.height)
                        guard current.dragging || moved > 8 else { return }
                        if !current.dragging {
                            current.dragging = true
                            current.grab = controller.decorGrab(item, at: value.startLocation)
                            controller.decorTouched(.dragBegan(item))
                        }
                        guard let spot = controller.decorSpot(for: item, at: value.location, grab: current.grab),
                            spot != current.last
                        else { return }
                        current.last = spot
                        controller.decorTouched(.dragged(spot))
                    }
                    .onEnded { _ in
                        defer { touch = nil }
                        guard let touch else { return }
                        if touch.dragging {
                            controller.decorTouched(.dropped)
                        } else if let item = touch.item {
                            controller.decorTouched(.tapped(item))
                        } else {
                            controller.decorTouched(.tappedEmpty)
                        }
                    }
            )
            .accessibilityHidden(true)
            .ignoresSafeArea()
    }
}
