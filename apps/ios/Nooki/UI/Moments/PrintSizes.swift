import MomentsInterface
import OurioShared
import UIKit
import UsInterface

/// The sizes, in pixels on the long side, a Moments print is decoded at.
enum PrintSizes {
    static let feed = 512

    /// The sizes a print of `maxPixels` may already be cached at, the size itself first, then the smaller ones the
    /// feed and the wall draw. One of them stands in while `maxPixels` is decoded, so the viewer's print shows the
    /// photo at once instead of a blank that fills in a moment later.
    static func standIns(for maxPixels: Int) -> [Int] {
        [maxPixels] + [feed, MomentStore.wallPixels].filter { $0 < maxPixels }.sorted(by: >)
    }
}

extension MomentStore {
    /// The sharpest print of `moment` already decoded at `maxPixels` or below.
    func standInFilmPrint(for moment: Moment, maxPixels: Int) -> UIImage? {
        PrintSizes.standIns(for: maxPixels).lazy.compactMap { self.cachedFilmPrint(for: moment, maxPixels: $0) }.first
    }
}
