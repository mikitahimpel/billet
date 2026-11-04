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

    @ObservationIgnored private let backend: Backend

    init(backend: Backend) {
        self.backend = backend
        signIn = AnonymousSignInModel(api: backend.api, keys: backend.keys, accounts: backend.accounts)
        pairing = PairingModel(api: backend.api)
        isPaired = (try? backend.accounts.load())?.record.isPaired ?? false
    }

    var onboarding: OnboardingClient { backend.onboarding }
    var api: APIClient { backend.api }

    var isSignedIn: Bool { signIn.state == .signedIn || (try? backend.accounts.load()) != nil }

    /// Saves a finished pairing on this phone. Does nothing while the pairing is still under way.
    func pairingFinished() {
        guard case .paired(let pairID) = pairing.state else { return }
        try? backend.accounts.setPaired(true, pairID)
        isPaired = true
        pairing = PairingModel(api: backend.api)
    }
}
