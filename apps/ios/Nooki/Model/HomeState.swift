import Observation
import SwiftUI
import WidgetKit

enum HomeTab: CaseIterable {
    case world, moments, shop, us
}

/// Which of Mochi's rooms the World tab shows.
enum RoomKind: CaseIterable {
    case home, city

    var title: String { self == .home ? "Room" : "City" }
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

/// Home screen state; no backend yet. The couple, the wallet, the Us tab, moments and moods live in the app group so
/// the widgets read the same data.
@Observable
final class HomeState {
    /// Named in onboarding; Mochi until then.
    var petName: String { CatProfile.name() }
    var tab: HomeTab = .world
    var room: RoomKind = .home
    var petPulse = 0
    /// Treats given since launch.
    private(set) var treatsGiven = 0
    var showsSettings = false
    var showsInbox = false
    /// Asks the World tab to open the cat's sheet, as an Inbox row does.
    var showsPetSheet = false
    /// A shop item opened from outside the Shop, such as an Inbox row.
    var openedShopItem: ShopItem?

    let moods = [
        Mood(title: "Happy", symbol: "heart.fill", tint: Color(hex: 0xFF7A93)),
        Mood(title: "Rested", symbol: "bolt.fill", tint: Color(hex: 0xFFC94A)),
        Mood(title: "Full", symbol: "fork.knife", tint: Color(hex: 0xF3A25E)),
        Mood(title: "Curious", symbol: "sparkles", tint: Color(hex: 0xFFD76A)),
    ]

    /// Shop state: both partners share one wallet, room and wishlist.
    let wallet = WalletStore()
    var coins: Int { wallet.wallet.coins }
    var level: Int { wallet.wallet.level }
    var progress: Double { wallet.wallet.progress }
    var owned: Set<String> { wallet.wallet.owned }
    var wishlist: Set<String> { wallet.wallet.wishlist }
    var gifted: Set<String> { wallet.wallet.gifted }

    /// The Shop's daily and weekly rotations, the same on both partners' phones.
    var offers: ShopOffers { ShopOffers(pairSeed: profile.couple.partners.sorted().joined(separator: "+")) }

    /// Today's price: the deal price when the item is one of today's deals.
    func price(of item: ShopItem, on date: Date = .now) -> Int {
        offers.deal(for: item.id, on: date)?.price(of: item) ?? item.price
    }

    private static let giftFile = "Shop/gift.json"
    private(set) var giftLog = SharedFile.read(GiftLog.self, from: giftFile) ?? GiftLog()

    func canClaimGift(on date: Date = .now) -> Bool { giftLog.canClaim(on: date) }

    /// Opens the day's free gift: coins into the wallet, or an item into the room's closet. Nil if it's already open.
    func claimGift(on date: Date = .now) -> GiftReward? {
        guard canClaimGift(on: date) else { return nil }
        let reward = offers.gift(on: date, owned: owned)
        wallet.update {
            switch reward {
            case .coins(let amount): $0.coins += amount
            case .item(let id): $0.owned.insert(id)
            }
        }
        giftLog.claimedDay = date
        SharedFile.write(giftLog, to: Self.giftFile)
        return reward
    }

    /// Buys a set's missing pieces at the set price: the featured set or a bundle.
    @discardableResult
    func buy(_ set: some PieceSet) -> Bool {
        guard let quote = ShopOffers.price(of: set, owned: owned) else { return false }
        return record { $0.buy(set.itemIDs, cost: quote.price, title: set.name, at: .now) }
    }

    /// The latest buy: the purchase moment plays for it and offers Undo for a few seconds.
    private(set) var lastPurchase: Purchase?

    /// Takes a buy back within its Undo window: the coins return and the pieces it added leave the closet.
    @discardableResult
    func undo(_ purchase: Purchase, at now: Date = .now) -> Bool {
        guard lastPurchase?.id == purchase.id, purchase.canUndo(at: now) else { return false }
        wallet.update { $0.undo(purchase) }
        lastPurchase = nil
        return true
    }

    private func record(_ buy: (inout Wallet) -> Purchase?) -> Bool {
        var made: Purchase?
        wallet.update { made = buy(&$0) }
        guard let made else { return false }
        lastPurchase = made
        // Mochi notices: the room's cat purrs at the next look.
        petPulse += 1
        return true
    }

    private static let collectionsFile = "Shop/collections.json"
    private(set) var collectionLog = SharedFile.read(CollectionLog.self, from: collectionsFile) ?? CollectionLog()

    /// The bonus waits until every piece is owned, and is collected once.
    func canClaimBonus(_ collection: ShopCollection) -> Bool {
        collection.isComplete(owned) && !collectionLog.claimed.contains(collection.id)
    }

    @discardableResult
    func claimBonus(_ collection: ShopCollection) -> Bool {
        guard canClaimBonus(collection) else { return false }
        wallet.earn(collection.bonus)
        collectionLog.claimed.insert(collection.id)
        SharedFile.write(collectionLog, to: Self.collectionsFile)
        return true
    }

    /// Deducts from the shared wallet. Gifts arrive wrapped and the partner unwraps them.
    @discardableResult
    func buy(_ item: ShopItem, asGift: Bool = false) -> Bool {
        let price = price(of: item)
        return record { $0.buy([item.id], cost: price, title: item.name, giftTo: asGift, at: .now) }
    }

