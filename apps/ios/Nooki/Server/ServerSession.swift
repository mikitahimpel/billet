import FeatureCanvas
import Foundation
import FeatureMoments
import FeatureOnboarding
import FeaturePairing
import Observation
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
    /// Whether the saved account has a partner. A phone learns it by pairing; the record keeps it across launches.
    private(set) var isPaired: Bool
    /// The pair's activity for the Inbox, and its unread count.
    let inbox: InboxModel
    /// The couple's reactions to each other's photos; nil until this account has a partner.
    private(set) var reactions: ReactionsModel?
    @ObservationIgnored private var inboxLink: InboxLink?
    @ObservationIgnored private let photoReceiving = PhotoReceiving()
    /// What the room socket pages when a photo arrives; set each time the socket is followed.
    @ObservationIgnored private var photos: PhotoSync?
    @ObservationIgnored private var texts: TextNoteSync?

    @ObservationIgnored private let backend: Backend

    init(backend: Backend) {
        self.backend = backend
        signIn = AnonymousSignInModel(api: backend.api, keys: backend.keys, accounts: backend.accounts)
        pairing = PairingModel(api: backend.api)
        isPaired = (try? backend.accounts.load())?.record.isPaired ?? false
        #if DEBUG
        // For screenshots: `-inboxFixture YES` fills the Inbox from the local fixture instead of the server.
        inbox = UserDefaults.standard.bool(forKey: "inboxFixture") ? InboxFixture.model() : InboxModel(api: backend.api)
        #else
        inbox = InboxModel(api: backend.api)
        #endif
        if isPaired { reactions = Self.reactionsModel(backend) }
    }

    nonisolated private static let reactionsKey = "moments.reactions"

    /// Reactions for the saved account, starting from what this phone last saved of them.
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
    var api: APIClient { backend.api }
    var baseURL: URL { backend.baseURL }

    var isSignedIn: Bool { signIn.state == .signedIn || (try? backend.accounts.load()) != nil }

    /// The pair's room socket for the shared canvas; nil until this account has a partner.
    ///
    /// The socket resumes after the last note `seq` it saw, kept on this phone, so opening the canvas does not replay
    /// the couple's whole history every time.
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

    /// Keeps the Inbox's count, the partner's photos into `photos` and reactions live over the room socket while the
    /// app is in front; nothing without a partner.
    func followInbox(_ follows: Bool, photos: PhotoSync? = nil, texts: TextNoteSync? = nil) {
        if follows, isPaired {
            self.photos = photos
            self.texts = texts
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
                        lastReactionRev: { [weak self] in self?.reactions?.lastRev }))
            }
            inboxLink?.connect()
        } else {
            inboxLink?.disconnect()
        }
    }

    /// Fills the drawing widgets and registers push tokens; nil until this account has a partner.
    var drawingSync: DrawingSync? {
        isPaired ? DrawingSync(api: backend.api, accounts: backend.accounts) : nil
    }

    /// Sends the photos taken here to the partner and keeps theirs in `moments` as from `partner`; nil until this
    /// account has a partner.
    func photoSync(moments: MomentStore, partner: String) -> PhotoSync? {
        guard isPaired else { return nil }
        return PhotoSync(api: backend.api, accounts: backend.accounts, moments: moments, partner: partner,
                         receiving: photoReceiving)
    }

    /// The pair as the server has it, this account first. `.api(.notFound)` once the server has no pair for it.
    func pair() async throws(TransportError) -> PairResponse {
        try await backend.api.pair()
    }

    /// The pair's shop in its room; nil until this account has a partner.
    var shopSync: ShopSync? {
        isPaired ? .live(backend.api) : nil
    }

    /// The pair's gift wishes in its room; nil until this account has a partner.
    var giftSync: GiftSync? {
        isPaired ? .live(backend.api) : nil
    }

    /// Sends the text notes written here to the partner and keeps theirs in `notes` as from `partner`; nil until this
    /// account has a partner.
    func textSync(notes: NoteStore, partner: String) -> TextNoteSync? {
        guard isPaired else { return nil }
        return TextNoteSync(api: backend.api, accounts: backend.accounts, notes: notes, partner: partner)
    }

    /// Saves a finished pairing on this phone. Does nothing while the pairing is still under way.
    func pairingFinished() {
        guard case .paired(let pairID) = pairing.state else { return }
        try? backend.accounts.setPaired(true, pairID)
        isPaired = true
        reactions = Self.reactionsModel(backend)
        pairing = PairingModel(api: backend.api)
    }
}
