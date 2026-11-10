import CoreGraphics
import Testing
@testable import Billet

struct CityTrafficTests {
    private let plan = CityTraffic.Plan(
        lanes: [.init(y: 0.5, direction: -1, stop: 0.2)],
        span: -1...1, speeds: 0.1...0.2, waits: 1...3, gap: 0.2, capacity: 3, colours: 5,
        holds: 2...4, pace: 0.1)

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
                #expect(abs(car.x - 1) < plan.speeds.upperBound * CityTraffic.maxStep + 0.001)
            }
        }
        #expect(!seen.isEmpty)
    }

    @Test func aCarStandsAtTheCrossingThenDrivesOnAndLeaves() {
        var traffic = CityTraffic(plan: plan, seed: 2)
        var stood: Float = 0
        var left = 0
        var previous = traffic.slots
        run(&traffic, seconds: 120) { traffic in
            for index in traffic.slots.indices {
                if let car = traffic.slots[index], car.hold > 0 {
                    #expect(car.x == plan.lanes[0].stop && car.speed == 0)
                    stood += 1 / 60
                }
                if let was = previous[index], traffic.slots[index].map({ abs($0.x - was.x) > 0.5 }) ?? true {
                    #expect(was.crossed)
                    left += 1
                }
            }
            previous = traffic.slots
        }
        #expect(stood > 2)
        #expect(left >= 3)
    }

    @Test func carsInALaneNeverComeCloserThanTheGapAndNeverOverlapTheCrossingWait() {
        var traffic = CityTraffic(plan: plan, seed: 3)
        run(&traffic, seconds: 600, dt: 1 / 30) { traffic in
            let cars = traffic.slots.compactMap { $0 }
            #expect(cars.count <= plan.capacity)
            for a in cars.indices {
                for b in cars.indices where b > a && cars[a].lane == cars[b].lane {
                    #expect(abs(cars[a].x - cars[b].x) >= plan.gap - 0.0001)
                }
            }
        }
    }

    @Test func aCarNeverPassesTheStopBeforeItHasStood() {
        var traffic = CityTraffic(plan: plan, seed: 4)
        run(&traffic, seconds: 300) { traffic in
            for car in traffic.slots.compactMap({ $0 }) where !car.crossed {
                #expect(car.x >= plan.lanes[0].stop - 0.0001)
            }
        }
    }

    @Test func speedChangesGentlyAndStaysWithinThePlan() {
        var traffic = CityTraffic(plan: plan, seed: 5)
        var last: [Int: Float] = [:]
        var lastX: [Int: Float] = [:]
        run(&traffic, seconds: 300) { traffic in
            for (index, slot) in traffic.slots.enumerated() {
                guard let car = slot else {
                    last[index] = nil
                    continue
                }
                #expect(car.speed >= 0 && car.speed <= plan.speeds.upperBound)
                #expect(car.x >= -1 && car.x <= 1)
                if let was = last[index], abs(car.x - lastX[index]!) < 0.5 {
                    // The braking curve may demand more than `pace` near the stop, but never a jolt.
                    #expect(abs(car.speed - was) < 0.03)
                }
                last[index] = car.speed
                lastX[index] = car.x
            }
        }
    }

    @Test func theSameSeedDrivesTheSameTraffic() {
        var a = CityTraffic(plan: plan, seed: 7)
        var b = CityTraffic(plan: plan, seed: 7)
        var c = CityTraffic(plan: plan, seed: 8)
        run(&a, seconds: 30)
        run(&b, seconds: 30)
        run(&c, seconds: 30)
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

    @Test func aFullPoolHoldsTheNextCarBack() {
        let busy = CityTraffic.Plan(
            lanes: [.init(y: 0.5, direction: -1, stop: -50)], span: -10...10, speeds: 0.1...0.1, waits: 0.1...0.1,
            gap: 0.2, capacity: 2, colours: 1, holds: 1...1, pace: 0.1)
        var traffic = CityTraffic(plan: busy, seed: 9)
        run(&traffic, seconds: 10)
        #expect(traffic.slots.compactMap { $0 }.count == 2)
    }

    @Test func parkingLeavesOneCarStillWhereItWasPut() {
        var traffic = CityTraffic(plan: plan, seed: 10)
        run(&traffic, seconds: 20)
        traffic.park(lane: 0, x: -0.3, colour: 2)
        let car = traffic.slots.compactMap { $0 }
        #expect(car.count == 1 && car[0].x == -0.3 && car[0].speed == 0 && car[0].colour == 2)
        traffic.step(1 / 60)
        #expect(traffic.slots[0]!.x < -0.3)
    }

    @Test func theStreetsCarsStandBeforeTheCrossingEdgeEachLaneReachesFirst() {
        let lanes = CityDiorama.plan.lanes
        #expect(lanes.count == 2)
        #expect(lanes[0].direction < 0 && lanes[0].stop > CityDiorama.crossing.right)
        #expect(lanes[1].direction > 0 && lanes[1].stop < CityDiorama.crossing.left)
    }

    @Test func theStreetsTrafficStaysSmallAndCrossesTheWholePicture() {
        var traffic = CityTraffic(plan: CityDiorama.plan, seed: 0xC17_CA25)
        var stood = false
        var most = 0
        run(&traffic, seconds: 400, dt: 1 / 30) { traffic in
            most = max(most, traffic.slots.compactMap { $0 }.count)
            stood = stood || traffic.slots.contains { ($0?.hold ?? 0) > 0 }
        }
        #expect(most <= 2)
        #expect(stood)
    }
}