    func toggleWish(_ item: ShopItem) {
        wallet.update { if $0.wishlist.remove(item.id) == nil { $0.wishlist.insert(item.id) } }
    }

    /// Lists, wishlists, calendar and dates on the Us tab.
    let us: UsStore

    /// The Us tab's open sheet; widgets deep-link into it.
    var usRoute: UsView.Route?

    let profile = CoupleStore()
    /// Each partner's latest check-in, mostly left from the widget.
    let partnerMoods = MoodStore()

    var partners: (String, String) { (profile.couple.partners[0], profile.couple.partners[1]) }
    var daysTogether: Int { profile.couple.daysTogether() }
    var togetherSince: Date { profile.couple.togetherSince }

    /// Which partner is holding the phone. Until sync lands both share one device and switch on the Us tab.
    var viewer: String {
        get { profile.couple.viewer }
        set { profile.setViewer(newValue) }
    }
    var otherPartner: String { profile.couple.other }

    func setMood(_ mood: PartnerMood) {
        partnerMoods.set(mood, for: viewer)
        streak.record()
    }

    /// Days in a row the couple did something together; see docs/love-streak.md.
    let streak = StreakStore()

    init() {
        us = UsStore(wallet: wallet)
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
        if defaults.object(forKey: "shotMoment") != nil, moments.moments.indices.contains(defaults.integer(forKey: "shotMoment")) {
            tab = .moments
            openedPin = PinRoute(id: moments.moments[defaults.integer(forKey: "shotMoment")].id)
        }
        #endif
    }

    /// Shared photo diary; its pinned moments hang as polaroids on the room wall.
    let moments = MomentStore()

    /// Adding a moment earns the couple 10 coins (see docs/shop-concept.md). A photo that `shares` also goes to the
    /// partner once this phone is paired (`PhotoSync`); a drawing's keepsake does not, as the drawing went already.
    @discardableResult
    func addMoment(_ image: UIImage, caption: String, shares: Bool = false) -> Bool {
        guard moments.add(image, caption: caption, author: partners.0, unsent: shares) != nil else { return false }
        wallet.earn(10)
        streak.record()
        return true
    }

    /// Notes and doodles pinned on the board.
    let notes = NoteStore()

    /// The open note composer; the Add menu and the new-note deep link set it.
    var composingNote: NoteComposer.Mode?

    /// The lock-screen drawing is open; the Add menu's Draw and a drawing widget's tap set it.
    var drawing = false

    /// The card the couple tapped on the board, opened as a sheet.
    var openedPin: PinRoute?
    var momentsMode: MomentsMode = .photos

    /// Adding a note earns the couple 5 coins.
    @discardableResult
    func addNote(text: String, paper: Note.Paper) -> Bool {
        guard notes.add(text: text, paper: paper, author: viewer) != nil else { return false }
        wallet.earn(5)
        streak.record()
        return true
    }

    @discardableResult
    func addNote(doodle: UIImage, paper: Note.Paper) -> Bool {
        guard notes.add(doodle: doodle, paper: paper, author: viewer) != nil else { return false }
        wallet.earn(5)
        streak.record()
        return true
    }

    func pet() {
        petPulse += 1
        care(0.03)
        streak.record()
    }

    nonisolated static let treatPrice = 10

    /// A treat from the shared wallet; it fills more of her bar than a pet.
    func treat() -> Bool {
        guard coins >= Self.treatPrice else { return false }
        wallet.update { $0.coins -= Self.treatPrice }
        treatsGiven += 1
        petPulse += 1
        care(0.1)
        streak.record()
        return true
    }

    private func care(_ amount: Double) {
        wallet.update {
            $0.progress += amount
            if $0.progress >= 1 {
                $0.progress -= 1
                $0.level += 1
            }
        }
    }

    /// Back in the foreground: pick up what the widgets changed and let Mochi feel the pets from outside the app.
    func refresh() {
        profile.reload()
        wallet.reload()
        giftLog = SharedFile.read(GiftLog.self, from: Self.giftFile) ?? giftLog
        collectionLog = SharedFile.read(CollectionLog.self, from: Self.collectionsFile) ?? collectionLog
        partnerMoods.reload()
        us.reload()
        moments.reload()
        notes.reload()
        streak.reload()
        var activity = WidgetActivity.load()
        let pets = activity.takePendingPets()
        guard pets > 0 else { return }
        activity.save()
        for _ in 0..<min(pets, 5) { pet() }
    }

    /// Deletes every store's files from the app group (or Documents) and this phone's preferences; the caller starts
    /// over with a fresh HomeState.
    static func eraseAll() {
        // Pending writes would otherwise land after the files are gone.
        SharedFile.flush()
        let files = FileManager.default
        for url in (try? files.contentsOfDirectory(at: AppGroup.container, includingPropertiesForKeys: nil)) ?? [] {
            try? files.removeItem(at: url)
        }
        if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Leaving the app: the widgets redraw from what was saved here.
    func didEnterBackground() {
        SharedFile.flush()
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
        }
    }

    private func showUs(_ route: UsView.Route?) {
        tab = .us
        usRoute = route
    }
}
