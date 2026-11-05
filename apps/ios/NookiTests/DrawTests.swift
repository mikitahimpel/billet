import Foundation
import Testing
import Wire
@testable import Billet

@MainActor
struct DrawTests {
    @Test func theDrawLinkRoundTrips() {
        #expect(DeepLink.draw.url.absoluteString == "nooki://draw")
        #expect(DeepLink(url: DeepLink.draw.url) == .draw)
    }

    @Test func theDrawLinkOpensTheCanvas() {
        let state = HomeState(stores: .live())
        state.open(.draw)
        #expect(state.drawing)
    }

    private func stroke(_ model: DrawModel, at x: Double) {
        model.touch(Point(x: x, y: 0.5))
        model.touch(Point(x: x, y: 0.6))
        model.lift()
    }

    @Test func undoTakesBackStrokesTheEraserAndAClear() {
        let model = DrawModel(room: nil, partnerName: "Anya")
        stroke(model, at: 0.2)
        stroke(model, at: 0.8)
        #expect(model.strokes.count == 2)

        model.tool = .eraser
        model.touch(Point(x: 0.2, y: 0.55))
        model.touch(Point(x: 0.21, y: 0.56))
        model.lift()
        #expect(model.strokes.count == 1)

        model.clear()
        #expect(model.isEmpty)

        model.undo()
        #expect(model.strokes.count == 1)
        model.undo()
        #expect(model.strokes.count == 2)
        model.undo()
        #expect(model.strokes.count == 1)
    }

    @Test func strokesUseTheChosenInkAsWireColour() {
        let model = DrawModel(room: nil, partnerName: "Anya")
        model.ink = DrawInks.all[1]
        stroke(model, at: 0.5)
        #expect(model.strokes.first?.color == "#FF4F86")
        #expect(model.strokes.first?.width == DrawModel.penWidth)
    }

    @Test func onlyTheFreeInkIsOwnedAtFirst() {
        let owned = DrawInks.all.filter { $0.isOwned([]) }
        #expect(owned == [DrawInks.free])
        #expect(DrawInks.all[1].isOwned([DrawInks.all[1].id]))
    }
}
