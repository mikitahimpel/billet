import FeatureGames
import Observation
import Persistence
import RoomInterface
import SwiftUI
import Design
import WidgetKit

enum HomeTab: CaseIterable {
    case world, moments, shop, us
}

/// Where the Shop opens when something elsewhere points at it, e.g. a locked ink in the drawing palette.
enum ShopFocus: Hashable {
    /// The Inks block in Today, at that ink.
    case ink(String)
    /// That item's sheet.
    case item(String)
}

/// Which of Mochi's rooms the World tab shows.
enum RoomKind: CaseIterable {
    case home, city

    var title: String { self == .home ? "Room" : "City" }

    var scene: RoomScene { self == .home ? .home : .city }
}

/// The Moments tab as a feed of photos and notes, or as the board in Mochi's desk room.
enum MomentsMode {
    case photos, board
}

/// The card on the corkboard the couple tapped; it opens as a sheet.
struct PinRoute: Identifiable {
    let id: UUID
}

struct Mood: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let tint: Color
}

/// The stores and feature models one launch of Home runs on. `HomeView` builds them; nothing below it makes its
/// own. The couple, the wallet, the Us tab, moments and moods live in the app group so the widgets read the same data.
struct HomeStores {
    let profile: CoupleStore
    let wallet: WalletStore
    let us: UsStore
    let partnerMoods: MoodStore
    let streak: StreakStore
    let moments: MomentStore
    let notes: NoteStore
    let rooms: RoomsChoice
    let care: CatCare
    let shop: ShopModel
    let gifts: GiftsModel
    let lists: ListsModel
    let journal: Journal

    /// The stores over the app group's files.
    static func live() -> HomeStores {
        let profile = CoupleStore()
        let wallet = WalletStore()
        let streak = StreakStore()
        let moments = MomentStore()
        let notes = NoteStore()
        let care = CatCare(wallet: wallet, streak: streak)
        let shop = ShopModel(wallet: wallet, couple: profile, care: care)
        let us = UsStore { shop.earn($0) }
        let members: GiftsModel.Members = { profile.couple.pair.map { (profile.couple.viewer, $0.users) } }
        return HomeStores(
            profile: profile, wallet: wallet, us: us, partnerMoods: MoodStore(), streak: streak,
            moments: moments, notes: notes, rooms: RoomsChoice(), care: care, shop: shop,
            gifts: GiftsModel(us: us, members: members), lists: ListsModel(us: us, members: members),
            journal: Journal(moments: moments, notes: notes, streak: streak, couple: profile) { shop.earn($0) })
    }
}

/// Where Home is: the tab, the room, the sheets that are open. The data and its rules are in the stores and models it
/// is given.
@Observable
final class HomeState {
    /// Named in onboarding; Mochi until then.
    var petName: String { CatProfile.name() }
    var tab: HomeTab = .world
    /// Set by `openShop`; the Shop scrolls or opens there, then clears it.
    var shopFocus: ShopFocus?

    /// Opens the Shop at an ink or an item.
    func openShop(_ focus: ShopFocus) {
        shopFocus = focus
        tab = .shop
    }

    var room: RoomKind = .home
    var showsProfile = false
    var showsInbox = false
    /// An invite link opened after onboarding: Home's pairing sheet opens with its code.
    var invitedCode: String?
    /// Asks the World tab to open the cat's sheet, as an Inbox row does.
    var showsPetSheet = false
    /// A shop item opened from outside the Shop, such as an Inbox row.
    var openedShopItem: ShopItem?
    /// The Us tab's open sheet; widgets deep-link into it.
    var usRoute: UsView.Route?
    /// The open note composer; the Add menu and the new-note deep link set it.
    var composingNote: NoteComposer.Mode?
    /// The lock-screen drawing is open; the Add menu's Draw and a drawing widget's tap set it.
    var drawing = false
    /// The card the couple tapped on the board, opened as a sheet.
    var openedPin: PinRoute?
    var momentsMode: MomentsMode = .photos

    let moods = [
        Mood(title: "Happy", symbol: "heart.fill", tint: Color(hex: 0xFF7A93)),
        Mood(title: "Rested", symbol: "bolt.fill", tint: Color(hex: 0xFFC94A)),
        Mood(title: "Full", symbol: "fork.knife", tint: Color(hex: 0xF3A25E)),
        Mood(title: "Curious", symbol: "sparkles", tint: Color(hex: 0xFFD76A)),
    ]

    let profile: CoupleStore
    /// Lists, wishlists, calendar and dates on the Us tab.
    let us: UsStore
    /// Each partner's latest check-in, mostly left from the widget.
    let partnerMoods: MoodStore
    /// Days in a row the couple did something together; see docs/love-streak.md.
    let streak: StreakStore
    /// Shared photo diary; its pinned moments hang as polaroids on the room wall.
    let moments: MomentStore
    /// Notes and doodles pinned on the board.
    let notes: NoteStore
    /// Which rooms this pair has: both, or one (the `rooms` experiment, see docs/experiments.md).
    let rooms: RoomsChoice
    let care: CatCare
    let shop: ShopModel
    /// The Us tab's gifts in step with the pair's room once paired.
    let gifts: GiftsModel
    /// The Us tab's lists in step with the pair's room once paired.
    let lists: ListsModel
    let journal: Journal
    @ObservationIgnored private let wallet: WalletStore

