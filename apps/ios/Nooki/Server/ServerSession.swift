import FeatureCanvas
import FeatureInbox
import Foundation
import FeatureMoments
import FeatureOnboarding
import FeaturePairing
import Observation
import Payments
import Persistence
import Transport
import Wire

/// The phone's place on the billet server: the anonymous sign-in, pairing with the partner, and whether this
/// account has a partner. One per launch, and none at all in a build without a server.
@MainActor
@Observable
final class ServerSession {
    let signIn: AnonymousSignInModel
    /// Replaced after a finished pairing, so the next one starts from the choice again.
    private(set) var pairing: PairingModel
    /// Learned by pairing; the saved record keeps it across launches.
    private(set) var isPaired: Bool
    /// Dev server only; nil without dev tools and until `checkDemoPartner()` has asked.
    private(set) var demoPartner: Bool?
    let inbox: InboxModel
    /// Nil until this account has a partner.
    private(set) var reactions: ReactionsModel?
    /// `unpaired` until this account has a partner.
    private(set) var whoKnows: WhoKnowsModel
    /// `unpaired` until this account has a partner.
    private(set) var drawGuess: DrawGuessModel
    @ObservationIgnored private var inboxLink: InboxLink?
    @ObservationIgnored private let photoReceiving = PhotoReceiving()
    /// Set each time the socket is followed.
    @ObservationIgnored private var photos: PhotoSync?
    @ObservationIgnored private var texts: TextNoteSync?
    @ObservationIgnored private weak var shop: ShopModel?
    @ObservationIgnored private weak var lists: ListsModel?
    /// Set each time the socket is followed.
    @ObservationIgnored private var moods: (@MainActor (PartnerCheckIn) -> Void)?
    /// Set each time the socket is followed; holds the last entry.
    @ObservationIgnored private var catEntry: (@MainActor (CatEntry) -> Void)?
    @ObservationIgnored private var lastCatSeq: (@MainActor () -> Int?)?
    /// Set by the open Pick tonight screen; nil while it is closed.
    @ObservationIgnored var matches: (@MainActor (PickMatch) -> Void)?

    @ObservationIgnored private let backend: Backend
    @ObservationIgnored let payments: any Payments

    init(backend: Backend) {
        self.backend = backend
        signIn = AnonymousSignInModel(api: backend.api, keys: backend.keys, accounts: backend.accounts)
        pairing = PairingModel(api: backend.api)
        let saved = try? backend.accounts.load()
        hadSavedAccount = saved != nil
        isPaired = saved?.record.isPaired ?? false
        #if DEBUG
        // For screenshots: `-inboxFixture YES` fills the Inbox from the local fixture instead of the server.
        inbox = UserDefaults.standard.bool(forKey: "inboxFixture") ? InboxFixture.model() : InboxModel(api: backend.api)
        #else
        inbox = InboxModel(api: backend.api)
        #endif
        payments = AppPayments.make(backend.purchases)
        whoKnows = Self.whoKnowsModel(backend, paired: saved?.record.isPaired ?? false)
        drawGuess = Self.drawGuessModel(backend, paired: saved?.record.isPaired ?? false)
        if isPaired { reactions = Self.reactionsModel(backend) }
    }

    private static func whoKnowsModel(_ backend: Backend, paired: Bool) -> WhoKnowsModel {
        let userID = paired ? (try? backend.accounts.load())?.record.userID : nil
        return WhoKnowsModel(sync: userID == nil ? nil : .live(backend.api), viewer: userID.map(UserId.init),
                             catalog: GuessCatalog.current?.questions ?? [])
    }

    private static func drawGuessModel(_ backend: Backend, paired: Bool) -> DrawGuessModel {
        let userID = paired ? (try? backend.accounts.load())?.record.userID : nil
        return DrawGuessModel(sync: userID == nil ? nil : .live(backend.api), viewer: userID.map(UserId.init),
                              words: .bundled)
    }

    nonisolated private static let reactionsKey = "moments.reactions"

