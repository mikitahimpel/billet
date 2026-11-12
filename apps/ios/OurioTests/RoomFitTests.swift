import Foundation
import Testing

@testable import Billet

struct RoomFitTests {
    private func halfWidth(_ degrees: Float, aspect: Float) -> Float { tan(degrees * .pi / 360) * aspect }

    @Test func theReferenceScreenAndWiderOnesKeepTheFieldOfView() {
        #expect(RoomFit.verticalFieldOfView(22, aspect: RoomFit.referenceAspect) == 22)
        #expect(RoomFit.verticalFieldOfView(22, aspect: 0.75) == 22)
        #expect(RoomFit.verticalFieldOfView(22, aspect: 1.6) == 22)
    }

    @Test func aTallScreenSeesTheWidthTheReferenceSees() {
        let aspects: [Float] = [440.0 / 956, 402.0 / 874, 0.3]
        for aspect in aspects {
            let fov = RoomFit.verticalFieldOfView(22, aspect: aspect)
            #expect(fov > 22)
            let reference = halfWidth(22, aspect: RoomFit.referenceAspect)
            #expect(abs(halfWidth(fov, aspect: aspect) - reference) < 1e-5)
        }
    }

    @Test func aDegenerateAspectChangesNothing() {
        #expect(RoomFit.verticalFieldOfView(22, aspect: 0) == 22)
        #expect(RoomFit.verticalFieldOfView(22, aspect: -1) == 22)
    }
}
