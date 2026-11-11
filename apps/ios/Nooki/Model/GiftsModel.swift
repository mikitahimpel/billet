import Foundation
import MomentsInterface
import WidgetInterface
import WidgetUI
import Transport
import UsInterface
import Wire

/// Keeps the Us tab's gifts in step with the pair's room while the phone is paired: each change made here is sent
/// as it happens, and every answer replaces the phone's copy.
final class GiftsModel {
    /// Who holds this phone and the pair's user ids by monogram; nil until paired.
    typealias Members = () -> (me: String, users: [String: String])?

    private let us: UsStore
    private let members: Members
    private var sync: GiftSync?

    init(us: UsStore, members: @escaping Members) {
        self.us = us
        self.members = members
        us.onGiftChange = { [weak self] change in
            Task { await self?.send(change) }
        }
    }

    /// Follows the pair's room, or, with nil, keeps the gifts as the phone has them. What this account made before
    /// pairing, or while offline, and the room lacks is sent first.
    func connect(_ sync: GiftSync?) async {
        self.sync = sync
        guard let sync, let view = try? await sync.fetch() else { return }
        apply(await upload(missingFrom: view, sync))
    }

    /// Reads the pair's room again, sending anything of this account's the room lacks.
    func refresh() async {
        await connect(sync)
    }

    private func send(_ change: GiftChange) async {
        guard let sync, let me = members()?.me else { return }
        let answer: GiftsResponse?
        switch change {
        case .save(let wish):
            guard wish.owner == me else { return }
            answer = try? await sync.saveWish(Self.request(wish))
        case .delete(let id):
            answer = try? await sync.deleteWish(DeleteGiftWishRequest(id: Self.key(id)))
        case .plan(let id, let stage):
            answer = try? await sync.setPlan(SetGiftPlanRequest(wish: Self.key(id), stage: stage.map(Self.stage)))
        case .received(let id, let received):
            answer = try? await sync.markReceived(MarkGiftReceivedRequest(wish: Self.key(id), received: received))
        case .loves(let loves, let partner):
            guard partner == me else { return }
            answer = try? await sync.saveLoves(SaveLovesRequest(loves: Self.wire(loves)))
        }
        // A refused or lost change comes back as the room has it on the next read.
        if let answer { apply(answer) }
    }

    private func upload(missingFrom view: GiftsResponse, _ sync: GiftSync) async -> GiftsResponse {
        guard let (me, users) = members(), let myID = users[me] else { return view }
        var view = view
        let known = Set(view.wishes.compactMap { UUID(uuidString: $0.id.rawValue) })
        for wish in us.wishes where wish.owner == me && wish.gifted == nil && !known.contains(wish.id) {
            if let answer = try? await sync.saveWish(Self.request(wish)) { view = answer }
        }
        let partners = Set(view.wishes.filter { $0.owner.rawValue != myID && $0.receivedAt == nil }
            .compactMap { UUID(uuidString: $0.id.rawValue) })
        let planned = Set(view.plans.compactMap { UUID(uuidString: $0.wish.rawValue) })
        let unsent = us.plans.filter { $0.giver == me && partners.contains($0.wishID) && !planned.contains($0.wishID) }
        for plan in unsent {
            let request = SetGiftPlanRequest(wish: Self.key(plan.wishID), stage: Self.stage(plan.stage))
            if let answer = try? await sync.setPlan(request) { view = answer }
        }
        let mine = us.loves(of: me)
        if mine != Loves(), !view.loves.contains(where: { $0.user.rawValue == myID }),
           let answer = try? await sync.saveLoves(SaveLovesRequest(loves: Self.wire(mine))) {
            view = answer
        }
        return view
    }

    private func apply(_ view: GiftsResponse) {
        guard let (me, users) = members() else { return }
        let monograms = Dictionary(users.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        let wishes = view.wishes.compactMap { wish -> WishItem? in
            guard let id = UUID(uuidString: wish.id.rawValue), let owner = monograms[wish.owner.rawValue] else {
                return nil
            }
            var item = WishItem(id: id, owner: owner, title: wish.title, link: wish.link, price: wish.price,
                                note: wish.note, mostWanted: wish.mostWanted, added: Self.date(wish.addedAt))
            item.occasion = wish.occasion.map { WishOccasion(title: $0.title, date: Self.date($0.date)) }
            item.gifted = wish.receivedAt.map(Self.date)
            item.giftedBy = wish.giftedBy.flatMap { monograms[$0.rawValue] }
            return item
        }
        let plans = view.plans.compactMap { plan in
            UUID(uuidString: plan.wish.rawValue).map {
                GiftPlan(wishID: $0, giver: me, stage: plan.stage == .bought ? .bought : .planning)
            }
        }
        var loves: [String: Loves] = [:]
        for entry in view.loves {
            guard let partner = monograms[entry.user.rawValue] else { continue }
            loves[partner] = Self.app(entry.loves)
        }
        us.mirrorGifts(wishes: wishes, plans: plans, loves: loves, surprise: view.surprise ? me : nil)
    }

    // MARK: Wire

    private static func key(_ id: UUID) -> IdempotencyKey { IdempotencyKey(id.uuidString) }

    private static func date(_ millis: Int) -> Date { Date(timeIntervalSince1970: Double(millis) / 1000) }

    private static func stage(_ stage: GiftPlan.Stage) -> GiftStage {
        switch stage {
        case .planning: .planning
        case .bought: .bought
        }
    }

    /// Cut to the room's limits, which the editor doesn't enforce.
    private static func request(_ wish: WishItem) -> SaveGiftWishRequest {
        SaveGiftWishRequest(id: key(wish.id), title: String(wish.title.prefix(200)),
                            link: String(wish.link.prefix(2048)), price: String(wish.price.prefix(40)),
                            note: String(wish.note.prefix(500)), mostWanted: wish.mostWanted,
                            occasion: wish.occasion.map {
                                GiftOccasion(title: String($0.title.prefix(60)),
                                             date: Int(($0.date.timeIntervalSince1970 * 1000).rounded()))
                            })
    }

    private static func wire(_ loves: Loves) -> GiftLoves {
        GiftLoves(sizes: String(loves.sizes.prefix(200)), flowers: String(loves.flowers.prefix(200)),
                  coffee: String(loves.coffee.prefix(200)), sweets: String(loves.sweets.prefix(200)),
                  allergies: String(loves.allergies.prefix(200)), avoid: String(loves.avoid.prefix(200)))
    }

    private static func app(_ loves: GiftLoves) -> Loves {
        var value = Loves()
        value.sizes = loves.sizes
        value.flowers = loves.flowers
        value.coffee = loves.coffee
        value.sweets = loves.sweets
        value.allergies = loves.allergies
        value.avoid = loves.avoid
        return value
    }
}
