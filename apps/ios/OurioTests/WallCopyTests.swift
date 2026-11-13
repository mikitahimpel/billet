import Testing
@testable import Billet

/// The wall card says how full the wall is and, while there is room, points at the "+" that hangs a photo.
struct WallCopyTests {
    @Test func anEmptyWallAsksForAPhoto() {
        #expect(WallCopy.detail(pinned: 0, slots: 6) == "Empty · tap + to hang a photo")
    }

    @Test(arguments: [1, 3, 5])
    func aWallWithRoomCountsAndPointsAtThePlus(pinned: Int) {
        #expect(WallCopy.detail(pinned: pinned, slots: 6) == "\(pinned) of 6 · tap + to hang one")
    }

    @Test func aFullWallSaysWhatANewPinDoes() {
        #expect(WallCopy.detail(pinned: 6, slots: 6) == "6 of 6 · full; a new pin swaps the oldest")
    }
}
