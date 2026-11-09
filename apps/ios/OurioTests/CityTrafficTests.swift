import CoreGraphics
import Testing
@testable import Billet

struct CityTrafficTests {
    private let plan = CityTraffic.Plan(
        lanes: [.init(z: -0.8, direction: 1), .init(z: -0.9, direction: -1)],
        span: -1...1, speeds: 0.1...0.3, waits: 1...3, gap: 0.2, capacity: 4, colours: 5)

    /// Steps of `dt` for `seconds`, calling `each` after every step.
    private func run(_ traffic: inout CityTraffic, seconds: Float, dt: Float = 1 / 60,
                     each: (CityTraffic) -> Void = { _ in }) {
        for _ in 0..<Int(seconds / dt) {
            traffic.step(dt)
            each(traffic)
        }
    }

    @Test func aCarEntersAtItsLanesStartOutOfSight() {
        var traffic = CityTraffic(plan: plan, seed: 1)
        var seen: [Int: Float] = [:]
        run(&traffic, seconds: 8) { traffic in
            for case let (index, car?) in traffic.slots.enumerated() where seen[index] == nil {
                seen[index] = car.x
                let start: Float = traffic.plan.lanes[car.lane].direction > 0 ? -1 : 1
                #expect(abs(car.x - start) < 0.3 * CityTraffic.maxStep + 0.001)
            }
        }
        #expect(!seen.isEmpty)
    }

    @Test func aCarLeavesPastTheFarEndAndFreesItsSlot() {
        var traffic = CityTraffic(plan: plan, seed: 2)
        var left = 0
        var previous = traffic.slots
        run(&traffic, seconds: 60) { traffic in
            for index in traffic.slots.indices {
                guard let was = previous[index], traffic.slots[index] == nil || traffic.slots[index]!.lane != was.lane
                    || abs(traffic.slots[index]!.x - was.x) > 0.5
                else { continue }
                let direction = traffic.plan.lanes[was.lane].direction
                // The last place it was seen is within one step of the far end.
                #expect(direction > 0 ? was.x > 1 - 0.03 : was.x < -1 + 0.03)
                left += 1
            }
            previous = traffic.slots
        }
        #expect(left > 5)
    }

    @Test func carsInALaneNeverComeCloserThanTheGap() {
        var traffic = CityTraffic(plan: plan, seed: 3)
        run(&traffic, seconds: 300, dt: 1 / 30) { traffic in
            let cars = traffic.slots.compactMap { $0 }
            #expect(cars.count <= plan.capacity)
            for a in cars.indices {
                for b in cars.indices where b > a && cars[a].lane == cars[b].lane {
                    #expect(abs(cars[a].x - cars[b].x) >= plan.gap - 0.0001)
                }
            }
        }
    }

    @Test func everyCarStaysOnTheStreetAtASpeedFromThePlan() {
        var traffic = CityTraffic(plan: plan, seed: 4)
        run(&traffic, seconds: 120) { traffic in
            for car in traffic.slots.compactMap({ $0 }) {
                #expect(car.x >= -1 && car.x <= 1)
                #expect(car.speed > 0 && car.speed <= plan.speeds.upperBound)
                #expect((0..<plan.colours).contains(car.colour))
            }
        }
    }

    @Test func theSameSeedDrivesTheSameTraffic() {
        var a = CityTraffic(plan: plan, seed: 7)
        var b = CityTraffic(plan: plan, seed: 7)
        var c = CityTraffic(plan: plan, seed: 8)
        run(&a, seconds: 20)
        run(&b, seconds: 20)
        run(&c, seconds: 20)
        #expect(a.slots == b.slots && a.waits == b.waits)
        #expect(a.slots != c.slots)
    }

    @Test func aLongFrameMovesNoFurtherThanTheLongestStep() {
        var traffic = CityTraffic(plan: plan, seed: 5)
        run(&traffic, seconds: 6)
        let before = traffic.slots
        traffic.step(5)
        for (old, new) in zip(before, traffic.slots) {
            guard let old, let new, old.lane == new.lane else { continue }
            #expect(abs(new.x - old.x) <= plan.speeds.upperBound * CityTraffic.maxStep + 0.0001)
        }
    }

    @Test func theLanesTakeTurnsAndBothGetCars() {
        var traffic = CityTraffic(plan: plan, seed: 6)
        var lanes: Set<Int> = []
        run(&traffic, seconds: 30) { traffic in
            for car in traffic.slots.compactMap({ $0 }) { lanes.insert(car.lane) }
        }
        #expect(lanes == [0, 1])
    }

    @Test func aFullPoolHoldsTheNextCarBack() {
        let busy = CityTraffic.Plan(
            lanes: plan.lanes, span: -10...10, speeds: 0.1...0.1, waits: 0.1...0.1, gap: 0.2, capacity: 2, colours: 1)
        var traffic = CityTraffic(plan: busy, seed: 9)
        run(&traffic, seconds: 10)
        #expect(traffic.slots.compactMap { $0 }.count == 2)
    }

    @Test func parkingLeavesOneCarStillWhereItWasPut() {
        var traffic = CityTraffic(plan: plan, seed: 10)
        run(&traffic, seconds: 20)
        traffic.park(lane: 1, x: -0.3, colour: 2)
        #expect(traffic.slots.compactMap { $0 } == [CityTraffic.Car(lane: 1, x: -0.3, speed: 0.1, colour: 2)])
        traffic.step(1 / 60)
        #expect(traffic.slots[0]!.x < -0.3)
    }

    private let wall = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 10), CGPoint(x: 100, y: 110), CGPoint(x: 0, y: 100)]

    @Test(arguments: [false, true])
    func aPointInsideTheWallsOutlineIsHidden(reversed: Bool) {
        let outline = reversed ? Array(wall.reversed()) : wall
        #expect(BehindWall.contains(outline, CGPoint(x: 10, y: 20)))
        #expect(BehindWall.contains(outline, CGPoint(x: 90, y: 95)))
        #expect(BehindWall.contains(outline, CGPoint(x: 0, y: 50)))
    }

    @Test(arguments: [CGPoint(x: 101, y: 50), CGPoint(x: 50, y: 4), CGPoint(x: -1, y: 50), CGPoint(x: 50, y: 106)])
    func aPointOutsideTheWallIsNot(point: CGPoint) {
        #expect(!BehindWall.contains(wall, point))
        #expect(!BehindWall.contains(Array(wall.reversed()), point))
    }

    @Test func noOutlineHidesNothing() {
        #expect(!BehindWall.contains([], CGPoint(x: 50, y: 50)))
    }
}
