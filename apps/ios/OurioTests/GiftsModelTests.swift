import Foundation
import OurioShared
import Persistence
import Testing
import Transport
import Wire
@testable import Billet

/// The pair's room as `GiftsModel` sees it: the room's rules in short, enough to tell the two phones apart.
private nonisolated final class FakeRoom: @unchecked Sendable {
    var wishes: [GiftWish] = []
    /// Wish id to giver's user id.
    var plans: [String: (giver: String, stage: GiftStage)] = [:]
    var loves: [PartnerLoves] = []

    func view(for user: String) -> GiftsResponse {
        GiftsResponse(
            wishes: wishes,
            plans: plans.filter { $0.value.giver == user }
                .map { Wire.GiftPlan(wish: IdempotencyKey($0.key), stage: $0.value.stage) },
            surprise: plans.contains { plan in
                plan.value.giver != user && wishes.contains { $0.id.rawValue == plan.key && $0.owner.rawValue == user }
            },
            loves: loves)
    }

    func sync(as user: String) -> GiftSync {
        GiftSync(
            fetch: { self.view(for: user) },
            saveWish: { request in
                self.wishes.removeAll { $0.id == request.id }
                self.wishes.append(GiftWish(id: request.id, owner: UserId(user), title: request.title,
                                            link: request.link, price: request.price, note: request.note,
                                            mostWanted: request.mostWanted, occasion: request.occasion,
                                            addedAt: 1_700_000_000_000))
                return self.view(for: user)
            },
            deleteWish: { request in
                self.wishes.removeAll { $0.id == request.id }
                return self.view(for: user)
            },
            setPlan: { request in
                self.plans[request.wish.rawValue] = request.stage.map { (user, $0) }
                return self.view(for: user)
            },
            markReceived: { _ throws(TransportError) in throw .status(500) },
            saveLoves: { request in
                self.loves.removeAll { $0.user.rawValue == user }
                self.loves.append(PartnerLoves(user: UserId(user), loves: request.loves))
                return self.view(for: user)
            })
    }
}

@MainActor
@Suite struct GiftsModelTests {
    private let files = (0..<4).map { "Tests/\(UUID().uuidString)-\($0).json" }
    private let users = ["L": "user-l", "M": "user-m"]

    private func phone(_ me: String, file: Int) -> (UsStore, GiftsModel) {
        let us = UsStore(file: files[file * 2])
        let users = users
        return (us, GiftsModel(us: us) { (me, users) })
    }

    private func cleanUp() {
        SharedFile.flush()
        for file in files { try? FileManager.default.removeItem(at: SharedFile.url(file)) }
    }

    private func settle(until done: () -> Bool) async {
        for _ in 0..<200 where !done() { await Task.yield() }
    }

    @Test func aWishMadeBeforePairingReachesThePartnersPhone() async {
        defer { cleanUp() }
        let room = FakeRoom()
        let (lena, lenaGifts) = phone("L", file: 0)
        var bracelet = WishItem(owner: "L", title: "Bracelet", note: "silver")
        let birthday = Date(timeIntervalSince1970: 1_800_000_000)
        bracelet.occasion = WishOccasion(title: "Lena's birthday", date: birthday)
        lena.upsertWish(bracelet)
        var lovesValue = Loves()
        lovesValue.flowers = "Peonies"
        lena.setLoves(lovesValue, for: "L")

        await lenaGifts.connect(room.sync(as: "user-l"))
        let (max, maxGifts) = phone("M", file: 1)
        await maxGifts.connect(room.sync(as: "user-m"))

        #expect(max.wishes(of: "L").map(\.title) == ["Bracelet"])
        #expect(max.wishes(of: "L").first?.note == "silver")
        #expect(max.wishes(of: "L").first?.occasion == WishOccasion(title: "Lena's birthday", date: birthday))
        #expect(max.loves(of: "L").flowers == "Peonies")
    }

    @Test func thePartnersPickStaysOnTheirPhoneAndTheOwnerOnlyLearnsASurpriseIsComing() async throws {
        defer { cleanUp() }
        let room = FakeRoom()
        let (lena, lenaGifts) = phone("L", file: 0)
        let (max, maxGifts) = phone("M", file: 1)
        await lenaGifts.connect(room.sync(as: "user-l"))
        await maxGifts.connect(room.sync(as: "user-m"))

        lena.upsertWish(WishItem(owner: "L", title: "Bracelet"))
        await settle { room.wishes.count == 1 }
        await maxGifts.refresh()
        let id = try #require(max.wishes(of: "L").first?.id)

        max.pick(id, by: "M")
        await settle { !room.plans.isEmpty }
        await lenaGifts.refresh()

        #expect(max.plan(for: id, viewer: "M")?.stage == .planning)
        #expect(lena.plan(for: id, viewer: "M") == nil)
        #expect(lena.plans.isEmpty)
        #expect(lena.surpriseComing(for: "L"))
        #expect(!max.surpriseComing(for: "M"))
    }
}
