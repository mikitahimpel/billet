import MomentsInterface
import WidgetInterface
import WidgetUI
import Testing
import UsInterface
@testable import Billet

/// What a print shows while its photo is decoded at the size it asked for.
@MainActor
@Suite struct MomentPrintTests {
    @Test func theViewerStandsInWithTheFeedPrintThenTheWallPrint() {
        #expect(PrintSizes.standIns(for: MomentStore.storedPixels)
            == [MomentStore.storedPixels, PrintSizes.feed, MomentStore.wallPixels])
    }

    @Test(arguments: [2048, 1024, 512, 384, 100])
    func theSizeAskedForComesFirstAndNothingLarger(maxPixels: Int) {
        let sizes = PrintSizes.standIns(for: maxPixels)
        #expect(sizes.first == maxPixels)
        #expect(sizes.allSatisfy { $0 <= maxPixels })
        #expect(sizes == [maxPixels] + sizes.dropFirst().sorted(by: >))
        #expect(Set(sizes).count == sizes.count)
    }

    @Test func theWallPrintHasNothingSmallerToStandIn() {
        #expect(PrintSizes.standIns(for: MomentStore.wallPixels) == [MomentStore.wallPixels])
    }
}