    init(stores: HomeStores) {
        profile = stores.profile
        us = stores.us
        partnerMoods = stores.partnerMoods
        streak = stores.streak
        moments = stores.moments
        notes = stores.notes
        rooms = stores.rooms
        care = stores.care
        shop = stores.shop
        gifts = stores.gifts
        lists = stores.lists
        journal = stores.journal
        wallet = stores.wallet
        #if DEBUG
        // For screenshots: `-shotMoments photos` or `board` opens Moments in that mode, `-shotMoment 0` opens that photo.
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "shotMoments") {
        case "photos": tab = .moments
        case "board":
            tab = .moments
            // After launch, so Home sees the change and builds the board room.
            Task {
                try? await Task.sleep(for: .seconds(2))
                momentsMode = .board
            }
        default: break
        }
        // For screenshots: `-shopCoins 20` sets the balance and `-shopOwned lamp,rug` what the couple owns.
        if defaults.object(forKey: "shopCoins") != nil {
            let coins = defaults.integer(forKey: "shopCoins")
            wallet.update { $0.coins = coins }
        }
        if let owned = defaults.string(forKey: "shopOwned") {
            wallet.update { $0.owned = Set(owned.split(separator: ",").map(String.init)) }
        }
        if defaults.object(forKey: "shotMoment") != nil, moments.moments.indices.contains(defaults.integer(forKey: "shotMoment")) {
            tab = .moments
            openedPin = PinRoute(id: moments.moments[defaults.integer(forKey: "shotMoment")].id)
        }
        #endif
    }

    var partners: (String, String) { (profile.couple.partners[0], profile.couple.partners[1]) }
    var daysTogether: Int { profile.couple.daysTogether() }
    var togetherSince: Date { profile.couple.togetherSince }

    /// Which partner is holding the phone: the signed-in user once paired, a switch on the Us tab before that.
    var viewer: String {
        get { profile.couple.viewer }
        set { profile.setViewer(newValue) }
    }
    var otherPartner: String { profile.couple.other }

    /// Follows the pair's room once paired; nil keeps check-ins on this phone.
    var moodSync: MoodSync?

    /// Shows at once here and goes to the partner through the room.
    func setMood(_ mood: PartnerMood, note: String? = nil) {
        partnerMoods.set(mood, note: note, for: viewer)
        streak.record()
        guard let sync = moodSync, let check = partnerMoods.latest[viewer] else { return }
        Task { await sync.share(check) }
    }

    /// Back in the foreground: pick up what the widgets changed and let Mochi feel the pets from outside the app.
    /// `reloading` false skips reading the stores again, for launch, where they were read a moment ago.
    func refresh(reloading: Bool = true) {
        if reloading {
            profile.reload()
            wallet.reload()
            partnerMoods.reload()
            us.reload()
            moments.reload()
            notes.reload()
            streak.reload()
        }
        var activity = WidgetActivity.load()
        let pets = activity.takePendingPets()
        guard pets > 0 else { return }
        activity.save()
        for _ in 0..<min(pets, 5) { care.pet() }
    }

    /// Deletes every store's files from the app group (or Documents) and this phone's preferences; the caller starts
    /// over with a fresh HomeState. The account stays: its record shares the folder, and its token in the Keychain
    /// would otherwise outlive it, signing the phone out halfway.
    static func eraseAll() {
        // Pending writes would otherwise land after the files are gone.
        SharedFile.flush()
        let files = FileManager.default
        for url in (try? files.contentsOfDirectory(at: AppGroup.container, includingPropertiesForKeys: nil)) ?? []
        where url.lastPathComponent != AccountStore.recordName {
            try? files.removeItem(at: url)
        }
        if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
        CatProfile.store.removeObject(forKey: CatProfile.nameKey)
        CatProfile.store.removeObject(forKey: CatProfile.coatKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Leaving the app: the widgets redraw from what was saved here.
    func didEnterBackground() {
        SharedFile.flush()
        CatProfile.store.set(CatCoat.current().rawValue, forKey: CatProfile.coatKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func open(_ link: DeepLink) {
        switch link {
        case .room: tab = .world
        case .moments: tab = .moments
        case .us: tab = .us
        case .calendar: showUs(.calendar)
        case .dates: showUs(.dates)
        case .newNote:
            tab = .moments
            composingNote = .write
        case .draw: drawing = true
        case .inbox: showsInbox = true
        case .list(let id): showUs(us.list(id) == nil ? nil : .list(id))
        case .invite(let code):
            // Before onboarding is done, the link is its code page's.
            if UserDefaults.standard.bool(forKey: OnboardingFlow.doneKey) { invitedCode = code }
        case .shopInk(let id): openShop(.ink(id))
        }
    }

    private func showUs(_ route: UsView.Route?) {
        tab = .us
        usRoute = route
    }
}