    /// Starts from what this phone last saved.
    private static func reactionsModel(_ backend: Backend) -> ReactionsModel? {
        guard let userID = (try? backend.accounts.load())?.record.userID else { return nil }
        let saved = UserDefaults.standard.data(forKey: reactionsKey)
            .flatMap { try? JSONDecoder().decode(ReactionsMachine.Saved.self, from: $0) }
        return ReactionsModel(api: backend.api, viewer: UserId(userID), saved: saved ?? .init()) { saved in
            UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: reactionsKey)
        }
    }

    var onboarding: OnboardingClient { backend.onboarding }
    var catEvents: CatEventsClient { backend.catEvents }
    var streakRemote: StreakRemote { backend.streak }
    var api: APIClient { backend.api }
    var baseURL: URL { backend.baseURL }

    /// Sign-in is the only place an account is saved, and nothing removes one, so this is read once instead of from
    /// the Keychain on every check.
    @ObservationIgnored private let hadSavedAccount: Bool
    var isSignedIn: Bool { signIn.state == .signedIn || hadSavedAccount }

    /// Nil until this account has a partner. Resumes after the last note `seq` kept on this phone, so opening the
    /// canvas does not replay the couple's whole history.
    func liveRoom(defaults: UserDefaults = .standard) -> LiveRoom? {
        guard isPaired else { return nil }
        let accounts = backend.accounts
        let key = "draw.lastNoteSeq"
        let lastSeq = defaults.object(forKey: key) as? Int
        let sync = drawingSync
        return LiveRoom.live(
            baseURL: backend.baseURL, token: { (try? accounts.load())?.token }, lastSeq: lastSeq,
            onNote: { seq, note in
                defaults.set(seq, forKey: key)
                sync?.received(note, seq: seq)
            })
    }

    /// Live over the room socket while the app is in front; nothing without a partner.
    func followInbox(
        _ follows: Bool, photos: PhotoSync? = nil, texts: TextNoteSync? = nil, shop: ShopModel? = nil,
        lists: ListsModel? = nil, moods: (@MainActor (PartnerCheckIn) -> Void)? = nil,
        cat: (@MainActor (CatEntry) -> Void)? = nil, lastCatSeq: (@MainActor () -> Int?)? = nil
    ) {
        if follows, isPaired {
            catEntry = cat
            self.lastCatSeq = lastCatSeq
            self.photos = photos
            self.texts = texts
            self.shop = shop
            self.lists = lists
            self.moods = moods
            if inboxLink == nil {
                let accounts = backend.accounts
                let inbox = inbox
                inboxLink = InboxLink(
                    baseURL: backend.baseURL, token: { (try? accounts.load())?.token },
                    lastSeq: UserDefaults.standard.object(forKey: PhotoSync.cursorKey) as? Int,
                    handlers: .init(
                        unread: { inbox.unreadChanged($0) },
                        photo: { [weak self] in Task { await self?.photos?.receive() } },
                        text: { [weak self] in Task { await self?.texts?.receive() } },
                        reaction: { [weak self] in self?.reactions?.received($0) },
                        lastReactionRev: { [weak self] in self?.reactions?.lastRev },
                        shop: { [weak self] in self?.shop?.received($0) },
                        lists: { [weak self] in self?.lists?.received($0) },
                        mood: { [weak self] in self?.moods?($0) },
                        match: { [weak self] in self?.matches?($0) },
                        guessProgress: { [weak self] in self?.whoKnows.progressed(round: $0, answered: $1) },
                        guessRevealed: { [weak self] in self?.whoKnows.revealed(round: $0, reveal: $1, score: $2) },
                        riddle: { [weak self] in self?.drawGuess.changed($0) },
                        catEntry: { [weak self] in self?.catEntry?($0) },
                        lastCatSeq: { [weak self] in self?.lastCatSeq?() }))
            }
            inboxLink?.connect()
        } else {
            inboxLink?.disconnect()
        }
    }

    /// Nil until this account has a partner.
    var drawingSync: DrawingSync? {
        isPaired ? DrawingSync(api: backend.api, accounts: backend.accounts) : nil
    }

    /// Nil until this account has a partner.
    func photoSync(moments: MomentStore, partner: String) -> PhotoSync? {
        guard isPaired else { return nil }
        return PhotoSync(api: backend.api, accounts: backend.accounts, moments: moments, partner: partner,
                         receiving: photoReceiving)
    }

    /// The pair as the server has it, this account first. `.api(.notFound)` once the server has no pair for it.
    func pair() async throws(TransportError) -> PairResponse {
        try await backend.api.pair()
    }

    /// Keeps a changed catalog for the next launch; offline, the cards stay as they are.
    func refreshDateCatalog() async {
        guard let catalog = try? await backend.api.dateCatalog(),
              catalog.version != (DateCatalog.saved ?? DateCatalog.bundled)?.version else { return }
        SharedFile.write(catalog, to: DateCatalog.file)
    }

    /// Keeps changed questions for the next launch; offline, the round uses the saved or bundled ones.
    func refreshGuessCatalog() async {
        guard let catalog = try? await backend.api.guessCatalog() else { return }
        whoKnows.use(catalog.questions)
        guard catalog.version != GuessCatalog.current?.version else { return }
        SharedFile.write(catalog, to: GuessCatalog.file)
    }

    /// Nil until this account has a partner.
    var shopSync: ShopSync? {
        isPaired ? .live(backend.api) : nil
    }

    /// Nil until this account has a partner.
    var giftSync: GiftSync? {
        isPaired ? .live(backend.api) : nil
    }

    /// Nil until this account has a partner.
    var listSync: ListSync? {
        isPaired ? .live(backend.api) : nil
    }

    /// Nil until this account has a partner.
    var pickTonight: PickTonightSync? {
        isPaired ? .live(backend.api) : nil
    }

    /// Nil until this phone has signed in.
    var titles: TitleSource? {
        isSignedIn ? .live(backend.api) : nil
    }

    /// Nil until this account has a partner.
    func textSync(notes: NoteStore, partner: String) -> TextNoteSync? {
        guard isPaired else { return nil }
        return TextNoteSync(api: backend.api, accounts: backend.accounts, notes: notes, partner: partner)
    }

    /// Asks the server about the demo partner. Any answer but the dev server's, offline included, hides the dev tools.
    func checkDemoPartner() async {
        guard isSignedIn else { return }
        demoPartner = try? await backend.api.demoPartner().paired
    }

    /// Dev server only; the server pairs the bot like a real partner.
    func pairWithDemoPartner() async throws(TransportError) {
        let pair = try await backend.api.createDemoPartner()
        paired(pair.pairId.rawValue)
        demoPartner = true
    }

    /// Dev server only; also deletes the bot.
    func removeDemoPartner() async throws(TransportError) {
        try await backend.api.removeDemoPartner()
        pairEnded()
        demoPartner = false
    }

    /// What each phone saved of the couple stays on it.
    func unpair() async throws(TransportError) {
        try await backend.api.unpair()
        pairEnded()
    }

    /// For good: the two can't pair again.
    func blockPartner() async throws(TransportError) {
        try await backend.api.blockPartner()
        pairEnded()
    }

    /// `note` is the one note or photo the report is about, when there is one.
    func reportPartner(_ reason: ReportReason, note: NoteId? = nil, details: String?) async throws(TransportError) {
        try await backend.api.reportPartner(ReportPartnerRequest(reason: reason, noteId: note, details: details))
    }

    /// Deletes the account on the server, then forgets the session and the account key on this phone, so the next
    /// launch is a first launch. A retry after a lost answer is refused as unauthorized, which means it is gone.
    func deleteAccount() async throws(TransportError) {
        do {
            try await backend.api.deleteAccount(DeleteAccountRequest())
        } catch {
            guard error == .api(.unauthorized) else { throw error }
        }
        try? backend.accounts.clear()
        try? backend.keys.clear()
    }

    private func pairEnded() {
        try? backend.accounts.setPaired(false, nil)
        isPaired = false
        reactions = nil
        whoKnows = Self.whoKnowsModel(backend, paired: false)
        drawGuess = Self.drawGuessModel(backend, paired: false)
    }

    /// Does nothing while the pairing is still under way.
    func pairingFinished() {
        guard case .paired(let pairID) = pairing.state else { return }
        paired(pairID)
    }

    private func paired(_ pairID: String?) {
        try? backend.accounts.setPaired(true, pairID)
        isPaired = true
        reactions = Self.reactionsModel(backend)
        whoKnows = Self.whoKnowsModel(backend, paired: true)
        drawGuess = Self.drawGuessModel(backend, paired: true)
        pairing = PairingModel(api: backend.api)
    }
}
