import FeatureGames
import SwiftUI
import Design
import TipKit
import Transport
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

    /// The ids of the newest notes on the board; a new set rebuilds their faces.
    var boardKey: [String] { BoardFaces.key(state: state) }

    /// Photos to and from the partner; nil until this phone is paired with them.
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
            let buying = state.shop.lastPurchase?.canUndo(at: .now) == true
            return HintContext(
                screen: screen, busy: sheet || buying || room.showcase != nil, hasRoomChoice: hasRoomChoice,
                canAffordTreat: state.shop.coins >= ShopModel.treatPrice,
                petted: state.care.petsGiven > 0,
                added: !state.notes.notes.isEmpty || !state.moments.moments.isEmpty,
                usedMoments: !state.moments.pinned.isEmpty,
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
