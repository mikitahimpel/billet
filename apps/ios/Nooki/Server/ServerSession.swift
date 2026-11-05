import FeatureCanvas
import Foundation
import FeatureOnboarding
import FeaturePairing
import Observation
import Persistence
import Transport

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
    @ObservationIgnored private var inboxLink: InboxLink?

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
    }

    var onboarding: OnboardingClient { backend.onboarding }
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

    /// Keeps the Inbox's count live over the room socket while the app is in front; nothing without a partner.
    func followInbox(_ follows: Bool) {
        if follows, isPaired {
            if inboxLink == nil {
                let accounts = backend.accounts
                let inbox = inbox
                inboxLink = InboxLink(
                    baseURL: backend.baseURL, token: { (try? accounts.load())?.token },
                    unread: { inbox.unreadChanged($0) })
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
        isPaired ? PhotoSync(api: backend.api, accounts: backend.accounts, moments: moments, partner: partner) : nil
    }

    /// Saves a finished pairing on this phone. Does nothing while the pairing is still under way.
    func pairingFinished() {
        guard case .paired(let pairID) = pairing.state else { return }
        try? backend.accounts.setPaired(true, pairID)
        isPaired = true
        pairing = PairingModel(api: backend.api)
    }
}
