import Foundation
import MomentsInterface
import OurioShared
import Persistence
import Testing
import UsInterface
import Wire
@testable import Billet

@Suite struct WishlistTests {
    private let path = "Tests/\(UUID().uuidString)-us.json"

    private func store(onEarn: @escaping (EarnEvent) -> Void = { _ in }) -> UsStore {
        UsStore(file: path, onEarn: onEarn)
    }

    private func cleanUp() {
        SharedFile.flush()
        try? FileManager.default.removeItem(at: SharedFile.url(path))
    }

    private func wish(_ us: UsStore, owner: String = "L", _ title: String = "Bracelet") -> UUID {
        let wish = WishItem(owner: owner, title: title)
        us.upsertWish(wish)
        return wish.id
    }

    @Test func theOwnerNeverSeesWhichWishIsPicked() {
        defer { cleanUp() }
        let us = store()
        let id = wish(us)
        us.pick(id, by: "M")

        #expect(us.plan(for: id, viewer: "L") == nil)
        #expect(us.plan(for: id, viewer: "M")?.stage == .planning)
        #expect(us.surpriseComing(for: "L"))
        #expect(!us.surpriseComing(for: "M"))
    }

    @Test func nobodyPicksTheirOwnWishOrOneAlreadyPicked() {
        defer { cleanUp() }
        let us = store()
        let id = wish(us)
        us.pick(id, by: "L")
        #expect(us.plans.isEmpty)

        us.pick(id, by: "M")
        us.pick(id, by: "X")
        #expect(us.plans.map(\.giver) == ["M"])
    }

    @Test func onlyTheGiverMovesOrReleasesTheirPlan() {
        defer { cleanUp() }
        let us = store()
        let id = wish(us)
        us.pick(id, by: "M")
        us.setStage(.bought, of: id, by: "L")
        us.release(id, by: "L")
        #expect(us.plan(for: id, viewer: "M")?.stage == .planning)

        us.setStage(.bought, of: id, by: "M")
        #expect(us.plan(for: id, viewer: "M")?.stage == .bought)
        us.release(id, by: "M")
        #expect(us.plans.isEmpty)
        #expect(!us.surpriseComing(for: "L"))
    }

    @Test func receivingClosesThePlanAndPaysOnce() {
        defer { cleanUp() }
        var earns: [EarnEvent] = []
        let us = store { earns.append($0) }
        let id = wish(us)
        us.pick(id, by: "M")

        us.markReceived(id, by: "M")
        #expect(us.gifted(to: "L").isEmpty)

        us.markReceived(id, by: "L")
        #expect(us.gifted(to: "L").first?.giftedBy == "M")
        #expect(us.plans.isEmpty)
        #expect(earns == [.wishReceived(wish: id.uuidString)])

        us.unmarkReceived(id, by: "L")
        #expect(us.wishes(of: "L").map(\.id) == [id])
        us.markReceived(id, by: "L")
        #expect(earns == [.wishReceived(wish: id.uuidString)])
    }

    @Test func mostWantedComesFirstThenNewest() {
        defer { cleanUp() }
        let us = store()
        let old = WishItem(owner: "L", title: "Old", added: .now.addingTimeInterval(-100))
        let new = WishItem(owner: "L", title: "New")
        let pinned = WishItem(owner: "L", title: "Pinned", mostWanted: true, added: .now.addingTimeInterval(-200))
        [old, new, pinned].forEach(us.upsertWish)
        #expect(us.wishes(of: "L").map(\.title) == ["Pinned", "New", "Old"])
    }

    @Test func oldReservationsBecomeTheGiversPlans() throws {
        defer { cleanUp() }
        let picked = UUID(), done = UUID()
        let old = """
        {"lists":[],"events":[],"planned":[],"swipes":{},
         "loves":{"L":{"sizes":"S","flowers":"","coffee":"","sweets":"","allergies":""}},
         "wishes":[
          {"id":"\(picked)","owner":"L","title":"Bracelet","link":"","price":"$65","want":3,"reservedBy":"M"},
          {"id":"\(done)","owner":"L","title":"Sunflowers","link":"","price":"","want":2,"reservedBy":"M","gifted":0}
         ]}
        """
        let url = SharedFile.url(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(old.utf8).write(to: url)

        let us = store()
        #expect(us.plans == [GiftPlan(wishID: picked, giver: "M")])
        #expect(us.wishes(of: "L").first?.mostWanted == true)
        #expect(us.gifted(to: "L").first?.rewarded == true)
        #expect(us.loves(of: "L").sizes == "S")

        // The old field is gone from what is written back.
        us.release(picked, by: "M")
        SharedFile.flush()
        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(!written.contains("reservedBy"))
    }
}
