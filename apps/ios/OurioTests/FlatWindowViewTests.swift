import CoreGraphics
import Pet
import Testing
import UIKit
@testable import WindowViews

@MainActor
struct FlatWindowViewTests {
    private let window = [CGPoint(x: 100, y: 200), CGPoint(x: 300, y: 200), CGPoint(x: 300, y: 316),
                          CGPoint(x: 100, y: 316)]

    @Test func platesArePaintedAtTheScreensPixelsInFewSteps() {
        let unit: CGFloat = 2
        let pixels = FlatWindowView.platePixels(unit: unit, scale: 3)
        #expect(CGFloat(pixels) >= ViewStage.plate.width * unit * 3)
        #expect(CGFloat(pixels) < ViewStage.plate.width * unit * 3 * 1.26)
        // A small pinch keeps the same plate.
        #expect(FlatWindowView.platePixels(unit: unit * 1.01, scale: 3) == pixels)
        #expect(FlatWindowView.platePixels(unit: 100, scale: 3) == FlatWindowView.maxPlatePixels)
    }

    @Test func aPlateCoversTheWholeStageWithItsGrain() throws {
        let key = FlatWindowView.PlateKey(
            look: ViewLook(view: .summerCulDeSac, hour: .day, weather: .clear), plane: .street, pixels: 640)
        let image = try #require(FlatWindowView.paintPlate(key))
        #expect(image.width == 640)
        #expect(abs(CGFloat(image.height) - 640 * ViewStage.plate.height / ViewStage.plate.width) <= 1)
    }

    @Test func farPlanesMoveLessThanNearOnesAsTheRoomTurns() {
        let home = ViewStage.Frame(window: window)!
        let turned = ViewStage.Frame(window: window.map { CGPoint(x: $0.x + 40, y: $0.y) })!
        let shifts = ViewPlane.allCases.map {
            FlatWindowView.rect(ViewStage.plate, in: .blend(home: home, live: turned, follow: $0.follow)).minX
                - FlatWindowView.rect(ViewStage.plate, in: home).minX
        }
        #expect(shifts == shifts.sorted())
        #expect(shifts.first! > 0 && shifts.last! < 40)
    }

    @Test func theViewIsClippedToTheHoleGrownToHideItsEdges() {
        let box = FlatWindowView.path(window, grownBy: 1.03).boundingBox
        #expect(box.contains(CGRect(x: 100, y: 200, width: 200, height: 116)))
        #expect(box.width < 200 * 1.04)
    }

    @Test func itNeverTakesATouchAndHidesWithoutAWindow() {
        let view = FlatWindowView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        #expect(!view.isUserInteractionEnabled)
        view.show(.suburbNight, hour: .night, weather: .clear, lampOn: true)
        view.place(window: [], home: [], hole: [])
        #expect(view.layer.sublayers?.first?.isHidden == true)
        view.place(window: window, home: window, hole: window)
        #expect(view.layer.sublayers?.first?.isHidden == false)
    }
}
