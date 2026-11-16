import FeatureGames
import FeatureMood
import FeatureShop
import MomentsInterface
import ServerSync
import ShopInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import Design
import TipKit
import Transport
import UsInterface
import WidgetBridge
import Wire

extension HomeView {
    /// Reads the pair's variants while the account has a partner, and forgets them when it has none.
    func refreshRooms() {
        guard let session else { return }
        guard session.isPaired else { return state.rooms.forget() }
        let rooms = state.rooms
        Task { await rooms.refresh(session.api) }
    }

    /// Counts `RoomOpened` once per room each time the app is in front, so the test can compare the rooms.
    func reportOpened(_ room: RoomKind) {
        guard let session, state.tab == .world, reportedRooms.insert(room).inserted else { return }
        let api = session.api
        Task { try? await api.reportEvents([ClientEvent(.roomOpened, detail: room.eventDetail)]) }
    }

    /// The partner's notes, games, coins and Inbox reach this phone while it is in front and paired: over the room's
    /// socket, with a pull each time it opens and, as `PartnerSyncMachine` paces it, while it is quiet or down.
    static func partnerSync(session: ServerSession, state: HomeState, room: RoomController) -> PartnerSync {
        let relay = SocketOpenedRelay()
        let sync = PartnerSync(.init(
            follow: { followRoomSocket(session: session, state: state, room: room, opened: relay.opened) },
            unfollow: { session.followInbox(false) },
            isHealthy: { await session.roomSocketIsHealthy(quietLimit: $0) },
            pull: { await pullPartner($0, session: session, state: state, room: room) }))
        relay.sync = sync
        return sync
    }

    private static func followRoomSocket(
        session: ServerSession, state: HomeState, room: RoomController, opened: @escaping @MainActor () -> Void
    ) {
        session.followInbox(
            true, photos: session.photoSync(moments: state.moments, partner: state.otherPartner),
            texts: session.textSync(notes: state.notes, partner: state.otherPartner), shop: state.shop,
            lists: state.lists, moods: { [state] in state.moodSync?.received($0) }, streak: state.streak,
            cat: { [room] in room.catEntryArrived($0) }, lastCatSeq: { [room] in room.lastCatSeq },
            opened: opened,
            catSaved: { [room, state] in
                Task {
                    await room.syncCat()
                    state.refreshPronouns()
                }
            },
            partnerCame: { [weak session, state] in
                // No frame says a name or the pair's day changed. The partner's phone sends both as it comes to
                // front, often a moment after its presence: one read now and one shortly after.
                guard let session else { return }
                Task {
                    await pullPairProfile(session: session, state: state)
                    try? await Task.sleep(for: pairProfileSettle)
                    await pullPairProfile(session: session, state: state)
                }
            })
    }

    private static let pairProfileSettle = Duration.seconds(5)

    /// The partner's name and the pair's day, and what the server lacks of this phone's.
    private static func pullPairProfile(session: ServerSession, state: HomeState) async {
        guard state.profile.couple.pair != nil, let pair = try? await session.pair() else { return }
        await PairProfileSync.take(pair, into: state.profile, api: session.api)
    }

    /// The games first: they are small, and a photo downloading below can take a while. The summary is four reads:
    /// the Inbox count (a new note or drawing shows there), the riddles, the shop with the wallet and the pair, for
    /// the partner's name and the pair's day. Everything
    /// includes the pair's cat, for a `CatSaved` the socket missed: the joiner's waits for the inviter's.
    private static func pullPartner(
        _ kind: PartnerSyncMachine.Kind, session: ServerSession, state: HomeState, room: RoomController
    ) async {
        await session.inbox.refreshCount()
        await session.drawGuess.load()
        await state.shop.refresh()
        await pullPairProfile(session: session, state: state)
        switch kind {
        case .summary: return
        case .everything: break
        }
        await session.whoKnows.load()
        await state.streak.refresh()
        session.reactions?.refresh()
        await session.drawingSync?.fetchLatest()
        await session.textSync(notes: state.notes, partner: state.otherPartner)?.receive()
        await session.photoSync(moments: state.moments, partner: state.otherPartner)?.receive()
        await state.lists.refresh()
        await room.syncCat()
        state.refreshPronouns()
    }

