import CoreGraphics
import Pet
import Testing
import WindowViews
@testable import Billet

@MainActor
struct WindowLayersTests {
    @Test func aLookPaintsItsStillLayersOneAtATimeFromTheBack() {
        let painter = WindowLayerPainter()
        #expect(painter.prepare(.summerCulDeSac, hour: .day, weather: .clear))
        #expect(!painter.prepare(.summerCulDeSac, hour: .day, weather: .clear))
        var layers: [PaneLayer] = []
        while let still = painter.nextStill(now: 1_000) {
            layers.append(still.layer)
            let area = WindowLayerPainter.stillArea
            let density = WindowLayerPainter.density(still.layer)
            #expect(still.image.width == Int(area.width * density))
            #expect(still.image.height == Int(area.height * density))
        }
        #expect(layers == [.sky, .far, .middle, .street, .near])
        // The sky comes back a few seconds later for its stars and clouds.
        #expect(painter.nextStill(now: 1_005)?.layer == .sky)
    }

    @Test func theLifeAtlasHasASlicePerLivePlaneAndTheAir() throws {
        let painter = WindowLayerPainter()
        painter.prepare(.rainySuburb, hour: .night, weather: .rain)
        #expect(painter.lifeLayers.last == .air)
        let atlas = try #require(painter.life(now: 1_000))
        let area = WindowLayerPainter.lifeArea
        #expect(atlas.width == Int(area.width * WindowLayerPainter.lifeDensity))
        #expect(atlas.height == Int(area.height * WindowLayerPainter.lifeDensity) * painter.lifeLayers.count)
    }

    @Test func nearerLayersSitInFront() {
        let depths = PaneLayer.allCases.map(WindowPane.depth)
        #expect(depths == depths.sorted(by: >))
    }
}
