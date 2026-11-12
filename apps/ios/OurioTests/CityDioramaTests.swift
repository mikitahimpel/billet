import CoreGraphics
import simd
import Testing
@testable import Billet

struct CityDioramaTests {
    @Test(arguments: Array(stride(from: Float(0), to: 24, by: 0.25)))
    func theThreeTimesAlwaysSumToOneAndOnlyNeighboursMix(hour: Float) {
        let weights = CityDiorama.weights(hour: hour)
        #expect(abs(weights.reduce(0, +) - 1) < 0.0001)
        #expect(!(weights[0] > 0 && weights[2] > 0))
    }

    @Test func theDayIsDayAtNoonAndNightIsNightAtMidnight() {
        #expect(CityDiorama.weights(hour: 12) == [1, 0, 0])
        #expect(CityDiorama.weights(hour: 0) == [0, 0, 1])
        #expect(CityDiorama.weights(hour: 24) == [0, 0, 1])
        #expect(CityDiorama.weights(hour: 18)[1] == 0.5)
    }

    @Test func stackedOpacitiesCrossFadeToTheWeights() {
        #expect(CityDiorama.opacities([0.25, 0.75, 0]) == [1, 0.75, 0])
        #expect(CityDiorama.opacities([0, 0.4, 0.6]) == [0, 1, 0.6])
        #expect(CityDiorama.opacities([0, 0, 0]) == [0, 0, 0])
    }

    @Test func theVisiblePartOfEveryImageCoversTheWindow() {
        let r = CityDiorama.imageRect
        let visible = CGRect(
            x: r.minX + r.width * CityDiorama.margin, y: r.minY + r.height * CityDiorama.margin,
            width: r.width * (1 - 2 * CityDiorama.margin), height: r.height * (1 - 2 * CityDiorama.margin))
        #expect(visible.contains(CGRect(x: 0, y: 0, width: 100, height: CityDiorama.stageHeight)))
        // Left to right it sits in the middle of the window.
        #expect(abs((visible.midX) - 50) < 0.001)
    }

    @Test func theBackingSkyIsBlueByDayAndDarkAtNight() {
        let noon = CityDiorama.sky(hour: 12), midnight = CityDiorama.sky(hour: 0)
        #expect(noon.top.z > noon.top.x && noon.horizon.z > noon.horizon.x)
        // Deeper at the top, lighter at the horizon.
        #expect(noon.top.x < noon.horizon.x)
        #expect(midnight.top.x + midnight.top.y + midnight.top.z < 0.5)
        #expect(midnight.top.x > midnight.top.y)
    }

    @Test(arguments: stride(from: Float(0), to: 24, by: 0.5).map { $0 })
    func theBackingSkyChangesGentlyThroughTheDay(hour: Float) {
        let a = CityDiorama.sky(hour: hour), b = CityDiorama.sky(hour: hour + 0.5)
        #expect(simd_length(a.top - b.top) < 0.45 && simd_length(a.horizon - b.horizon) < 0.45)
    }

    @Test(arguments: [CGFloat(1.12), .infinity])
    func aLayerSlidesOverAnOpeningThatTurnedPastItsEdge(growth: CGFloat) {
        let frame = CGRect(x: 0, y: 0, width: 112, height: 70)
        for shift in stride(from: CGFloat(-12), through: 12, by: 4) {
            let opening = CGRect(x: 6 + shift, y: 4, width: 100, height: 58)
            let covered = CityDiorama.covering(frame, opening: opening, growth: growth)
            #expect(covered.contains(opening), "shift \(shift)")
        }
    }

    @Test func aLayerAlreadyCoveringTheOpeningStaysWhereItIs() {
        let frame = CGRect(x: -6, y: -4, width: 112, height: 70)
        #expect(CityDiorama.covering(frame, opening: CGRect(x: 0, y: 0, width: 100, height: 58), growth: 1.12) == frame)
    }

    @Test func onlyTheSkyGrowsPastItsLimit() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 60)
        let opening = CGRect(x: 0, y: 0, width: 160, height: 90)
        #expect(CityDiorama.covering(frame, opening: opening, growth: .infinity).contains(opening))
        #expect(CityDiorama.covering(frame, opening: opening, growth: 1.12).width <= 112.001)
    }
}