    /// The newest notes on the board and whether each still waits to be sent; a change rebuilds their faces.
    var boardKey: [String] { BoardFaces.key(state: state, paired: session?.isPaired == true) }

    /// Once paired, the monograms belong to the pair's two accounts and the shop, the gifts and the lists follow the
    /// pair's room.
    func followPair() async {
        #if DEBUG
        if ShopFixture.isOn { return await state.shop.connect(ShopFixture(offers: state.shop.offers).sync) }
        #endif
        guard let session, let sync = session.shopSync else { return await leavePair() }
        let moods = MoodSync(send: session.api.setMood, moods: state.partnerMoods, couple: state.profile)
        do throws(TransportError) {
            let pair = try await session.pair()
            state.profile.adopt(
                pairID: pair.pairId.rawValue, me: pair.members[0].rawValue, partner: pair.members[1].rawValue)
            await PairProfileSync.take(pair, into: state.profile, api: session.api)
            state.moodSync = moods
            await moods.follow(pair.moods)
        } catch {
            if error == .api(.notFound) { return await leavePair() }
            // Offline: a phone that already took the pair keeps following it.
            guard state.profile.couple.pair != nil else { return }
            state.moodSync = moods
        }
        if let since = state.togetherSince { state.notes.queueDoodles(by: state.viewer, since: since) }
        await state.shop.connect(sync)
        await state.gifts.connect(session.giftSync)
        await state.lists.connect(session.listSync)
        guard let pair = state.profile.couple.catPair else { return }
        await state.streak.follow(session.streakRemote)
        let followedCat = room.lastCatSeq != nil
        await room.connectCat(session.catEvents, pair: pair)
        // A socket opened before the cat was the pair's follows no journal, so it never hears `CatSaved`.
        if !followedCat, room.lastCatSeq != nil { session.reopenRoomSocket() }
        state.refreshPronouns()
    }

    private func leavePair() async {
        state.moodSync = nil
        state.profile.leavePair()
        await state.shop.connect(nil)
        await state.gifts.connect(nil)
        await state.lists.connect(nil)
        await state.streak.follow(nil)
        await room.connectCat(nil, pair: nil)
    }

    /// Each tab shown, and each return to the app, is a visit that may show one hint.
    func visitHints() {
        hints.visit {
            let screen: HintScreen = switch state.tab {
            case .world: .world
            case .moments: .moments
            case .shop: .shop
            case .us: .other
            }
            let sheet = state.composingNote != nil || state.drawing || state.showsProfile || state.showsInbox
                || state.openedShopItem != nil
            let buying = state.shop.lastPurchase?.momentShows(at: .now) == true
            return HintContext(
                // A hint shown under the splash points at nothing and pokes out over its title.
                screen: screen, busy: launching || sheet || buying || room.showcase != nil,
                hasRoomChoice: hasRoomChoice,
                canAffordTreat: state.shop.coins >= ShopModel.treatPrice,
                petted: state.care.petsGiven > 0,
                added: !state.notes.notes.isEmpty || !state.moments.moments.isEmpty,
                usedMoments: !state.moments.pinned.isEmpty,
                momentsEmpty: state.moments.moments.isEmpty && state.notes.notes.isEmpty,
                purchased: !state.shop.owned.isSubset(of: Wallet().owned),
                switchedRooms: state.room == .city,
                gaveTreat: state.care.treatsGiven > 0)
        }
    }

    /// Photos to and from the partner; nil until this phone is paired with them.
    var photoSync: PhotoSync? {
        session?.photoSync(moments: state.moments, partner: state.otherPartner)
    }

    var textSync: TextNoteSync? {
        session?.textSync(notes: state.notes, partner: state.otherPartner)
    }
}

/// Tells the sync its socket opened without the sync's own closures holding it.
@MainActor
private final class SocketOpenedRelay {
    weak var sync: PartnerSync?

    func opened() { sync?.send(.socketOpened) }
}
