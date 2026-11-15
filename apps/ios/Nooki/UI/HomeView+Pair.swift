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
    /// socket, and by a pull at once and every `PartnerSyncMachine.every`, since the socket can be down or silently dead.
    static func partnerSync(session: ServerSession, state: HomeState, room: RoomController) -> PartnerSync {
        PartnerSync(.init(
            follow: { followRoomSocket(session: session, state: state, room: room) },
            unfollow: { session.followInbox(false) },
            pull: { await pullPartner(session: session, state: state) }))
    }

    static func followRoomSocket(session: ServerSession, state: HomeState, room: RoomController) {
        session.followInbox(
            true, photos: session.photoSync(moments: state.moments, partner: state.otherPartner),
            texts: session.textSync(notes: state.notes, partner: state.otherPartner), shop: state.shop,
            lists: state.lists, moods: { [state] in state.moodSync?.received($0) }, streak: state.streak,
            cat: { [room] in room.catEntryArrived($0) }, lastCatSeq: { [room] in room.lastCatSeq })
    }

    /// The games first: they are small, and a photo downloading below can take a while.
    private static func pullPartner(session: ServerSession, state: HomeState) async {
        await session.inbox.refreshCount()
        await session.drawGuess.load()
        await session.whoKnows.load()
        await state.shop.refresh()
        await state.streak.refresh()
        session.reactions?.refresh()
        await session.drawingSync?.fetchLatest()
        await session.textSync(notes: state.notes, partner: state.otherPartner)?.receive()
        await session.photoSync(moments: state.moments, partner: state.otherPartner)?.receive()
        await state.lists.refresh()
    }

    /// The ids of the newest notes on the board; a new set rebuilds their faces.
    var boardKey: [String] { BoardFaces.key(state: state) }

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
            state.moodSync = moods
            await moods.follow(pair.moods)
        } catch {
            if error == .api(.notFound) { return await leavePair() }
            // Offline: a phone that already took the pair keeps following it.
            guard state.profile.couple.pair != nil else { return }
            state.moodSync = moods
        }
        await state.shop.connect(sync)
        await state.gifts.connect(session.giftSync)
        await state.lists.connect(session.listSync)
        guard let pair = state.profile.couple.catPair else { return }
        await state.streak.follow(session.streakRemote)
        await room.connectCat(session.catEvents, pair: pair)
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
                screen: screen, busy: sheet || buying || room.showcase != nil, hasRoomChoice: hasRoomChoice,
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
