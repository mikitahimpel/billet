import CoreGraphics
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
}
